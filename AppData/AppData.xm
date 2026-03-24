#import "Classes/Controller/ADDataViewController.h"

// 声明遵循 UIGestureRecognizerDelegate 协议
@interface SBIconImageView (AppData) <UIGestureRecognizerDelegate>
@end

// 声明 iOS 15/16 渲染相关的结构体和接口
struct SBIconImageInfo {
    CGSize size;
    CGFloat scale;
    CGFloat continuousCornerRadius;
};

@interface SBLeafIcon : NSObject
- (NSString *)applicationBundleID;
@end


%group SHARED_HOOKS

#pragma mark - Helpers

static inline NSString *ADCustomIconPathForBundleID(NSString *bundleID) {
    if (!bundleID || ![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) return nil;
    return [NSString stringWithFormat:@"/var/mobile/Library/Preferences/AppDataIcons/%@.png", bundleID];
}

static inline UIImage *ADLoadCustomIcon(NSString *bundleID) {
    NSString *path = ADCustomIconPathForBundleID(bundleID);
    if (!path) return nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [UIImage imageWithContentsOfFile:path];
}

static inline NSString *ADBundleIDFromIconImageView(id iconImageView) {
    if (!iconImageView) return nil;

    id icon = nil;

    if ([iconImageView respondsToSelector:@selector(icon)]) {
        icon = [iconImageView performSelector:@selector(icon)];
    }

    if (!icon && [iconImageView respondsToSelector:@selector(iconView)]) {
        id iconView = [iconImageView performSelector:@selector(iconView)];
        if (iconView && [iconView respondsToSelector:@selector(icon)]) {
            icon = [iconView performSelector:@selector(icon)];
        }
    }

    if (!icon) return nil;

    if ([icon respondsToSelector:@selector(applicationBundleIdentifier)]) {
        NSString *bundleID = [icon performSelector:@selector(applicationBundleIdentifier)];
        if (bundleID.length) return bundleID;
    }

    if ([icon respondsToSelector:@selector(applicationBundleID)]) {
        NSString *bundleID = [icon performSelector:@selector(applicationBundleID)];
        if (bundleID.length) return bundleID;
    }

    return nil;
}

static inline UIImage *ADRenderedCustomIconForImageView(id iconImageView) {
    NSString *bundleID = ADBundleIDFromIconImageView(iconImageView);
    UIImage *customImage = ADLoadCustomIcon(bundleID);
    if (!customImage) return nil;

    CGSize targetSize = CGSizeZero;
    CGFloat targetScale = [UIScreen mainScreen].scale;
    CGFloat targetCornerRadius = 0.0;

    if ([iconImageView respondsToSelector:@selector(iconImageInfo)]) {
        NSMethodSignature *sig = [iconImageView methodSignatureForSelector:@selector(iconImageInfo)];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setSelector:@selector(iconImageInfo)];
            [inv setTarget:iconImageView];
            [inv invoke];

            struct SBIconImageInfo info;
            [inv getReturnValue:&info];
            targetSize = info.size;
            targetScale = info.scale > 0.0 ? info.scale : targetScale;
            targetCornerRadius = info.continuousCornerRadius;
        }
    }

    if (CGSizeEqualToSize(targetSize, CGSizeZero)) {
        if ([iconImageView bounds].size.width > 0.0 && [iconImageView bounds].size.height > 0.0) {
            targetSize = [iconImageView bounds].size;
        } else {
            targetSize = CGSizeMake(60.0, 60.0);
        }
    }

    if (targetCornerRadius <= 0.0 && [iconImageView respondsToSelector:@selector(continuousCornerRadius)]) {
        NSMethodSignature *sig = [iconImageView methodSignatureForSelector:@selector(continuousCornerRadius)];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setSelector:@selector(continuousCornerRadius)];
            [inv setTarget:iconImageView];
            [inv invoke];
            [inv getReturnValue:&targetCornerRadius];
        }
    }

    if (targetCornerRadius <= 0.0) {
        targetCornerRadius = round(MIN(targetSize.width, targetSize.height) * 0.224f);
    }

    UIGraphicsBeginImageContextWithOptions(targetSize, NO, targetScale);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, targetSize.width, targetSize.height)
                                                    cornerRadius:targetCornerRadius];
    [path addClip];
    [customImage drawInRect:CGRectMake(0, 0, targetSize.width, targetSize.height)];
    UIImage *finalIcon = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return finalIcon ?: customImage;
}

static inline void ADSetShowsSquareCornersIfPossible(id iconImageView, BOOL showsSquareCorners) {
    SEL sel = @selector(setShowsSquareCorners:);
    if ([iconImageView respondsToSelector:sel]) {
        NSMethodSignature *sig = [iconImageView methodSignatureForSelector:sel];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setSelector:sel];
            [inv setTarget:iconImageView];
            [inv setArgument:&showsSquareCorners atIndex:2];
            [inv invoke];
        }
    }
}

