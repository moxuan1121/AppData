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

    // 新增：同时把图标缓存/显示也刷新掉
    if ([self respondsToSelector:@selector(clearCachedImages)]) {
        [self performSelector:@selector(clearCachedImages)];
    }
    if ([self respondsToSelector:@selector(clearIconImageInfo)]) {
        [self performSelector:@selector(clearIconImageInfo)];
    }
    if ([self respondsToSelector:@selector(iconImageDidUpdate:)]) {
        [self performSelector:@selector(iconImageDidUpdate:) withObject:nil];
    }
    if ([self respondsToSelector:@selector(updateImageAnimated:)]) {
        NSMethodSignature *sig = [self methodSignatureForSelector:@selector(updateImageAnimated:)];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            BOOL animated = NO;
            [inv setSelector:@selector(updateImageAnimated:)];
            [inv setTarget:self];
            [inv setArgument:&animated atIndex:2];
            [inv invoke];
        }
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


#pragma mark - Additional Icon Cache Hook (iOS 14-16)

%hook SBIcon

// iOS 14-16 生成图标核心方法，解决打开/关闭 App 瞬间图标闪回原版的问题
- (UIImage *)generateIconImageWithInfo:(struct SBIconImageInfo)info {
    NSString *bundleID = nil;
    if ([self respondsToSelector:@selector(applicationBundleIdentifier)]) {
        bundleID = [self performSelector:@selector(applicationBundleIdentifier)];
    } else if ([self respondsToSelector:@selector(applicationBundleID)]) {
        bundleID = [self performSelector:@selector(applicationBundleID)];
    }
    
    if (bundleID) {
        NSString *customPath = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/AppDataIcons/%@.png", bundleID];
        if ([[NSFileManager defaultManager] fileExistsAtPath:customPath]) {
            UIImage *customImage = [UIImage imageWithContentsOfFile:customPath];
            if (customImage) {
                return customImage;
            }
        }
    }
    return %orig;
}

// 补充拦截缓存图像
- (UIImage *)unmaskedIconImageWithInfo:(struct SBIconImageInfo)info {
    NSString *bundleID = nil;
    if ([self respondsToSelector:@selector(applicationBundleIdentifier)]) {
        bundleID = [self performSelector:@selector(applicationBundleIdentifier)];
    } else if ([self respondsToSelector:@selector(applicationBundleID)]) {
        bundleID = [self performSelector:@selector(applicationBundleID)];
    }
    
    if (bundleID) {
        NSString *customPath = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/AppDataIcons/%@.png", bundleID];
        if ([[NSFileManager defaultManager] fileExistsAtPath:customPath]) {
            UIImage *customImage = [UIImage imageWithContentsOfFile:customPath];
            if (customImage) {
                return customImage;
            }
        }
    }
    return %orig;
}

%end


%ctor {
    %init(SHARED_HOOKS);
    if (@available(iOS 13, *)) {
        %init(IOS13_AND_NEWER_HOOKS);
    } else {
        %init(IOS12_AND_OLDER_HOOKS);
    }
}
