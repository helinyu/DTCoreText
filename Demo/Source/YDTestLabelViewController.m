//
//  DemoTextViewController.m
//  DTCoreText
//
//  Created by Oliver Drobnik on 1/9/11.
//  Copyright 2011 Drobnik.com. All rights reserved.
//

#import "YDTestLabelViewController.h"
#import <QuartzCore/QuartzCore.h>
#import <MediaPlayer/MediaPlayer.h>

#import "DTTiledLayerWithoutFade.h"
#import "DTWebVideoView.h"


@interface YDTestLabelViewController ()<UITableViewDelegate,UITableViewDataSource>
- (void)_segmentedControlChanged:(id)sender;

- (void)linkPushed:(DTLinkButton *)button;
- (void)linkLongPressed:(UILongPressGestureRecognizer *)gesture;
- (void)debugButton:(UIBarButtonItem *)sender;

@property (nonatomic, strong) NSMutableSet *mediaPlayers;
@property (nonatomic, strong) NSArray *contentViews;

@property (nonatomic, strong) UITableView *tableView;

@end


@implementation YDTestLabelViewController
{
	NSString *_fileName;
	
	UISegmentedControl *_segmentedControl;
	UISegmentedControl *_htmlOutputTypeSegment;
	
	DTAttributedLabel *_textView;
	UITextView *_rangeView;
	UITextView *_charsView;
	UITextView *_htmlView;
	UITextView *_iOS6View;
	
	NSURL *baseURL;
	
	// private
	NSURL *lastActionLink;
	NSMutableSet *mediaPlayers;
	
	BOOL _needsAdjustInsetsOnLayout;
}


#pragma mark NSObject




- (id)init
{
	self = [super init];
	if (self)
	{
		NSMutableArray *items = [[NSMutableArray alloc] initWithObjects:@"View", @"Ranges", @"Chars", @"HTML", nil];
		
#ifdef DTCORETEXT_SUPPORT_NS_ATTRIBUTES
		if (floor(NSFoundationVersionNumber) >= DTNSFoundationVersionNumber_iOS_6_0)
		{
			[items addObject:@"iOS 6"];
		}
#endif
		
		_segmentedControl = [[UISegmentedControl alloc] initWithItems:items];
		_segmentedControl.selectedSegmentIndex = 0;
		[_segmentedControl addTarget:self action:@selector(_segmentedControlChanged:) forControlEvents:UIControlEventValueChanged];
		self.navigationItem.titleView = _segmentedControl;
		
		[self _updateToolbarForMode];
		
		_needsAdjustInsetsOnLayout = YES;
		
		self.automaticallyAdjustsScrollViewInsets = YES;
	}
	return self;
}


- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return YES;
}


#pragma mark UIViewController

- (void)_updateToolbarForMode
{
	NSMutableArray *toolbarItems = [NSMutableArray array];
	
	UIBarButtonItem *debug = [[UIBarButtonItem alloc] initWithTitle:@"Debug Frames" style:UIBarButtonItemStylePlain target:self action:@selector(debugButton:)];
	[toolbarItems addObject:debug];
	
	UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	[toolbarItems addObject:space];
	
	UIBarButtonItem *screenshot = [[UIBarButtonItem alloc] initWithTitle:@"Screenshot" style:UIBarButtonItemStylePlain target:self action:@selector(screenshot:)];
	[toolbarItems addObject:screenshot];
	
	if (_segmentedControl.selectedSegmentIndex == 3)
	{
		if (!_htmlOutputTypeSegment)
		{
			_htmlOutputTypeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Document", @"Fragment"]];
			_htmlOutputTypeSegment.selectedSegmentIndex = 0;
			
			[_htmlOutputTypeSegment addTarget:self action:@selector(_htmlModeChanged:) forControlEvents:UIControlEventValueChanged];
		}
		
		UIBarButtonItem *spacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
		[toolbarItems addObject:spacer];
		
		UIBarButtonItem *htmlMode = [[UIBarButtonItem alloc] initWithCustomView:_htmlOutputTypeSegment];
		
		[toolbarItems addObject:htmlMode];
	}
	
	[self setToolbarItems:toolbarItems];
}

