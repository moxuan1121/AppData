#import "Classes/Controller/ADDataViewController.h"
#import "Classes/Model/ADAppData.h"

// 声明遵循 UIGestureRecognizerDelegate 协议
@interface SBIconImageView (AppData) <UIGestureRecognizerDelegate>
@end

// 声明 iOS 15/16 渲染相关的结构体和接口
struct SBIconImageInfo {
    CGSize size;
    CGFloat scale;
    CGFloat continuousCornerRadius;
};

// 修复重复声明：只声明 SBLeafIcon 继承自 Headers.h 中的 SBIcon
@interface SBLeafIcon : SBIcon
@end

@interface SBMainWorkspace : NSObject
@end

@interface BSProcessHandle : NSObject
@property(nonatomic, copy, readonly) NSString *bundleIdentifier;
@property(nonatomic, copy, readonly) NSString *name;
@end

@interface SBApplicationSceneEntity : NSObject
@property(nonatomic, strong, readonly) SBApplication *application;
@property(nonatomic, copy, readonly) NSSet *actions;
@end

@interface SBLayoutElement : NSObject
@property(nonatomic, copy, readonly) NSString *uniqueIdentifier;
@end

@interface SBLayoutState : NSObject
- (SBLayoutElement *)elementWithRole:(long long)role;
@end

@interface SBWorkspaceApplicationSceneTransitionContext : NSObject
@property(nonatomic, strong, readonly) SBLayoutState *previousLayoutState;
@end

@interface SBWorkspaceTransitionRequest : NSObject
@property(nonatomic, copy, readonly) NSSet<SBApplicationSceneEntity *> *toApplicationSceneEntities;
@property(nonatomic, copy, readonly) NSSet<SBApplicationSceneEntity *> *fromApplicationSceneEntities;
@property(nonatomic, copy, readonly) NSString *eventLabel;
@property(nonatomic, strong, readonly) BSProcessHandle *originatingProcess;
@property(nonatomic, strong, readonly) SBWorkspaceApplicationSceneTransitionContext *applicationContext;
- (void)declineWithReason:(id)reason;
@end

static NSString *ADBundleIdentifierFromPreviousLayout(SBWorkspaceTransitionRequest *request) {
    SBLayoutElement *element = [request.applicationContext.previousLayoutState elementWithRole:1];
    NSString *identifier = element.uniqueIdentifier;
    if ([identifier hasPrefix:@"sceneID:"]) identifier = [identifier substringFromIndex:8];
    if ([identifier hasSuffix:@"-default"]) {
        identifier = [identifier substringToIndex:identifier.length - 8];
    } else if (identifier.length > 37) {
        identifier = [identifier substringToIndex:identifier.length - 37];
    }
    return identifier;
}

static SBIconView *ADApplicationIconViewForImageView(UIView *imageView) {
    UIView *candidate = imageView.superview;
    Class iconViewClass = NSClassFromString(@"SBIconView");
    Class folderIconClass = NSClassFromString(@"SBFolderIcon");
    Class widgetIconClass = NSClassFromString(@"SBWidgetIcon");

    for (NSUInteger depth = 0; candidate && depth < 12; depth++, candidate = candidate.superview) {
        if (iconViewClass && [candidate isKindOfClass:iconViewClass]
            && [candidate respondsToSelector:@selector(icon)]) {
            SBIcon *icon = [(SBIconView *)candidate icon];
            if (!icon || (folderIconClass && [icon isKindOfClass:folderIconClass])
                || (widgetIconClass && [icon isKindOfClass:widgetIconClass])) return nil;

            NSString *bundleIdentifier = nil;
            if ([icon respondsToSelector:@selector(applicationBundleIdentifier)]) {
                bundleIdentifier = [icon performSelector:@selector(applicationBundleIdentifier)];
            } else if ([icon respondsToSelector:@selector(applicationBundleID)]) {
                bundleIdentifier = [icon performSelector:@selector(applicationBundleID)];
            }
            return bundleIdentifier.length > 0 ? (SBIconView *)candidate : nil;
        }
    }
    return nil;
}

%group SHARED_HOOKS

#pragma mark - Swipe Up on Icon

%hook SBIconImageView

%property (nonatomic, retain) UISwipeGestureRecognizer *adSwipeGestureRecognizer;

- (SBIconImageView *)initWithFrame:(CGRect)arg1 {
    %log;
    SBIconImageView *r = %orig;
    if (![r isKindOfClass:NSClassFromString(@"SBFolderIconImageView")]
        && ![r isKindOfClass:NSClassFromString(@"SBIconImageCrossfadeView")]
        && [r respondsToSelector:@selector(setAdSwipeGestureRecognizer:)]) {
        [[NSNotificationCenter defaultCenter] addObserver:r selector:@selector(appDataPreferencesChanged) name:kAppDataSwipeUpPreferencesChangedNotification object:nil];
        
        // Create Gesture Recognizer
        self.adSwipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:r action:@selector(appDataDidSwipeUp:)];
        self.adSwipeGestureRecognizer.direction = (UISwipeGestureRecognizerDirectionUp);
        
        // 设置代理，允许手势共存与干预
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

    // 刷新图标缓存与显示
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
        SBIconView *iconView = ADApplicationIconViewForImageView(self);
        if (!iconView) return;
        [ADDataViewController presentControllerFromSBIconView:iconView fromContextMenu:NO];
    }
}

// 智能判断是否允许手势共存，解决多插件重叠触发
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

// 抢占优先级，强行让其他插件的上滑手势失效
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

