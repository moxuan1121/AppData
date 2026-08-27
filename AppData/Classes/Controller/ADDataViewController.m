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

@interface UIImage (ADApplicationIconFallback)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(NSInteger)format scale:(CGFloat)scale;
@end

@interface ADDataViewController () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) ADDataPresentationManager *presentationManager;

@property (nonatomic, strong) UIVisualEffectView *contentView;

@property (nonatomic, strong) ADAppData *appData;

@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UIButton *nameLabel;
@property (nonatomic, strong) UIButton *identifierLabel;
@property (nonatomic, strong) UIButton *identifierCopyButton;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UIButton *appStoreButton;

@property (nonatomic, strong) ADMainDataSource *mainDataSource;
@property (nonatomic, strong) ADMoreDataSource *moreDataSource;

@property (nonatomic, assign) BOOL isCopyingIdentifier;

@property (nonatomic, strong) UIScreenEdgePanGestureRecognizer *screenEdgeGesture;

@end

static NSString *ADBundleIdentifierForIcon(SBIcon *icon) {
    if (!icon) return nil;
    NSString *bundleIdentifier = nil;
    if ([icon respondsToSelector:@selector(applicationBundleIdentifier)]) bundleIdentifier = [icon performSelector:@selector(applicationBundleIdentifier)];
    if (bundleIdentifier.length == 0 && [icon respondsToSelector:@selector(applicationBundleID)]) bundleIdentifier = [icon performSelector:@selector(applicationBundleID)];
    if (bundleIdentifier.length == 0 && [icon respondsToSelector:@selector(application)]) {
        SBApplication *application = [icon application];
        if ([application respondsToSelector:@selector(bundleIdentifier)]) bundleIdentifier = [application bundleIdentifier];
    }
    return bundleIdentifier.length > 0 ? bundleIdentifier : nil;
}

static SBIconImageView *ADFindIconImageView(UIView *view, NSUInteger depth) {
    if (!view || depth > 5) return nil;
    Class imageViewClass = NSClassFromString(@"SBIconImageView");
    for (UIView *subview in view.subviews) {
        if (imageViewClass && [subview isKindOfClass:imageViewClass]) return (SBIconImageView *)subview;
        SBIconImageView *nested = ADFindIconImageView(subview, depth + 1);
        if (nested) return nested;
    }
    return nil;
}

@implementation ADDataViewController