- (void)loadView {
	[super loadView];
	
	CGRect frame = CGRectMake(0.0, 100.f, self.view.frame.size.width, self.view.frame.size.height);
	
	// Create chars view
	_charsView = [[UITextView alloc] initWithFrame:frame];
	_charsView.editable = NO;
	_charsView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:_charsView];
	
	// Create range view
	_rangeView = [[UITextView alloc] initWithFrame:frame];
	_rangeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_rangeView.editable = NO;
	[self.view addSubview:_rangeView];
	
	// Create html view
	_htmlView = [[UITextView alloc] initWithFrame:frame];
	_htmlView.editable = NO;
	_htmlView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:_htmlView];
	
	// Create text view
	_textView = [[DTAttributedLabel alloc] initWithFrame:frame];
	
	// we draw images and links via subviews provided by delegate methods
	_textView.shouldDrawImages = NO;
	_textView.shouldDrawLinks = NO;
	_textView.delegate = self; // delegate for custom sub views
	
	// gesture for testing cursor positions
	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
	[_textView addGestureRecognizer:tap];
	_textView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.view addSubview:_textView];
	
	// create a text view to for testing iOS 6 compatibility
	// Create html view
	_iOS6View = [[UITextView alloc] initWithFrame:frame];
	_iOS6View.editable = NO;
	_iOS6View.contentInset = UIEdgeInsetsMake(10, 0, 10, 0);
	_iOS6View.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:_iOS6View];
	
	self.contentViews = @[_charsView, _rangeView, _htmlView, _textView, _iOS6View];
}


- (NSAttributedString *)_attributedStringForSnippetUsingiOS6Attributes:(BOOL)useiOS6Attributes
{
	// Load HTML data
	NSString *readmePath = [[NSBundle mainBundle] pathForResource:_fileName ofType:nil];
	NSString *html = [NSString stringWithContentsOfFile:readmePath encoding:NSUTF8StringEncoding error:NULL];
	NSData *data = [html dataUsingEncoding:NSUTF8StringEncoding];
	
	// Create attributed string from HTML
	CGSize maxImageSize = CGSizeMake(self.view.bounds.size.width - 20.0, self.view.bounds.size.height - 20.0);
	
	// example for setting a willFlushCallback, that gets called before elements are written to the generated attributed string
	void (^callBackBlock)(DTHTMLElement *element) = ^(DTHTMLElement *element) {
		
		// the block is being called for an entire paragraph, so we check the individual elements
		
		for (DTHTMLElement *oneChildElement in element.childNodes)
		{
			// if an element is larger than twice the font size put it in it's own block
			if (oneChildElement.displayStyle == DTHTMLElementDisplayStyleInline && oneChildElement.textAttachment.displaySize.height > 2.0 * oneChildElement.fontDescriptor.pointSize)
			{
				oneChildElement.displayStyle = DTHTMLElementDisplayStyleBlock;
				oneChildElement.paragraphStyle.minimumLineHeight = element.textAttachment.displaySize.height;
				oneChildElement.paragraphStyle.maximumLineHeight = element.textAttachment.displaySize.height;
			}
		}
	};
	
	NSMutableDictionary *options = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithFloat:1.0], NSTextSizeMultiplierDocumentOption, [NSValue valueWithCGSize:maxImageSize], DTMaxImageSize,
									@"Times New Roman", DTDefaultFontFamily,  @"purple", DTDefaultLinkColor, @"red", DTDefaultLinkHighlightColor, callBackBlock, DTWillFlushBlockCallBack, nil];
	
	if (useiOS6Attributes)
	{
		[options setObject:[NSNumber numberWithBool:YES] forKey:DTUseiOS6Attributes];
	}
	
	[options setObject:[NSURL fileURLWithPath:readmePath] forKey:NSBaseURLDocumentOption];
	
	NSAttributedString *string = [[NSAttributedString alloc] initWithHTMLData:data options:options documentAttributes:NULL];
	
	return string;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
//	CGRect bounds = self.view.bounds;
//	_textView.frame = bounds;
	_tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
	_tableView.dataSource = self;
	_tableView.delegate = self;
	[_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:NSStringFromClass([UITableViewCell class])];
	[self.view addSubview:_tableView];
	
	// Display string
	_textView.backgroundColor = [UIColor redColor];
	_textView.shouldDrawLinks = NO; // we draw them in DTLinkButton
	NSAttributedString *attrString = [self _attributedStringForSnippetUsingiOS6Attributes:NO];