// 1. 恢复了原本正确的重绘逻辑（带有 UIGraphicsBeginImageContextWithOptions），这保证了修改后图标能【立即生效】
- (UIImage *)generateIconImageWithInfo:(struct SBIconImageInfo)info {
    NSString *bundleID = nil;
    if ([self respondsToSelector:@selector(applicationBundleIdentifier)]) {
        bundleID = [self performSelector:@selector(applicationBundleIdentifier)];
    } else if ([self respondsToSelector:@selector(applicationBundleID)]) {
        bundleID = [self performSelector:@selector(applicationBundleID)];
    }
    
    if (bundleID) {
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

// 2. 终极修复：拦截 iOS 14+ 动画引擎请求的“无遮罩”纯净图标，这保证了打开/退出软件时【不再闪回原版图标】
- (UIImage *)unmaskedIconImageWithInfo:(struct SBIconImageInfo)info {
    NSString *bundleID = nil;
    if ([self respondsToSelector:@selector(applicationBundleIdentifier)]) {
        bundleID = [self performSelector:@selector(applicationBundleIdentifier)];
    } else if ([self respondsToSelector:@selector(applicationBundleID)]) {
        bundleID = [self performSelector:@selector(applicationBundleID)];
    }
    
    if (bundleID) {
        NSString *customIconPath = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/AppDataIcons/%@.png", bundleID];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:customIconPath]) {
            UIImage *customImage = [UIImage imageWithContentsOfFile:customIconPath];
            if (customImage) {
                // 无遮罩（unmasked）图像不需要切圆角，但是必须缩放到正确的 size 返回给动画引擎
                UIGraphicsBeginImageContextWithOptions(info.size, NO, info.scale);
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

%end // IOS13_AND_NEWER_HOOKS


%group IOS12_AND_OLDER_HOOKS

%hook SBUIAppIconForceTouchControllerDataProvider

- (id)applicationShortcutItems {
    if ([ADSettings forceTouchMenuEnabled]) {
        NSArray *originalItems = %orig;
        NSMutableArray *newItems = [NSMutableArray arrayWithArray:originalItems ?: @[]];
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


#pragma mark - Redirect / Cross-App Launch Control

%group APP_LAUNCH_CONTROL_HOOKS

%hook SBMainWorkspace

- (BOOL)_canExecuteTransitionRequest:(id)transitionRequest forExecution:(BOOL)forExecution {
    if (![transitionRequest isKindOfClass:%c(SBMainWorkspaceTransitionRequest)]) return %orig;

    SBWorkspaceTransitionRequest *request = (SBWorkspaceTransitionRequest *)transitionRequest;
    NSString *eventLabel = request.eventLabel;
    BOOL isFromBreadcrumb = [eventLabel containsString:@"ActivateFromBreadcrumb"];
    if (eventLabel.length > 0) {
        BOOL isRequesterLaunch = [eventLabel containsString:@"OpenApplication"]
            && [eventLabel containsString:@"ForRequester"];
        if (!isFromBreadcrumb && !isRequesterLaunch) return %orig;
    }

    NSString *sourceBundleIdentifier = nil;
    SBApplicationSceneEntity *sourceEntity = request.fromApplicationSceneEntities.anyObject;
    if (sourceEntity) {
        id sourceAction = sourceEntity.actions.anyObject;
        if (sourceAction && ![sourceAction isKindOfClass:%c(UIOpenURLAction)]) return %orig;
        sourceBundleIdentifier = sourceEntity.application.bundleIdentifier;
    } else {
        NSString *originatingProcessName = request.originatingProcess.name;
        if (isFromBreadcrumb || [originatingProcessName isEqualToString:@"lsd"]) {
            sourceBundleIdentifier = ADBundleIdentifierFromPreviousLayout(request);
        }
    }
    sourceBundleIdentifier = sourceBundleIdentifier ?: request.originatingProcess.bundleIdentifier;

    SBApplicationSceneEntity *targetEntity = request.toApplicationSceneEntities.anyObject;
    NSString *targetBundleIdentifier = targetEntity.application.bundleIdentifier;
    BOOL shouldBlock = [ADSettings shouldBlockSourceBundleIdentifier:sourceBundleIdentifier
                                              targetBundleIdentifier:targetBundleIdentifier];
    if (!shouldBlock) {
        if (forExecution && targetBundleIdentifier.length > 0
            && [ADSettings automaticallyClearsCachesForBundleIdentifier:targetBundleIdentifier]) {
            static NSMutableSet<NSString *> *clearingBundleIdentifiers = nil;
            static dispatch_once_t clearCacheToken;
            dispatch_once(&clearCacheToken, ^{
                clearingBundleIdentifiers = [NSMutableSet set];
            });
            if (![clearingBundleIdentifiers containsObject:targetBundleIdentifier]) {
                [clearingBundleIdentifiers addObject:targetBundleIdentifier];
                ADAppData *targetAppData = [ADAppData appDataForBundleIdentifier:targetBundleIdentifier iconImage:nil];
                [targetAppData clearAppCachesWithCompletion:^{
                    [clearingBundleIdentifiers removeObject:targetBundleIdentifier];
                    NSLog(@"[AppData Cache] Automatically cleared caches for %@", targetBundleIdentifier);
                }];
            }
        }
        return %orig;
    }

    NSLog(@"[AppData Redirect] Declined transition %@ -> %@ (%@)",
          sourceBundleIdentifier, targetBundleIdentifier, eventLabel);
    [request declineWithReason:@"AppData Redirect"];
    return NO;
}

%end

%end // APP_LAUNCH_CONTROL_HOOKS


%ctor {
    %init(SHARED_HOOKS);
    %init(APP_LAUNCH_CONTROL_HOOKS);
    if (@available(iOS 13, *)) {
        %init(IOS13_AND_NEWER_HOOKS);
    } else {
        %init(IOS12_AND_OLDER_HOOKS);
    }
}