static inline void ADHardRefreshIconImageView(id iconImageView) {
    if (!iconImageView) return;

    ADSetShowsSquareCornersIfPossible(iconImageView, NO);

    if ([iconImageView respondsToSelector:@selector(clearCachedImages)]) {
        [iconImageView performSelector:@selector(clearCachedImages)];
    }
    if ([iconImageView respondsToSelector:@selector(clearIconImageInfo)]) {
        [iconImageView performSelector:@selector(clearIconImageInfo)];
    }
    if ([iconImageView respondsToSelector:@selector(iconImageDidUpdate:)]) {
        [iconImageView performSelector:@selector(iconImageDidUpdate:) withObject:nil];
    }
    if ([iconImageView respondsToSelector:@selector(updateImageAnimated:)]) {
        NSMethodSignature *sig = [iconImageView methodSignatureForSelector:@selector(updateImageAnimated:)];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            BOOL animated = NO;
            [inv setSelector:@selector(updateImageAnimated:)];
            [inv setTarget:iconImageView];
            [inv setArgument:&animated atIndex:2];
            [inv invoke];
        }
    }

    [iconImageView setNeedsDisplay];
    [iconImageView setNeedsLayout];
    if ([iconImageView respondsToSelector:@selector(layoutIfNeeded)]) {
        [iconImageView layoutIfNeeded];
    }
}

#pragma mark - Swipe Up on Icon

%hook SBIconImageView

%property (nonatomic, retain) UISwipeGestureRecognizer *adSwipeGestureRecognizer;

- (SBIconImageView *)initWithFrame:(CGRect)arg1 {
    %log;
    SBIconImageView *r = %orig;
    if (![r isKindOfClass:NSClassFromString(@"SBFolderIconImageView")]
        && [r respondsToSelector:@selector(setAdSwipeGestureRecognizer:)]) {
        [[NSNotificationCenter defaultCenter] addObserver:r selector:@selector(appDataPreferencesChanged) name:kAppDataSwipeUpPreferencesChangedNotification object:nil];
        
        // Create Gesture Recognizer
        self.adSwipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:r action:@selector(appDataDidSwipeUp:)];
        self.adSwipeGestureRecognizer.direction = (UISwipeGestureRecognizerDirectionUp);
        
        // 【关键修复】：设置代理，允许手势共存与干预
        self.adSwipeGestureRecognizer.delegate = (id<UIGestureRecognizerDelegate>)r;
        
        r.userInteractionEnabled = YES;
        
        // Add gesture if enabled
        [self appDataPreferencesChanged];
    }
    return r;
}

// 新增：显示层直接取图时，也优先返回自定义图
- (UIImage *)contentsImage {
    UIImage *custom = ADRenderedCustomIconForImageView(self);
    if (custom) {
        ADSetShowsSquareCornersIfPossible(self, NO);
        return custom;
    }
    return %orig;
}

// 新增：系统重新给 imageView 绑定 icon 的瞬间，也强制失效旧缓存
- (void)setIcon:(id)icon location:(id)location animated:(BOOL)animated {
    %orig;
    if (ADBundleIDFromIconImageView(self)) {
        [self appDataPreferencesChanged];
    }
}

// 新增：异步图标加载结束时，系统可能把原图塞回来，这里再压一次自定义图
- (void)didEndAsynchronousImageLoadForIcon:(id)icon {
    %orig;
    if (ADBundleIDFromIconImageView(self)) {
        [self appDataPreferencesChanged];
    }
}

// 新增：icon cache 更新时，系统也可能回写原图，这里再次覆盖
- (void)iconImageCache:(id)cache didUpdateImageForIcon:(id)icon {
    %orig;
    if (ADBundleIDFromIconImageView(self)) {
        [self appDataPreferencesChanged];
    }
}

%new
- (void)appDataPreferencesChanged {
    if ([ADSettings swipeUpEnabled]) {
        if (![self.gestureRecognizers containsObject:self.adSwipeGestureRecognizer]) {
            [self addGestureRecognizer:self.adSwipeGestureRecognizer];
        }
    } else {
        if ([self.gestureRecognizers containsObject:self.adSwipeGestureRecognizer]) {
            [self removeGestureRecognizer:self.adSwipeGestureRecognizer];
        }
    }

    // 更彻底：同时处理缓存、角、异步回写、显示刷新
    ADHardRefreshIconImageView(self);
}

%new
- (void)appDataDidSwipeUp:(UIGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [ADDataViewController presentControllerFromSBIconImageView:self fromContextMenu:NO];
    }
}

// 【精细化修复1】：智能判断是否允许手势共存，解决多插件重叠触发
%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.adSwipeGestureRecognizer) {
        if ([otherGestureRecognizer isKindOfClass:[UISwipeGestureRecognizer class]] || 
            [otherGestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
            return NO;
        }
        return YES;
    }
    return NO;
}

// 【精细化修复2】：抢占优先级，强行让其他插件的上滑手势失效
%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.adSwipeGestureRecognizer) {
        if ([otherGestureRecognizer isKindOfClass:[UISwipeGestureRecognizer class]]) {
            UISwipeGestureRecognizer *otherSwipe = (UISwipeGestureRecognizer *)otherGestureRecognizer;
            if (otherSwipe.direction == UISwipeGestureRecognizerDirectionUp) {
                return YES;
            }
        }
    }
    return NO;
}