//	CGFloat height = [_textView getRenderH:attrString width:[UIScreen mainScreen].bounds.size.width];
	CGFloat height = [_textView getRenderHeight:attrString width:_textView.bounds.size.width];
	_textView.frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, height);
	_textView.attributedString = attrString;
	_tableView.tableHeaderView = _textView;
	[self _segmentedControlChanged:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return 10;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([UITableViewCell class]) forIndexPath:indexPath];
	cell.textLabel.text = @"hahah";
	return  cell;
}


// this is only called on >= iOS 5
- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	
	//	if (![self respondsToSelector:@selector(topLayoutGuide)] || !_needsAdjustInsetsOnLayout)
	//	{
	//		return;
	//	}
	//
	//	// this also compiles with iOS 6 SDK, but will work with later SDKs too
	//	CGFloat topInset = [[self valueForKeyPath:@"topLayoutGuide.length"] floatValue];
	//	CGFloat bottomInset = [[self valueForKeyPath:@"bottomLayoutGuide.length"] floatValue];
	//
	//	UIEdgeInsets outerInsets = UIEdgeInsetsMake(topInset, 0, bottomInset, 0);
	//	UIEdgeInsets innerInsets = outerInsets;
	//	innerInsets.left += 10;
	//	innerInsets.right += 10;
	//	innerInsets.top += 10;
	//	innerInsets.bottom += 10;
	//
	//	CGPoint innerScrollOffset = CGPointMake(-innerInsets.left, -innerInsets.top);
	//	CGPoint outerScrollOffset = CGPointMake(-outerInsets.left, -outerInsets.top);
	//
	//	_textView.contentInset = innerInsets;
	//	_textView.contentOffset = innerScrollOffset;
	//	_textView.scrollIndicatorInsets = outerInsets;
	//
	//	_iOS6View.contentInset = outerInsets;
	//	_iOS6View.contentOffset = outerScrollOffset;
	//	_iOS6View.scrollIndicatorInsets = outerInsets;
	//
	//	_charsView.contentInset = outerInsets;
	//	_charsView.contentOffset = outerScrollOffset;
	//	_charsView.scrollIndicatorInsets = outerInsets;
	//
	//	_rangeView.contentInset = outerInsets;
	//	_rangeView.contentOffset = outerScrollOffset;
	//	_rangeView.scrollIndicatorInsets = outerInsets;
	//
	//	_htmlView.contentInset = outerInsets;
	//	_htmlView.contentOffset = outerScrollOffset;
	//	_htmlView.scrollIndicatorInsets = outerInsets;
	//
	//	_needsAdjustInsetsOnLayout = NO;
}

#pragma mark Private Methods

- (void)updateDetailViewForIndex:(NSUInteger)index
{
	switch (index)
	{
		case 1:
		{
			NSMutableString *dumpOutput = [[NSMutableString alloc] init];
			NSDictionary *attributes = nil;
			NSRange effectiveRange = NSMakeRange(0, 0);
			
			if ([_textView.attributedString length])
			{
				
				while ((attributes = [_textView.attributedString attributesAtIndex:effectiveRange.location effectiveRange:&effectiveRange]))
				{
					[dumpOutput appendFormat:@"Range: (%lu, %lu), %@\n\n", (unsigned long)effectiveRange.location, (unsigned long)effectiveRange.length, attributes];
					effectiveRange.location += effectiveRange.length;
					
					if (effectiveRange.location >= [_textView.attributedString length])
					{
						break;
					}
				}
			}
			_rangeView.text = dumpOutput;
			break;
		}
		case 2:
		{
			// Create characters view
			NSMutableString *dumpOutput = [[NSMutableString alloc] init];
			NSData *dump = [[_textView.attributedString string] dataUsingEncoding:NSUTF8StringEncoding];
			for (NSInteger i = 0; i < [dump length]; i++)
			{
				char *bytes = (char *)[dump bytes];
				char b = bytes[i];
				
				[dumpOutput appendFormat:@"%li: %x %c\n", (long)i, b, b];
			}
			_charsView.text = dumpOutput;
			
			break;
		}
		case 3:
		{
			if (_htmlOutputTypeSegment.selectedSegmentIndex == 0)
			{
				_htmlView.text = [_textView.attributedString htmlString];
			}
			else
			{
				_htmlView.text = [_textView.attributedString htmlFragment];
			}
			
			break;
		}
		case 4:
		{
			if (![_iOS6View.attributedText length])
			{
				_iOS6View.attributedText = [self _attributedStringForSnippetUsingiOS6Attributes:YES];
			}
		}
	}
}

