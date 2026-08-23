//
//  ADDataViewController.m
//  AppData
//
//  Created by Fouad Raheb on 6/29/20.
//

#import "ADDataViewController.h"
#import "ADDataPresentationManager.h"
#import "ADExpandableSectionHeaderView.h"
#import "ADTitleSectionHeaderView.h"
#import "ADMainDataSource.h"
#import "ADMoreDataSource.h"
#import <objc/runtime.h>

#ifndef IS_IPAD
#define IS_IPAD (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#endif

@interface ADDataViewController () <UIGestureRecognizerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic, strong) ADDataPresentationManager *presentationManager;

@property (nonatomic, strong) UIVisualEffectView *contentView;

@property (nonatomic, strong) ADAppData *appData;

@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UIButton *nameLabel;
@property (nonatomic, strong) UIButton *nameEditButton;
@property (nonatomic, strong) UIButton *identifierLabel;
@property (nonatomic, strong) UIButton *identifierCopyButton;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UIButton *appStoreButton;

@property (nonatomic, strong) ADMainDataSource *mainDataSource;
@property (nonatomic, strong) ADMoreDataSource *moreDataSource;

@property (nonatomic, assign) BOOL isCopyingIdentifier;

@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *screenEdgeGesture;
@property (nonatomic, weak) UIScrollView *desktopScrollView;

@end

@implementation ADDataViewController

#pragma mark - Icon Helpers

static inline SBIconImageView *ADGetIconImageViewFromIconView(SBIconView *iconView) {
    if (!iconView) return nil;

    SBIconImageView *iconImageView = nil;

    if ([iconView respondsToSelector:@selector(iconImageView)]) {
        iconImageView = [iconView performSelector:@selector(iconImageView)];
    } else if ([iconView respondsToSelector:@selector(_iconImageView)]) {
        iconImageView = [iconView _iconImageView];
    } else {
        Ivar ivar = class_getInstanceVariable(object_getClass(iconView), "_iconImageView");
        if (ivar) {
            iconImageView = object_getIvar(iconView, ivar);
        }
    }

    if (!iconImageView) {
        for (UIView *subview in iconView.subviews) {
            if ([subview isKindOfClass:NSClassFromString(@"SBIconImageView")]) {
                iconImageView = (SBIconImageView *)subview;
                break;
            }
        }
    }

    return iconImageView;
}

static inline CGFloat ADIconContinuousCornerRadiusForSide(CGFloat side) {
    // 58pt 图标用 13 左右会比较接近系统那种“微圆”
    return round(side * 0.224f);
}

static UIImage *ADRoundedSquareIconImage(UIImage *image) {
    if (!image) return nil;

    CGSize size = image.size;
    CGFloat side = MIN(size.width, size.height);
    CGRect cropRect = CGRectMake((size.width - side) * 0.5f,
                                 (size.height - side) * 0.5f,
                                 side,
                                 side);

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, image.scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    CGFloat radius = ADIconContinuousCornerRadiusForSide(side);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side)
                                                    cornerRadius:radius];
    [path addClip];

    [image drawAtPoint:CGPointMake(-cropRect.origin.x, -cropRect.origin.y)];

    UIImage *roundedImage = UIGraphicsGetImageFromCurrentImageContext();
    CGContextFlush(ctx);
    UIGraphicsEndImageContext();

    return roundedImage;
}

