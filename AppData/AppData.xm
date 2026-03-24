#import "Classes/Controller/ADDataViewController.h"

// 声明扩展与代理
@interface SBIconImageView (AppData) <UIGestureRecognizerDelegate>
@property (nonatomic, retain) UISwipeGestureRecognizer *adSwipeGestureRecognizer;
@property (nonatomic, readonly) SBIcon *icon;
- (void)appDataPreferencesChanged;
@end

// 声明 iOS 14-16 的底层图标缓存类，解决动画闪回的核心！
@interface SBHIconImageCache : NSObject
- (UIImage *)imageForIcon:(SBIcon *)icon;
- (UIImage *)unmaskedImageForIcon:(SBIcon *)icon;
@end

// 统一提取自定义图标的 Helper 方法
static UIImage *ADGetCustomIconImage(SBIcon *icon) {
    if (!icon) return nil;
    NSString *bundleID = nil;
    if ([icon respondsToSelector:@selector(applicationBundleIdentifier)]) {
        bundleID = [icon performSelector:@selector(applicationBundleIdentifier)];
    } else if ([icon respondsToSelector:@selector(applicationBundleID)]) {
        bundleID = [icon performSelector:@selector(applicationBundleID)];
    }
    
    if (bundleID && [bundleID isKindOfClass:[NSString class]]) {
        NSString *customPath = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/AppDataIcons/%@.png", bundleID];
        if ([[NSFileManager defaultManager] fileExistsAtPath:customPath]) {
            UIImage *customImage = [UIImage imageWithContentsOfFile:customPath];
            if (customImage) return customImage;
        }
    }
    return nil;
}

%group SHARED_HOOKS

#pragma mark - Swipe Up on Icon

%hook SBIconImageView

%property (nonatomic, retain) UISwipeGestureRecognizer *adSwipeGestureRecognizer;

- (SBIconImageView *)initWithFrame:(CGRect)arg1 {
    SBIconImageView *r = %orig;
    if (![r isKindOfClass:NSClassFromString(@"SBFolderIconImageView")]
        && [r respondsToSelector:@selector(setAdSwipeGestureRecognizer:)]) {
        [[NSNotificationCenter defaultCenter] addObserver:r selector:@selector(appDataPreferencesChanged) name:kAppDataSwipeUpPreferencesChangedNotification object:nil];
        
        self.adSwipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:r action:@selector(appDataDidSwipeUp:)];
        self.adSwipeGestureRecognizer.direction = (UISwipeGestureRecognizerDirectionUp);
        self.adSwipeGestureRecognizer.delegate = (id<UIGestureRecognizerDelegate>)r;
        
        r.userInteractionEnabled = YES;
        [self appDataPreferencesChanged];
    }
    return r;
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

    if ([self respondsToSelector:@selector(clearCachedImages)]) {
        [self performSelector:@selector(clearCachedImages)];
    }
    if ([self respondsToSelector:@selector(clearIconImageInfo)]) {
        [self performSelector:@selector(clearIconImageInfo)];
    }
    if ([self respondsToSelector:@selector(iconImageDidUpdate:)]) {
        [self performSelector:@selector(iconImageDidUpdate:) withObject:nil];
    }
    [self setNeedsDisplay];
    [self setNeedsLayout];
}

%new
- (void)appDataDidSwipeUp:(UIGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [ADDataViewController presentControllerFromSBIconImageView:self fromContextMenu:NO];
    }
}

// 解决手势冲突
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


// ==========================================
// 核心：替换桌面静止状态显示的图标
// ==========================================
- (UIImage *)contentsImage {
    UIImage *custom = ADGetCustomIconImage(self.icon);
    if (custom) return custom;
    return %orig;
}

- (UIImage *)displayedImage {
    UIImage *custom = ADGetCustomIconImage(self.icon);
    if (custom) return custom;
    return %orig;
}

- (UIImage *)image {
    UIImage *custom = ADGetCustomIconImage(self.icon);
    if (custom) return custom;
    return %orig;
}

%end // SBIconImageView


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


// ==========================================
// 终极修复：解决打开/关闭 App 动画闪回原版的问题
// ==========================================
%hook SBHIconImageCache

- (UIImage *)imageForIcon:(SBIcon *)icon {
    UIImage *custom = ADGetCustomIconImage(icon);
    if (custom) return custom;
    return %orig;
}

- (UIImage *)unmaskedImageForIcon:(SBIcon *)icon {
    UIImage *custom = ADGetCustomIconImage(icon);
    if (custom) return custom;
    return %orig;
}

%end // SBHIconImageCache

%end // SHARED_HOOKS


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

%end // IOS13_AND_NEWER_HOOKS


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

%end // IOS12_AND_OLDER_HOOKS


%ctor {
    %init(SHARED_HOOKS);
    if (@available(iOS 13, *)) {
        %init(IOS13_AND_NEWER_HOOKS);
    } else {
        %init(IOS12_AND_OLDER_HOOKS);
    }
}