static inline CGFloat ADIconContinuousCornerRadiusForSide(CGFloat side) {
    // 58pt 图标用 13 左右会比较接近系统那种“微圆”
    return round(side * 0.224f);
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
        config.screenPercentage = [ADSettings panelHeightPercentage];
        
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
        [self showAlertWithTitle:@"AppData" message:@"无法获取应用数据。\n\n错误：图标视图为空。"];
        return;
    }
    
    // Find Icon Image View (iOS 15/16+ 兼容)
    SBIconImageView *_iconImageView = nil;
    if ([iconView respondsToSelector:@selector(iconImageView)]) {
        _iconImageView = [iconView performSelector:@selector(iconImageView)];
    }
    if (!_iconImageView && [iconView respondsToSelector:@selector(_iconImageView)]) {
        _iconImageView = [iconView _iconImageView];
    }
    if (!_iconImageView) {
        Ivar imageViewIvar = class_getInstanceVariable(object_getClass(iconView), "_iconImageView");
        if (imageViewIvar) _iconImageView = object_getIvar(iconView, imageViewIvar);
    }
    
    if (!_iconImageView) _iconImageView = ADFindIconImageView(iconView, 0);
    [self presentControllerFromSBIconImageView:_iconImageView iconView:iconView fromContextMenu:contextMenu];
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
    if ([iconView respondsToSelector:@selector(icon)]) {
        SBIcon *icon = iconView.icon;
        NSString *bundleID = ADBundleIdentifierForIcon(icon);
        
        if (!bundleID) {
            return;
        }
        
        UIImage *iconImage = [iconImageView respondsToSelector:@selector(contentsImage)] ? iconImageView.contentsImage : nil;
        if (!iconImage && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
            iconImage = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2 scale:[UIScreen mainScreen].scale];
        }
        ADAppData *appData = [ADAppData appDataForBundleIdentifier:bundleID iconImage:iconImage];
        if (appData) {
            [[UISelectionFeedbackGenerator new] selectionChanged];
            ADDataViewController *dataViewController = [[ADDataViewController alloc] initWithAppData:appData];
            
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
        // SpringBoard creates temporary crossfade/folder-animation views that are
        // not application icons. Ignore them silently instead of showing UI.
        NSLog(@"[AppData] Ignored unsupported icon view: %@", [iconView class]);
        return;
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

- (void)dismissImmediately {
    [self dismissAppDataControllerAnimated:NO completion:nil];
}

- (void)dismissAppDataControllerAnimated:(BOOL)animated completion:(void(^)(void))completion {
    // 恢复逻辑已经转移到下方生命周期中，这里只需负责关闭 Controller
    [self dismissViewControllerAnimated:animated completion:completion];
}

// Restore Dock state only. The icon recognizer now owns its touch arbitration;
// never disable an arbitrary ancestor scroll view, especially a folder container.
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // isBeingDismissed 判断确保：只有在面板真正被关闭时才恢复。
    if (self.isBeingDismissed) {
        if (self.dockDismissed) {
            self.dockDismissed = NO;
            [self.class presentFloatingDockIfNeeded];
        }
        
    }
}

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
    self.iconImageView.image = self.appData.iconImage;

    [self applyRoundedStyleToPreviewIconView];
    
    self.appStoreButton.hidden = ![self.appData hasAppStoreApp];
    
    if ([self.appData isApplication]) {
        [self.nameLabel setTitle:self.appData.name forState:UIControlStateNormal];
        [self.identifierLabel setTitle:self.appData.bundleIdentifier forState:UIControlStateNormal];
        if (self.appData.diskUsage > 0 && self.appData.diskUsageString) {
            self.versionLabel.text = [self.appData.version stringByAppendingFormat:@"  —  %@", self.appData.diskUsageString];
        } else {
            self.versionLabel.text = self.appData.version;
        }
    } else {
        [self.nameLabel setTitle:@"不是应用程序" forState:UIControlStateNormal];
        [self.nameLabel setEnabled:NO];
        
        [self.identifierLabel setTitle:@"无包标识符" forState:UIControlStateNormal];
        [self.identifierLabel setEnabled:NO];
        
        [self.versionLabel setText:@"—"];
        
        self.identifierCopyButton.hidden = YES;
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

    self.nameLabel = [UIButton buttonWithType:UIButtonTypeSystem];
    self.nameLabel.userInteractionEnabled = NO;
    self.nameLabel.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.nameLabel.titleLabel.font = [UIFont systemFontOfSize:17];
    
    [self.nameLabel setTitle:@"-" forState:UIControlStateNormal];
    self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:self.nameLabel];
    [self.nameLabel.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:15].active = YES;
    [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.iconImageView.trailingAnchor constant:11].active = YES;
    [self.nameLabel.heightAnchor constraintEqualToConstant:22].active = YES;
    [self.nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.appStoreButton.leadingAnchor constant:-11].active = YES;
    
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
    
    // Keep the management actions pinned. Only the container/group list below
    // this table scrolls, so frequently used actions remain reachable.
    self.managementTableView = [self createTableViewWithDataSource:self.mainDataSource];
    self.managementTableView.scrollEnabled = NO;
    self.managementTableView.showsVerticalScrollIndicator = NO;
    [self.managementTableView registerClass:ADTitleSectionHeaderView.class forHeaderFooterViewReuseIdentifier:ADTitleSectionHeaderView.reuseIdentifier];
    [containerView addSubview:self.managementTableView];

    // Keep the 1.8.15 layout: management controls stay pinned while the
    // directory and App Groups list below can scroll independently.
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
    [self.appStoreButton setTintColor:secondaryLabelsColor];
    
    self.tableView.separatorColor = [ADAppearance.sharedInstance tableSeparatorColor];
    self.managementTableView.separatorColor = [ADAppearance.sharedInstance tableSeparatorColor];
    self.moreTableView.separatorColor = [ADAppearance.sharedInstance tableSeparatorColor];
}

- (void)traitCollectionDidChange:(UITraitCollection *)collection {
    [super traitCollectionDidChange:collection];
    [self.tableView reloadData];
    [self.managementTableView reloadData];
    [self.moreTableView reloadData];
}

- (UITableView *)createTableViewWithDataSource:(id)dataSource {
    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    tableView.showsVerticalScrollIndicator = NO;
    tableView.backgroundColor = [UIColor clearColor];
    if (@available(iOS 15.0, *)) {
        tableView.sectionHeaderTopPadding = 0;
    }
    tableView.delegate = dataSource;
    tableView.dataSource = dataSource;
    return tableView;
}

- (void)layoutTableViews {
    CGFloat pinnedY = self.iconImageView.frame.origin.y + self.iconImageView.frame.size.height + 15;
    CGFloat pinnedHeight = 170.0; // 25pt title + 100pt actions + 45pt More Info
    CGFloat width = self.tableView.superview.frame.size.width;
    CGFloat height = self.tableView.superview.frame.size.height;
    self.managementTableView.frame = CGRectMake(0, pinnedY, width, pinnedHeight);

    CGFloat scrollingY = CGRectGetMaxY(self.managementTableView.frame);
    CGRect frame = CGRectMake(0, scrollingY, width, MAX(0, height - scrollingY));
    self.tableView.frame = frame;
    self.moreTableView.frame = frame;
}

#pragma mark - Actions

- (void)didTapIdentifierButton:(UIButton *)button {
    if (!self.isCopyingIdentifier) {
        self.isCopyingIdentifier = YES;
        
        NSString *currentTitle = self.identifierLabel.titleLabel.text;
        [[UIPasteboard generalPasteboard] setString:currentTitle ?: @""];
        
        [self.identifierLabel setTitle:@"已复制到剪贴板" forState:UIControlStateNormal];
        
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
    [self showAlertFromViewController:nil title:title message:message cancelTitle:@"确定"];
}

+ (void)showAlertFromViewController:(UIViewController *)viewController title:(NSString *)title message:(NSString *)message cancelTitle:(NSString *)cancelTitle {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:cancelTitle style:UIAlertActionStyleCancel handler:nil]];
    [viewController ?: [UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alertController animated:YES completion:nil];
}

@end