- (void)applyRoundedStyleToPreviewIconView {
    self.iconImageView.clipsToBounds = YES;
    self.iconImageView.layer.masksToBounds = YES;
    self.iconImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.iconImageView.layer.cornerRadius = ADIconContinuousCornerRadiusForSide(58.0);

    if (@available(iOS 13.0, *)) {
        self.iconImageView.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

- (instancetype)initWithAppData:(ADAppData *)data {
    if (self = [super init]) {
        ADDataPresentationConfiguration *config = [[ADDataPresentationConfiguration alloc] init];
        
        self.presentationManager = [[ADDataPresentationManager alloc] initWithConfiguration:config];
        
        self.transitioningDelegate = self.presentationManager;
        self.modalPresentationStyle = UIModalPresentationCustom;
        
        self.appData = data;

        self.mainDataSource = [[ADMainDataSource alloc] initWithAppData:self.appData dataViewController:self];
        self.moreDataSource = [[ADMoreDataSource alloc] initWithAppData:self.appData dataViewController:self];
        
        [self initializeViews];
        
        [self configureViewWithAppData];
    }
    return self;
}

#pragma mark - Used from Force Touch Menu

+ (void)presentControllerFromSBIconView:(SBIconView *)iconView fromContextMenu:(BOOL)contextMenu {
    if (!iconView) {
        [self showAlertWithTitle:@"AppData" message:[NSString stringWithFormat:@"Could not fetch app data.\n\nError: Empty icon view."]];
        return;
    }
    
    // Find Icon Image View (iOS 15/16+ 兼容)
    SBIconImageView *_iconImageView = nil;
    if ([iconView respondsToSelector:@selector(iconImageView)]) {
        _iconImageView = [iconView performSelector:@selector(iconImageView)];
    } else if ([iconView respondsToSelector:@selector(_iconImageView)]) {
        _iconImageView = [iconView _iconImageView];
    } else {
        _iconImageView = object_getIvar(iconView, class_getInstanceVariable(object_getClass(iconView), "_iconImageView"));
    }
    
    if (!_iconImageView) {
        for (UIView *subview in iconView.subviews) {
            if ([subview isKindOfClass:NSClassFromString(@"SBIconImageView")]) {
                _iconImageView = (SBIconImageView *)subview;
                break;
            }
        }
    }
    
    if (!_iconImageView) {
        [self showAlertWithTitle:@"AppData" message:[NSString stringWithFormat:@"Could not fetch app data.\n\nError: could not find icon image view."]];
        return;
    }
    [self presentControllerFromSBIconImageView:_iconImageView iconView:iconView fromContextMenu:contextMenu];
}

#pragma mark - Used from Swipe Up

+ (void)presentControllerFromSBIconImageView:(SBIconImageView *)iconImageView fromContextMenu:(BOOL)contextMenu {
    SBIconView *iconView = (SBIconView *)[iconImageView superview];
    if (![iconView respondsToSelector:@selector(icon)]) {
        NSLog(@"iconView: %@", iconView);
        iconView = (SBIconView *)[iconView superview];
    }
    [self presentControllerFromSBIconImageView:iconImageView iconView:iconView fromContextMenu:contextMenu];
}

#pragma mark - Internal

+ (void)presentControllerFromSBIconImageView:(SBIconImageView *)iconImageView iconView:(SBIconView *)iconView fromContextMenu:(BOOL)contextMenu {
    NSLog(@"iconImageView: %@", iconImageView);
    
    // 获取 RootController，增强 iOS 15/16 兼容性
    UIViewController *rootController = nil;
    if ([iconImageView respondsToSelector:@selector(_viewControllerForAncestor)]) {
        rootController = [iconImageView _viewControllerForAncestor];
    } else if ([iconView respondsToSelector:@selector(_viewControllerForAncestor)]) {
        rootController = [iconView _viewControllerForAncestor];
    }
    
    // Fallback 到 window root controller
    if (!rootController) {
        UIWindow *window = iconView.window;
        if (!window) window = [UIApplication sharedApplication].keyWindow;
        rootController = window.rootViewController;
        while (rootController.presentedViewController) {
            rootController = rootController.presentedViewController;
        }
    }
    
    NSLog(@"rootController: %@", rootController);
    
    // iOS 15+ 兼容新的 BundleID 提取逻辑
    if ([iconView respondsToSelector:@selector(icon)] && [iconImageView respondsToSelector:@selector(contentsImage)]) {
        SBIcon *icon = iconView.icon;
        NSString *bundleID = nil;
        if ([icon respondsToSelector:@selector(applicationBundleIdentifier)]) {
            bundleID = [icon performSelector:@selector(applicationBundleIdentifier)];
        } else if ([icon respondsToSelector:@selector(applicationBundleID)]) {
            bundleID = [icon performSelector:@selector(applicationBundleID)];
        }
        
        if (!bundleID) {
            [self showAlertFromViewController:rootController
                                        title:@"AppData"
                                      message:@"Could not fetch bundle ID."
                                  cancelTitle:@"Okay"];
            return;
        }
        
        ADAppData *appData = [ADAppData appDataForBundleIdentifier:bundleID iconImage:iconImageView.contentsImage];
        if (appData) {
            appData.iconView = iconView;
            
            [[UISelectionFeedbackGenerator new] selectionChanged];
            ADDataViewController *dataViewController = [[ADDataViewController alloc] initWithAppData:appData];
            
            // ================= 新增：拦截桌面滑动 =================
            UIView *superview = iconView.superview;
            while (superview) {
                if ([superview isKindOfClass:NSClassFromString(@"SBIconScrollView")] || [superview isKindOfClass:[UIScrollView class]]) {
                    UIScrollView *scrollView = (UIScrollView *)superview;
                    dataViewController.desktopScrollView = scrollView;
                    // 禁用再启用 pan 手势，强制打断当前的手指滑动事件追踪
                    scrollView.panGestureRecognizer.enabled = NO;
                    scrollView.panGestureRecognizer.enabled = YES;
                    scrollView.scrollEnabled = NO; // 临时禁用滚动
                    break;
                }
                superview = superview.superview;
            }
            // ====================================================

            if (IS_IPAD) {
                dataViewController.contentView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
                dataViewController.presentationManager.configuration.fadeAnimationAlpha = 0;
                dataViewController.presentationManager.configuration.fadeAnimation = YES;
                dataViewController.presentationManager.configuration.customFrameHandler = ^CGRect(UIView *containerView) {
                    CGSize size = CGSizeMake(containerView.frame.size.width * 0.5, containerView.frame.size.height * 0.5);
                    return CGRectMake(containerView.frame.size.width/2 - size.width/2,
                                      containerView.frame.size.height/2 - size.height/2,
                                      size.width, size.height);
                };
                if (contextMenu) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        [rootController presentViewController:dataViewController animated:YES completion:nil];
                    });
                } else {
                    [rootController presentViewController:dataViewController animated:YES completion:nil];
                }
            } else {
                dataViewController.dockDismissed = [self.class dismissFloatingDockIfNeededWithCompletion:nil];
                [rootController presentViewController:dataViewController animated:YES completion:nil];
            }
        }
    } else {
        [self showAlertFromViewController:rootController
                                    title:@"AppData"
                                  message:[NSString stringWithFormat:@"Could not fetch app data.\n\n%@ is not a valid icon class.", [iconView class]]
                              cancelTitle:@"Okay"];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    tapGesture.delegate = self;
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];
    
    UISwipeGestureRecognizer *swipeUpDownGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    swipeUpDownGesture.delegate = self;
    [swipeUpDownGesture setDirection:UISwipeGestureRecognizerDirectionDown | UISwipeGestureRecognizerDirectionUp];
    [self.view addGestureRecognizer:swipeUpDownGesture];
    
    self.screenEdgeGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(screenEdgeSwiped:)];
    if (self.view.semanticContentAttribute == UISemanticContentAttributeForceRightToLeft) {
        self.screenEdgeGesture.edges = UIRectEdgeRight;
    } else {
        self.screenEdgeGesture.edges = UIRectEdgeLeft;
    }
}

