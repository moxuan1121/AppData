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

static inline UIImage *ADLoadCustomIconForBundleID(NSString *bundleID) {
    NSString *path = ADCustomIconPathForBundleID(bundleID);
    if (!path) return nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [UIImage imageWithContentsOfFile:path];
}

static inline NSString *ADBundleIDFromIcon(id icon) {
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

static inline id ADIconFromIconImageView(SBIconImageView *iconImageView) {
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

    if (!icon) {
        UIView *superview = iconImageView.superview;
        if ([superview respondsToSelector:@selector(icon)]) {
            icon = [superview performSelector:@selector(icon)];
        }
    }

    return icon;
}

static inline NSString *ADBundleIDFromIconImageView(SBIconImageView *iconImageView) {
    return ADBundleIDFromIcon(ADIconFromIconImageView(iconImageView));
}

static inline UIImage *ADRenderCustomIconForImageView(SBIconImageView *iconImageView) {
    NSString *bundleID = ADBundleIDFromIconImageView(iconImageView);
    UIImage *customImage = ADLoadCustomIconForBundleID(bundleID);
    if (!customImage) return nil;

    CGSize size = iconImageView.bounds.size;
    if (size.width <= 0.0 || size.height <= 0.0) {
        size = CGSizeMake(60.0, 60.0);
    }

    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat cornerRadius = round(MIN(size.width, size.height) * 0.2237f);

    UIGraphicsBeginImageContextWithOptions(size, NO, scale);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height)
                                                    cornerRadius:cornerRadius];
    [path addClip];
    [customImage drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *finalIcon = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return finalIcon ?: customImage;
}

static inline void ADSafeRefreshIconImageView(SBIconImageView *iconImageView) {
    if (!iconImageView) return;

    if ([iconImageView respondsToSelector:@selector(clearCachedImages)]) {
        [iconImageView performSelector:@selector(clearCachedImages)];
    }
    if ([iconImageView respondsToSelector:@selector(clearIconImageInfo)]) {
        [iconImageView performSelector:@selector(clearIconImageInfo)];
    }
    if ([iconImageView respondsToSelector:@selector(iconImageDidUpdate:)]) {
        [iconImageView performSelector:@selector(iconImageDidUpdate:) withObject:nil];
    }

    [iconImageView setNeedsDisplay];
    [iconImageView setNeedsLayout];
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
        
        self.adSwipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:r action:@selector(appDataDidSwipeUp:)];
        self.adSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
        self.adSwipeGestureRecognizer.delegate = (id<UIGestureRecognizerDelegate>)r;
        
        r.userInteractionEnabled = YES;
        [self appDataPreferencesChanged];
    }
    return r;
}

// 新增：显示层直接取图时也优先返回自定义图
- (UIImage *)contentsImage {
    UIImage *customImage = ADRenderCustomIconForImageView(self);
    if (customImage) {
        return customImage;
    }
    return %orig;
}

// 新增：异步加载结束后再轻刷一次，减少进出应用时闪原图
- (void)didEndAsynchronousImageLoadForIcon:(id)icon {
    %orig;

    NSString *bundleID = ADBundleIDFromIcon(icon);
    if (!bundleID.length) {
        bundleID = ADBundleIDFromIconImageView(self);
    }

    if (bundleID.length && ADLoadCustomIconForBundleID(bundleID)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ADSafeRefreshIconImageView(self);
        });
    }
}

// 新增：cache 回写时再轻刷一次，减少退出应用瞬间回原图
- (void)iconImageCache:(id)cache didUpdateImageForIcon:(id)icon {
    %orig;

    NSString *bundleID = ADBundleIDFromIcon(icon);
    if (!bundleID.length) {
        bundleID = ADBundleIDFromIconImageView(self);
    }

    if (bundleID.length && ADLoadCustomIconForBundleID(bundleID)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ADSafeRefreshIconImageView(self);
        });
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

    // 立即刷新一次
    ADSafeRefreshIconImageView(self);

    // 再延迟补一刀，解决“要滑页面才生效”和“进退应用闪一下”
    __weak SBIconImageView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SBIconImageView *strongSelf = weakSelf;
        if (!strongSelf) return;
        ADSafeRefreshIconImageView(strongSelf);
    });
}

%new
- (void)appDataDidSwipeUp:(UIGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [ADDataViewController presentControllerFromSBIconImageView:self fromContextMenu:NO];
    }
}

// 智能判断是否允许手势共存
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

// 抢占优先级，让其他插件的上滑手势失效
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