- (void)_segmentedControlChanged:(id)sender {
	UIScrollView *selectedView = _textView;
	
	// Hide all views except for the selected view to not conflict with VoiceOver
	for (UIView *view in self.contentViews)
		view.hidden = YES;
	selectedView.hidden = NO;
}

- (void)_htmlModeChanged:(id)sender
{
	// refresh only this tab
	[self updateDetailViewForIndex:_segmentedControl.selectedSegmentIndex];
}


#pragma mark Custom Views on Text

- (UIView *)attributedTextContentView:(DTAttributedTextContentView *)attributedTextContentView viewForAttributedString:(NSAttributedString *)string frame:(CGRect)frame
{
	NSDictionary *attributes = [string attributesAtIndex:0 effectiveRange:NULL];
	
	NSURL *URL = [attributes objectForKey:DTLinkAttribute];
	NSString *identifier = [attributes objectForKey:DTGUIDAttribute];
	
	
	DTLinkButton *button = [[DTLinkButton alloc] initWithFrame:frame];
	button.URL = URL;
	button.minimumHitSize = CGSizeMake(25, 25); // adjusts it's bounds so that button is always large enough
	button.GUID = identifier;
	button.backgroundColor = [UIColor greenColor];
	
	// get image with normal link text
	UIImage *normalImage = [attributedTextContentView contentImageWithBounds:frame options:DTCoreTextLayoutFrameDrawingDefault];
	[button setImage:normalImage forState:UIControlStateNormal];
	
	// get image for highlighted link text
	UIImage *highlightImage = [attributedTextContentView contentImageWithBounds:frame options:DTCoreTextLayoutFrameDrawingDrawLinksHighlighted];
	[button setImage:highlightImage forState:UIControlStateHighlighted];
	
	// use normal push action for opening URL
	[button addTarget:self action:@selector(linkPushed:) forControlEvents:UIControlEventTouchUpInside];
	
	// demonstrate combination with long press
	UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(linkLongPressed:)];
	[button addGestureRecognizer:longPress];
	
	return button;
}