- (void)screenEdgeSwiped:(UIScreenEdgePanGestureRecognizer *)screenGesture {
    [self switchTableViews];
}

- (void)dismiss {
    [self dismissAppDataControllerAnimated:YES completion:nil];
}

- (void)dismissAppDataControllerAnimated:(BOOL)animated completion:(void(^)(void))completion {
    // 恢复逻辑已经转移到下方生命周期中，这里只需负责关闭 Controller
    [self dismissViewControllerAnimated:animated completion:completion];
}

// ================= 核心修复：利用生命周期自动恢复防滑与 Dock =================
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // isBeingDismissed 判断确保：只有在面板真正被关闭时才恢复。
    // 如果是从面板弹出相册选取图片，不触发恢复。
    if (self.isBeingDismissed) {
        if (self.dockDismissed) {
            self.dockDismissed = NO;
            [self.class presentFloatingDockIfNeeded];
        }
        
        if (self.desktopScrollView) {
            self.desktopScrollView.scrollEnabled = YES;
        }
    }
}

- (void)dealloc {
    // 兜底保障：当应用进入后台 SpringBoard 直接回收内存强制销毁时，强制恢复桌面滑动
    if (_desktopScrollView) {
        _desktopScrollView.scrollEnabled = YES;
    }
}
// =======================================================================

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *touchedView = touch.view;
    
    if ([touchedView isKindOfClass:NSClassFromString(@"UITableViewCellContentView")]) {
        return NO;
    }
    
    if ([touchedView isKindOfClass:[UIButton class]] || [touchedView isDescendantOfView:self.contentView]) {
        return NO;
    }
    
    return YES;
}