%end

#pragma mark - Custom App Icon Name

%hook SBApplication

- (NSString *)displayName {
    if ([self respondsToSelector:@selector(bundleIdentifier)]) {
        NSString *customAppName = [ADSettings customAppNameForBundleIdentifier:self.bundleIdentifier];
        return customAppName ? : %orig;
    }
    return %orig;
}

%end


#pragma mark - Custom Icon Replacement (SBLeafIcon)

%hook SBLeafIcon

- (UIImage *)generateIconImageWithInfo:(struct SBIconImageInfo)info {
    NSString *bundleID = [self applicationBundleID];
    if (bundleID && [bundleID isKindOfClass:[NSString class]]) {
        NSString *customIconPath = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/AppDataIcons/%@.png", bundleID];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:customIconPath]) {
            UIImage *customImage = [UIImage imageWithContentsOfFile:customIconPath];
            if (customImage) {
                UIGraphicsBeginImageContextWithOptions(info.size, NO, info.scale);
                UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, info.size.width, info.size.height) cornerRadius:info.continuousCornerRadius];
                [path addClip];
                [customImage drawInRect:CGRectMake(0, 0, info.size.width, info.size.height)];
                UIImage *finalIcon = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                
                return finalIcon;
            }
        }
    }
    
    return %orig;
}

%end

%end // 结束 SHARED_HOOKS


#pragma mark - ForceTouch Menu

%group IOS13_AND_NEWER_HOOKS

%hook SBIconView

- (void)setApplicationShortcutItems:(NSArray *)items {
    if ([ADSettings forceTouchMenuEnabled] && [self ad_isSupportedIcon]) {
        NSMutableArray *newItems = [NSMutableArray arrayWithArray:items?:@[]];
        SBSApplicationShortcutItem *shortcutItem = [ADHelper applicationShortcutItem];
        if (shortcutItem) {
            [newItems insertObject:shortcutItem atIndex:0];
        }
        %orig(newItems);
    } else {
        %orig;
    }
}

+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(SBIconView *)iconView {
    NSLog(@"[AppData]: iconView: %@",iconView);
    if ([item.type isEqualToString:kSBApplicationShortcutItemType]) {
        [ADDataViewController presentControllerFromSBIconView:iconView fromContextMenu:YES];
    } else {
        %orig;
    }
}

%new
- (BOOL)ad_isSupportedIcon {
    if ([self respondsToSelector:@selector(icon)]) {
        return ![self.icon isKindOfClass:%c(SBFolderIcon)]
            && ![self.icon isKindOfClass:%c(SBWidgetIcon)];
    }
    return YES;
}

%end

%hook SBSApplicationShortcutItem

- (BOOL)sbh_isSystemShortcut {
    if ([self respondsToSelector:@selector(type)]
        && [self.type respondsToSelector:@selector(isEqualToString:)]
        && [self.type isEqualToString:kSBApplicationShortcutItemType]) {
        return YES;
    }
    return %orig;
}

- (NSUInteger)sbh_shortcutSection {
    if ([self respondsToSelector:@selector(type)]
        && [self.type respondsToSelector:@selector(isEqualToString:)]
        && [self.type isEqualToString:kSBApplicationShortcutItemType]) {
        return 2;
    }
    return %orig;
}

%end

%end


%group IOS12_AND_OLDER_HOOKS

%hook SBUIAppIconForceTouchControllerDataProvider

- (id)applicationShortcutItems {
    if ([ADSettings forceTouchMenuEnabled]) {
        NSMutableArray *newItems = [NSMutableArray arrayWithArray:%orig?:@[]];
        SBSApplicationShortcutItem *shortcutItem = [ADHelper applicationShortcutItem];
        if (shortcutItem) {
            [newItems insertObject:shortcutItem atIndex:0];
        }
        return newItems;
    }
    return %orig;
}

%end

%hook SBUIAppIconForceTouchController

- (void)appIconForceTouchShortcutViewController:(id)arg1 activateApplicationShortcutItem:(SBSApplicationShortcutItem *)item {
    if ([item.type isEqualToString:kSBApplicationShortcutItemType]) {
        [self dismissAnimated:YES withCompletionHandler:nil];
        SBUIAppIconForceTouchControllerDataProvider* _dataProvider = [self valueForKey:@"_dataProvider"];
        SBIconView *iconView = (SBIconView *)_dataProvider.gestureRecognizer.view;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [ADDataViewController presentControllerFromSBIconView:iconView fromContextMenu:YES];
        });
    } else {
        %orig;
    }
}

%end

%end


%ctor {
    %init(SHARED_HOOKS);
    if (@available(iOS 13, *)) {
        %init(IOS13_AND_NEWER_HOOKS);
    } else {
        %init(IOS12_AND_OLDER_HOOKS);
    }
}