- (UIView *)attributedTextContentView:(DTAttributedTextContentView *)attributedTextContentView viewForAttachment:(DTTextAttachment *)attachment frame:(CGRect)frame
{
	if ([attachment isKindOfClass:[DTVideoTextAttachment class]])
	{
		NSURL *url = (id)attachment.contentURL;
		
		// we could customize the view that shows before playback starts
		UIView *grayView = [[UIView alloc] initWithFrame:frame];
		grayView.backgroundColor = [DTColor blackColor];
		
		// find a player for this URL if we already got one
		MPMoviePlayerController *player = nil;
		for (player in self.mediaPlayers)
		{
			if ([player.contentURL isEqual:url])
			{
				break;
			}
		}
		
		if (!player)
		{
			player = [[MPMoviePlayerController alloc] initWithContentURL:url];
			[self.mediaPlayers addObject:player];
		}
		
#if __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_4_2
		NSString *airplayAttr = [attachment.attributes objectForKey:@"x-webkit-airplay"];
		if ([airplayAttr isEqualToString:@"allow"])
		{
			if ([player respondsToSelector:@selector(setAllowsAirPlay:)])
			{
				player.allowsAirPlay = YES;
			}
		}
#endif
		
		NSString *controlsAttr = [attachment.attributes objectForKey:@"controls"];
		if (controlsAttr)
		{
			player.controlStyle = MPMovieControlStyleEmbedded;
		}
		else
		{
			player.controlStyle = MPMovieControlStyleNone;
		}
		
		NSString *loopAttr = [attachment.attributes objectForKey:@"loop"];
		if (loopAttr)
		{
			player.repeatMode = MPMovieRepeatModeOne;
		}
		else
		{
			player.repeatMode = MPMovieRepeatModeNone;
		}
		
		NSString *autoplayAttr = [attachment.attributes objectForKey:@"autoplay"];
		if (autoplayAttr)
		{
			player.shouldAutoplay = YES;
		}
		else
		{
			player.shouldAutoplay = NO;
		}
		
		[player prepareToPlay];
		
		player.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		player.view.frame = grayView.bounds;
		[grayView addSubview:player.view];
		
		return grayView;
	}
	else if ([attachment isKindOfClass:[DTImageTextAttachment class]])
	{
		// if the attachment has a hyperlinkURL then this is currently ignored
		DTLazyImageView *imageView = [[DTLazyImageView alloc] initWithFrame:frame];
		imageView.delegate = self;
		
		// sets the image if there is one
		imageView.image = [(DTImageTextAttachment *)attachment image];
		imageView.userInteractionEnabled = YES;
		UITapGestureRecognizer *tapGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
		[imageView addGestureRecognizer:tapGR];
		
		// url for deferred loading
		imageView.url = attachment.contentURL;
		imageView.tapBlock = ^{
			NSLog(@"tap clock");
		};
		// if there is a hyperlink then add a link button on top of this image
		if (attachment.hyperLinkURL)
		{
			// NOTE: this is a hack, you probably want to use your own image view and touch handling
			// also, this treats an image with a hyperlink by itself because we don't have the GUID of the link parts
			imageView.userInteractionEnabled = YES;
			
			DTLinkButton *button = [[DTLinkButton alloc] initWithFrame:imageView.bounds];
			button.URL = attachment.hyperLinkURL;
			button.minimumHitSize = CGSizeMake(25, 25); // adjusts it's bounds so that button is always large enough
			button.GUID = attachment.hyperLinkGUID;
			
			// use normal push action for opening URL
			[button addTarget:self action:@selector(linkPushed:) forControlEvents:UIControlEventTouchUpInside];
			
			// demonstrate combination with long press
			UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(linkLongPressed:)];
			[button addGestureRecognizer:longPress];
			
			[imageView addSubview:button];
		}
		
		return imageView;
	}
	else if ([attachment isKindOfClass:[DTIframeTextAttachment class]])
	{
		DTWebVideoView *videoView = [[DTWebVideoView alloc] initWithFrame:frame];
		videoView.attachment = attachment;
		
		return videoView;
	}
	else if ([attachment isKindOfClass:[DTObjectTextAttachment class]])
	{
		// somecolorparameter has a HTML color
		NSString *colorName = [attachment.attributes objectForKey:@"somecolorparameter"];
		UIColor *someColor = DTColorCreateWithHTMLName(colorName);
		
		UIView *someView = [[UIView alloc] initWithFrame:frame];
		someView.backgroundColor = someColor;
		someView.layer.borderWidth = 1;
		someView.layer.borderColor = [UIColor blackColor].CGColor;
		
		someView.accessibilityLabel = colorName;
		someView.isAccessibilityElement = YES;
		
		return someView;
	}
	
	return nil;
}

- (void)onTap:(UITapGestureRecognizer *)recognizer {
	NSLog(@"recognizer ：%@",recognizer);
}

- (BOOL)attributedTextContentView:(DTAttributedTextContentView *)attributedTextContentView shouldDrawBackgroundForTextBlock:(DTTextBlock *)textBlock frame:(CGRect)frame context:(CGContextRef)context forLayoutFrame:(DTCoreTextLayoutFrame *)layoutFrame
{
	UIBezierPath *roundedRect = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(frame,1,1) cornerRadius:10];
	
	CGColorRef color = [textBlock.backgroundColor CGColor];
	if (color)
	{
		CGContextSetFillColorWithColor(context, color);
		CGContextAddPath(context, [roundedRect CGPath]);
		CGContextFillPath(context);
		
		CGContextAddPath(context, [roundedRect CGPath]);
		CGContextSetRGBStrokeColor(context, 0, 0, 0, 1);
		CGContextStrokePath(context);
		return NO;
	}
	
	return YES; // draw standard background
}


#pragma mark Actions

- (void)linkPushed:(DTLinkButton *)button
{
	NSURL *URL = button.URL;
	
	if ([[UIApplication sharedApplication] canOpenURL:[URL absoluteURL]])
	{
		[[UIApplication sharedApplication] openURL:[URL absoluteURL]];
	}
	else
	{
		if (![URL host] && ![URL path])
		{
			
			// possibly a local anchor link
			NSString *fragment = [URL fragment];
			
			if (fragment)
			{
//				[_textView scrollToAnchorNamed:fragment animated:NO];
			}
		}
	}
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if (buttonIndex != actionSheet.cancelButtonIndex)
	{
		[[UIApplication sharedApplication] openURL:[self.lastActionLink absoluteURL]];
	}
}