- (void)configureViewWithAppData {
    // 初始化时，如果本地有自定义图标，则读取显示，否则显示原始图标
    NSString *bundleID = self.appData.bundleIdentifier;
    NSString *customPath = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/AppDataIcons/%@.png", bundleID];
    if ([[NSFileManager defaultManager] fileExistsAtPath:customPath]) {
        self.iconImageView.image = [UIImage imageWithContentsOfFile:customPath];
    } else {
        self.iconImageView.image = self.appData.iconImage;
    }

    [self applyRoundedStyleToPreviewIconView];
    
    self.appStoreButton.hidden = ![self.appData hasAppStoreApp];
    
    if ([self.appData isApplication]) {
        NSString *customIconName = self.appData.customIconName;
        [self.nameLabel setTitle:customIconName ?: self.appData.name forState:UIControlStateNormal];
        [self.identifierLabel setTitle:self.appData.bundleIdentifier forState:UIControlStateNormal];
        if (self.appData.diskUsage > 0 && self.appData.diskUsageString) {
            self.versionLabel.text = [self.appData.version stringByAppendingFormat:@"  —  %@", self.appData.diskUsageString];
        } else {
            self.versionLabel.text = self.appData.version;
        }
    } else {
        [self.nameLabel setTitle:@"Not an Application" forState:UIControlStateNormal];
        [self.nameLabel setEnabled:NO];
        
        [self.identifierLabel setTitle:@"No Bundle Identifier" forState:UIControlStateNormal];
        [self.identifierLabel setEnabled:NO];
        
        [self.versionLabel setText:@"—"];
        
        self.identifierCopyButton.hidden = YES;
        self.nameEditButton.hidden = YES;
    }
}

- (void)initializeViews {
    self.contentView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentView.clipsToBounds = YES;
    self.contentView.layer.cornerRadius = 15;
    self.contentView.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMinXMinYCorner;
    [self.view addSubview:self.contentView];
    [self.contentView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [self.contentView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [self.contentView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [self.contentView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    
    UIView *containerView = [UIView new];
    containerView.backgroundColor = [UIColor clearColor];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView.contentView addSubview:containerView];
    [containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor].active = YES;
    [containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor].active = YES;
    [containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor].active = YES;
    [containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor].active = YES;

    [self addSubviewsToContainer:containerView];
}

- (void)addSubviewsToContainer:(UIView *)containerView {
    self.appStoreButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.appStoreButton setImage:[[ADHelper imageNamed:@"AppStoreButton"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    [self.appStoreButton addTarget:self action:@selector(didTapAppStoreButton:) forControlEvents:UIControlEventTouchUpInside];
    self.appStoreButton.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:self.appStoreButton];
    [self.appStoreButton.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:9].active = YES;
    [self.appStoreButton.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-9].active = YES;
    [self.appStoreButton setContentEdgeInsets:UIEdgeInsetsMake(6, 6, 6, 6)];
    [self.appStoreButton.heightAnchor constraintEqualToConstant:30].active = YES;
    [self.appStoreButton.widthAnchor constraintEqualToConstant:30].active = YES;
    
    self.iconImageView = [[UIImageView alloc] init];
    self.iconImageView.userInteractionEnabled = NO;
    [self.iconImageView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [containerView addSubview:self.iconImageView];
    [self.iconImageView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:15].active = YES;
    [self.iconImageView.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:15].active = YES;
    [self.iconImageView.widthAnchor constraintEqualToConstant:58].active = YES;
    [self.iconImageView.heightAnchor constraintEqualToConstant:58].active = YES;
    [self applyRoundedStyleToPreviewIconView];

    UIButton *iconButton = [UIButton buttonWithType:UIButtonTypeCustom];
    iconButton.translatesAutoresizingMaskIntoConstraints = NO;
    iconButton.backgroundColor = [UIColor clearColor];
    [iconButton addTarget:self action:@selector(didTapIconImageView:) forControlEvents:UIControlEventTouchUpInside];
    [containerView addSubview:iconButton];
    [iconButton.leadingAnchor constraintEqualToAnchor:self.iconImageView.leadingAnchor].active = YES;
    [iconButton.topAnchor constraintEqualToAnchor:self.iconImageView.topAnchor].active = YES;
    [iconButton.widthAnchor constraintEqualToAnchor:self.iconImageView.widthAnchor].active = YES;
    [iconButton.heightAnchor constraintEqualToAnchor:self.iconImageView.heightAnchor].active = YES;
    
    self.nameLabel = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.nameLabel addTarget:self action:@selector(didTapNameButton:) forControlEvents:UIControlEventTouchUpInside];
    self.nameLabel.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.nameLabel.titleLabel.font = [UIFont systemFontOfSize:17];
    
    [self.nameLabel setTitle:@"-" forState:UIControlStateNormal];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:self.nameLabel];
    [self.nameLabel.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:15].active = YES;
    [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.iconImageView.trailingAnchor constant:11].active = YES;
    [self.nameLabel.heightAnchor constraintEqualToConstant:22].active = YES;
    [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.appStoreButton.leadingAnchor constant:-(22 + 11)].active = YES;
    
    UIImage *nameEditImage = nil;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightBold];
        nameEditImage = [[UIImage systemImageNamed:@"square.and.pencil" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else {
        nameEditImage = [[ADHelper imageNamed:@"EditIconButton"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    self.nameEditButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.nameEditButton setImage:nameEditImage forState:UIControlStateNormal];
    [self.nameEditButton addTarget:self action:@selector(didTapNameButton:) forControlEvents:UIControlEventTouchUpInside];
    [self.nameEditButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [containerView addSubview:self.nameEditButton];
    [self.nameEditButton setContentEdgeInsets:UIEdgeInsetsMake(4.75, 4.75, 4.75, 4.75)];
    [self.nameEditButton.heightAnchor constraintEqualToConstant:22].active = YES;
    [self.nameEditButton.widthAnchor constraintEqualToConstant:22].active = YES;
    [self.nameEditButton.centerYAnchor constraintEqualToAnchor:self.nameLabel.centerYAnchor].active = YES;
    [self.nameEditButton.leadingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor constant:2].active = YES;
    
    self.identifierLabel = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.identifierLabel addTarget:self action:@selector(didTapIdentifierButton:) forControlEvents:UIControlEventTouchUpInside];
    self.identifierLabel.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.identifierLabel setTitle:@"-" forState:UIControlStateNormal];
    self.identifierLabel.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.identifierLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:self.identifierLabel];
    [self.identifierLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:2].active = YES;
    [self.identifierLabel.leadingAnchor constraintEqualToAnchor:self.iconImageView.trailingAnchor constant:11].active = YES;
    [self.identifierLabel.heightAnchor constraintEqualToConstant:20.16].active = YES;
    [self.identifierLabel.trailingAnchor constraintLessThanOrEqualToAnchor:containerView.trailingAnchor constant:-(22 + 11)].active = YES;

    UIImage *clipboardImage = nil;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithWeight:UIImageSymbolWeightBold];
        clipboardImage = [[UIImage systemImageNamed:@"doc.on.clipboard" withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    } else {
        clipboardImage = [[ADHelper imageNamed:@"ClipboardButton"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    self.identifierCopyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.identifierCopyButton setImage:clipboardImage forState:UIControlStateNormal];
    [self.identifierCopyButton addTarget:self action:@selector(didTapIdentifierButton:) forControlEvents:UIControlEventTouchUpInside];
    [self.identifierCopyButton setTranslatesAutoresizingMaskIntoConstraints:NO];
    [containerView addSubview:self.identifierCopyButton];
    [self.identifierCopyButton setContentEdgeInsets:UIEdgeInsetsMake(5, 5, 5, 5)];
    [self.identifierCopyButton.heightAnchor constraintEqualToConstant:22].active = YES;
    [self.identifierCopyButton.widthAnchor constraintEqualToConstant:22].active = YES;
    [self.identifierCopyButton.centerYAnchor constraintEqualToAnchor:self.identifierLabel.centerYAnchor].active = YES;
    [self.identifierCopyButton.leadingAnchor constraintEqualToAnchor:self.identifierLabel.trailingAnchor constant:1].active = YES;
    
    self.versionLabel = [[UILabel alloc] init];
    self.versionLabel.font = [UIFont systemFontOfSize:13];
    self.versionLabel.text = @"-";
    self.versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:self.versionLabel];
    [self.versionLabel.topAnchor constraintEqualToAnchor:self.identifierLabel.bottomAnchor].active = YES;
    [self.versionLabel.leadingAnchor constraintEqualToAnchor:self.iconImageView.trailingAnchor constant:11].active = YES;
    [self.versionLabel.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-11].active = YES;
    [self.versionLabel.heightAnchor constraintEqualToConstant:20.16].active = YES;
    
    // Create Table View
    self.tableView = [self createTableViewWithDataSource:self.mainDataSource];
    [self.tableView registerClass:ADTitleSectionHeaderView.class forHeaderFooterViewReuseIdentifier:ADTitleSectionHeaderView.reuseIdentifier];
    [containerView addSubview:self.tableView];
    
    self.moreTableView = [self createTableViewWithDataSource:self.moreDataSource];
    [self.moreTableView registerClass:ADExpandableSectionHeaderView.class forHeaderFooterViewReuseIdentifier:ADExpandableSectionHeaderView.reuseIdentifier];
    [self.moreTableView registerClass:ADTitleSectionHeaderView.class forHeaderFooterViewReuseIdentifier:ADTitleSectionHeaderView.reuseIdentifier];
    self.moreTableView.hidden = YES;
    [containerView addSubview:self.moreTableView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutTableViews];
    [self applyRoundedStyleToPreviewIconView];
    
    // Apply blur effect to contentView
    self.contentView.effect = [UIBlurEffect effectWithStyle:[ADAppearance.sharedInstance blurEffectStyle]];

    // Apply text colors
    UIColor *primaryLabelColor = [ADAppearance.sharedInstance primaryTextColor];
    UIColor *secondaryLabelsColor = [ADAppearance.sharedInstance secondaryTextColor];

    [self.nameLabel setTitleColor:primaryLabelColor forState:UIControlStateNormal];
    [self.identifierLabel setTitleColor:secondaryLabelsColor forState:UIControlStateNormal];
    self.versionLabel.textColor = secondaryLabelsColor;
    [self.identifierCopyButton setTintColor:secondaryLabelsColor];
    [self.nameEditButton setTintColor:secondaryLabelsColor];
    [self.appStoreButton setTintColor:secondaryLabelsColor];
    
    self.tableView.separatorColor = [ADAppearance.sharedInstance tableSeparatorColor];
    self.moreTableView.separatorColor = [ADAppearance.sharedInstance tableSeparatorColor];
}

- (void)traitCollectionDidChange:(UITraitCollection *)collection {
    [super traitCollectionDidChange:collection];
    [self.tableView reloadData];
    [self.moreTableView reloadData];
}

- (UITableView *)createTableViewWithDataSource:(id)dataSource {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    tableView.showsVerticalScrollIndicator = NO;
    tableView.backgroundColor = [UIColor clearColor];
    tableView.delegate = dataSource;
    tableView.dataSource = dataSource;
    return tableView;
}

- (void)layoutTableViews {
    CGFloat y = self.iconImageView.frame.origin.y + self.iconImageView.frame.size.height + 15;
    CGRect frame = CGRectMake(0, y, self.tableView.superview.frame.size.width, self.tableView.superview.frame.size.height - y);
    self.tableView.frame = frame;
    self.moreTableView.frame = frame;
}

#pragma mark - Actions

- (void)didTapNameButton:(UIButton *)button {
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self showCustomIconNameInterface];
}

- (void)didTapIdentifierButton:(UIButton *)button {
    if (!self.isCopyingIdentifier) {
        self.isCopyingIdentifier = YES;
        
        NSString *currentTitle = self.identifierLabel.titleLabel.text;
        [[UIPasteboard generalPasteboard] setString:currentTitle ?: @""];
        
        [self.identifierLabel setTitle:@"Copied to clipboard" forState:UIControlStateNormal];
        
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.7 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self.identifierLabel setTitle:currentTitle forState:UIControlStateNormal];
            self.isCopyingIdentifier = NO;
        });
    }
}

- (void)didTapAppStoreButton:(UIButton *)button {
    if (IS_IPAD) {
        [self dismissAppDataControllerAnimated:YES completion:^{
            [self.appData openInAppStore];
        }];
    } else {
        [self.appData openInAppStore];
    }
}

- (void)showCustomIconNameInterface {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"修改名称" message:@"输入新的应用图标名称" preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        if (self.dockDismissed && IS_IPAD) [self.class presentFloatingDockIfNeeded];
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"修改" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self.appData setCustomIconName:alertController.textFields.firstObject.text];
        [self.nameLabel setTitle:self.appData.name forState:UIControlStateNormal];
        if (self.dockDismissed && IS_IPAD) [self.class presentFloatingDockIfNeeded];
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self.appData setCustomIconName:nil];
        [self.nameLabel setTitle:self.appData.name forState:UIControlStateNormal];
        if (self.dockDismissed && IS_IPAD) [self.class presentFloatingDockIfNeeded];
    }]];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.clearButtonMode = UITextFieldViewModeAlways;
        textField.placeholder = @"应用名称";
        textField.text = self.nameLabel.titleLabel.text;
    }];
    if (IS_IPAD) {
        self.dockDismissed = [self.class dismissFloatingDockIfNeededWithCompletion:^{
            [self presentViewController:alertController animated:YES completion:nil];
        }];
        if (!self.dockDismissed) {
            [self presentViewController:alertController animated:YES completion:nil];
        }
    } else {
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

- (void)switchTableViews {
    UITableView *activeTableView = self.tableView.hidden ? self.moreTableView : self.tableView;
    UITableView *inactiveTableView = self.tableView.hidden ? self.tableView : self.moreTableView;
    
    BOOL isPresenting = [activeTableView isEqual:self.tableView];
    
    CGRect activeInitialFrame = activeTableView.frame;
    CGRect activeEndFrame = CGRectMake(0 - activeTableView.frame.size.width, activeTableView.frame.origin.y, activeTableView.frame.size.width, activeTableView.frame.size.height);
    
    CGRect inactiveInitialFrame = CGRectMake(activeTableView.frame.size.width, activeTableView.frame.origin.y, activeTableView.frame.size.width, activeTableView.frame.size.height);
    CGRect inactiveEndFrame = activeTableView.frame;
    
    if (isPresenting) {
        [self.view addGestureRecognizer:self.screenEdgeGesture];
    } else {
        [self.view removeGestureRecognizer:self.screenEdgeGesture];
        CGRect tmp = activeEndFrame;
        activeEndFrame = inactiveInitialFrame;
        inactiveInitialFrame = tmp;
    }
    
    activeTableView.frame = activeInitialFrame;
    inactiveTableView.frame = inactiveInitialFrame;

    activeTableView.hidden = NO;
    inactiveTableView.hidden = NO;
    
    activeTableView.alpha = 1.0;
    inactiveTableView.alpha = 0.0;
    
    [UIView animateWithDuration:0.25 animations:^{
        activeTableView.frame = activeEndFrame;
        inactiveTableView.frame = inactiveEndFrame;
        
        activeTableView.alpha = 0.0;
        inactiveTableView.alpha = 1.0;
    } completion:^(BOOL finished) {
        activeTableView.hidden = YES;
    }];
}

#pragma mark - Dock Controller

+ (SBFloatingDockController *)floatingDockController {
    if (NSClassFromString(@"SBIconController") && [NSClassFromString(@"SBIconController") respondsToSelector:@selector(sharedInstance)]) {
        SBIconController *iconController = [NSClassFromString(@"SBIconController") sharedInstance];
        if ([iconController respondsToSelector:@selector(floatingDockController)]) {
            return [iconController floatingDockController];
        }
    }
    return nil;
}

+ (BOOL)dismissFloatingDockIfNeededWithCompletion:(void(^)(void))completion {
    SBFloatingDockController *dockController = [self floatingDockController];
    if ([dockController respondsToSelector:@selector(_dismissFloatingDockIfPresentedAnimated:completionHandler:)] &&
        [dockController respondsToSelector:@selector(isFloatingDockPresented)]) {
        if ([dockController isFloatingDockPresented]) {
            [dockController _dismissFloatingDockIfPresentedAnimated:YES completionHandler:completion];
            return YES;
        }
    }
    return NO;
}

+ (void)presentFloatingDockIfNeeded {
    SBFloatingDockController *dockController = [self floatingDockController];
    if ([dockController respondsToSelector:@selector(_dismissFloatingDockIfPresentedAnimated:completionHandler:)] &&
        [dockController respondsToSelector:@selector(isFloatingDockPresented)]) {
        if (![dockController isFloatingDockPresented]) {
            [dockController _presentFloatingDockIfDismissedAnimated:YES completionHandler:^{}];
        }
    }
}

#pragma mark - Alert Helpers

+ (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    [self showAlertFromViewController:nil title:title message:message cancelTitle:@"Okay"];
}

+ (void)showAlertFromViewController:(UIViewController *)viewController title:(NSString *)title message:(NSString *)message cancelTitle:(NSString *)cancelTitle {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:nil]];
    [viewController ?: [UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alertController animated:YES completion:nil];
}