- (void)linkLongPressed:(UILongPressGestureRecognizer *)gesture
{
	if (gesture.state == UIGestureRecognizerStateBegan)
	{
		DTLinkButton *button = (id)[gesture view];
		button.highlighted = NO;
		self.lastActionLink = button.URL;
		
		if ([[UIApplication sharedApplication] canOpenURL:[button.URL absoluteURL]])
		{
			UIActionSheet *action = [[UIActionSheet alloc] initWithTitle:[[button.URL absoluteURL] description] delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Open in Safari", nil];
			[action showFromRect:button.frame inView:button.superview animated:YES];
		}
	}
}

- (void)handleTap:(UITapGestureRecognizer *)gesture
{
	if (gesture.state == UIGestureRecognizerStateRecognized)
	{
		CGPoint location = [gesture locationInView:_textView];
		NSUInteger tappedIndex = [_textView closestCursorIndexToPoint:location];
		
		NSString *plainText = [_textView.attributedString string];
		NSString *tappedChar = [plainText substringWithRange:NSMakeRange(tappedIndex, 1)];
		
		__block NSRange wordRange = NSMakeRange(0, 0);
		
		[plainText enumerateSubstringsInRange:NSMakeRange(0, [plainText length]) options:NSStringEnumerationByWords usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
			if (NSLocationInRange(tappedIndex, enclosingRange))
			{
				*stop = YES;
				wordRange = substringRange;
			}
		}];
		
		NSString *word = [plainText substringWithRange:wordRange];
		NSLog(@"index: %lu , char: '%@' , word: '%@'", (unsigned long)tappedIndex, tappedChar, word);
	}
}

- (void)debugButton:(UIBarButtonItem *)sender
{
	[DTCoreTextLayoutFrame setShouldDrawDebugFrames:![DTCoreTextLayoutFrame shouldDrawDebugFrames]];
	[_textView setNeedsDisplay];
}

- (void)screenshot:(UIBarButtonItem *)sender
{
	UIWindow *keyWindow = [[UIApplication sharedApplication] keyWindow];
	
	CGRect rect = [keyWindow bounds];
	UIGraphicsBeginImageContextWithOptions(rect.size, YES, 0);
	
	CGContextRef context = UIGraphicsGetCurrentContext();
	[keyWindow.layer renderInContext:context];
	
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	
	[[UIPasteboard generalPasteboard] setImage:image];
}

#pragma mark - DTLazyImageViewDelegate

- (void)lazyImageView:(DTLazyImageView *)lazyImageView didChangeImageSize:(CGSize)size {
	NSURL *url = lazyImageView.url;
	CGSize imageSize = size;
	
	NSPredicate *pred = [NSPredicate predicateWithFormat:@"contentURL == %@", url];
	
	BOOL didUpdate = NO;
	
	// update all attachments that match this URL (possibly multiple images with same size)
	for (DTTextAttachment *oneAttachment in [_textView.layoutFrame textAttachmentsWithPredicate:pred])
	{
		// update attachments that have no original size, that also sets the display size
		if (CGSizeEqualToSize(oneAttachment.originalSize, CGSizeZero))
		{
			oneAttachment.originalSize = imageSize;
			
			didUpdate = YES;
		}
	}
	
	if (didUpdate)
	{
		// layout might have changed due to image sizes
		// do it on next run loop because a layout pass might be going on
		dispatch_async(dispatch_get_main_queue(), ^{
			[_textView relayoutText];
		});
	}
}

#pragma mark Properties

- (NSMutableSet *)mediaPlayers
{
	if (!mediaPlayers)
	{
		mediaPlayers = [[NSMutableSet alloc] init];
	}
	
	return mediaPlayers;
}

@synthesize fileName = _fileName;
@synthesize lastActionLink;
@synthesize mediaPlayers;
@synthesize baseURL;

- (void)attributedTextContentView:(DTAttributedTextContentView *)attributedTextContentView willDrawLayoutFrame:(DTCoreTextLayoutFrame *)layoutFrame inContext:(CGContextRef)context {
	NSLog(@"willDrawLayoutFrame");
}

- (void)attributedTextContentView:(DTAttributedTextContentView *)attributedTextContentView didDrawLayoutFrame:(DTCoreTextLayoutFrame *)layoutFrame inContext:(CGContextRef)context {
	NSLog(@"didDrawLayoutFrame :%@",layoutFrame);
}

@end