#pragma mark - Custom Icon Replacement

- (void)didTapIconImageView:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"修改图标"
                                                                   message:@"选择要执行的操作"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"从相册选择"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self performSelector:@selector(presentImagePickerForCustomIcon) withObject:nil afterDelay:0.05];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认图标"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self resetCustomIcon];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    BOOL dismissed = [self.class dismissFloatingDockIfNeededWithCompletion:^{
        [self presentViewController:alert animated:YES completion:nil];
    }];
    self.dockDismissed = dismissed;

    if (!dismissed) {
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)presentImagePickerForCustomIcon {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.allowsEditing = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    UIImage *image = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    if (image) {
        [self saveCustomIcon:image];
    }
    
    if (self.dockDismissed && IS_IPAD) {
        [self.class presentFloatingDockIfNeeded];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    if (self.dockDismissed && IS_IPAD) {
        [self.class presentFloatingDockIfNeeded];
    }
}

- (void)saveCustomIcon:(UIImage *)image {
    NSString *bundleID = self.appData.bundleIdentifier;
    if (!bundleID) return;

    NSString *dirPath = @"/var/mobile/Library/Preferences/AppDataIcons";
    if (![[NSFileManager defaultManager] fileExistsAtPath:dirPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dirPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }

    UIImage *finalImage = ADRoundedSquareIconImage(image);
    if (!finalImage) {
        finalImage = image;
    }
    
    NSString *path = [dirPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", bundleID]];
    [UIImagePNGRepresentation(finalImage) writeToFile:path atomically:YES];

    [self refreshSBIcon];
}

- (void)resetCustomIcon {
    NSString *bundleID = self.appData.bundleIdentifier;
    if (!bundleID) return;

    NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/AppDataIcons/%@.png", bundleID];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }

    [self refreshSBIcon];
    [self dismiss];
}

- (void)refreshSBIcon {
    NSString *bundleID = self.appData.bundleIdentifier;
    NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/AppDataIcons/%@.png", bundleID];
    
    // 1. 刷新当前 AppData 面板显示的图标
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        self.iconImageView.image = [UIImage imageWithContentsOfFile:path];
    } else {
        self.iconImageView.image = self.appData.iconImage;
    }

    [self applyRoundedStyleToPreviewIconView];

    // 2. 优先刷新当前桌面 icon image view
    if (self.appData.iconView) {
        SBIconImageView *iconImageView = ADGetIconImageViewFromIconView(self.appData.iconView);
        if (iconImageView && [iconImageView respondsToSelector:@selector(appDataPreferencesChanged)]) {
            [iconImageView performSelector:@selector(appDataPreferencesChanged)];
        }
    }

    // 3. 兜底通知 SpringBoard icon model
    if (self.appData.iconView && [self.appData.iconView respondsToSelector:@selector(icon)]) {
        id sbIcon = [self.appData.iconView performSelector:@selector(icon)];
        if ([sbIcon respondsToSelector:@selector(iconImageDidUpdate:)]) {
            [sbIcon performSelector:@selector(iconImageDidUpdate:) withObject:nil];
        }
    }
}

@end
