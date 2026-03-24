#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "Classes/Controller/ADDataViewController.h"
#import "Classes/Helpers/ADSettings.h"
#import "Classes/Helpers/ADHelper.h"

static NSString * const kADBrandName = @".Alist";
static NSString * const kADApplicationShortcutItemType = @"com.fouadraheb.appdata-shortcut";
static NSString * const kADCustomIconDirectory = @"/var/mobile/Library/Preferences/AppDataIcons";

@interface SBApplication : NSObject
@end

@interface SBIcon : NSObject
- (NSString *)applicationBundleID;
- (NSString *)applicationBundleIdentifier;
- (SBApplication *)application;
- (NSInteger)badgeValue;
- (void)iconImageDidUpdate:(id)arg1;
@end

@interface SBFolderIcon : SBIcon
@end

@interface SBIconView : UIView
@property (nonatomic, retain) SBIcon *icon;
@property (nonatomic, retain) SBFolderIcon *folderIcon;
- (id)_iconImageView;
- (id)iconImageView;
- (void)_updateLabel;
- (BOOL)ad_isSupportedIcon;
@end

@interface SBSApplicationShortcutIcon : NSObject
@end

@interface SBSApplicationShortcutCustomImageIcon : SBSApplicationShortcutIcon
- (id)initWithImagePNGData:(id)arg1;
@end

@interface SBSApplicationShortcutItem : NSObject
@property (nonatomic, copy) SBSApplicationShortcutIcon *icon;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *localizedTitle;
@end

@interface SBIconImageView : UIView
@property (nonatomic, strong) UISwipeGestureRecognizer *adSwipeGestureRecognizer;
@property (nonatomic, retain) id iconImageCache;
@property (nonatomic) SBIconView *iconView;
- (UIImage *)contentsImage;
- (id)icon;
- (void)clearCachedImages;
- (void)clearIconImageInfo;
- (void)iconImageDidUpdate:(id)arg1;
- (void)updateImageAnimated:(BOOL)arg1;
- (void)appDataPreferencesChanged;
@end

@interface SBFloatingDockViewController : UIViewController
@end

@interface SBFloatingDockController : NSObject
@property (nonatomic, readonly) SBFloatingDockViewController *floatingDockViewController;
- (BOOL)isFloatingDockPresented;
- (void)_presentFloatingDockIfDismissedAnimated:(BOOL)arg1 completionHandler:(id)arg2;
- (void)_dismissFloatingDockIfPresentedAnimated:(BOOL)arg1 completionHandler:(id)arg2;
@end

@interface SBIconController : NSObject
+ (instancetype)sharedInstance;
@property (nonatomic, readonly) SBFloatingDockController *floatingDockController;
- (id)firstIconViewForIcon:(id)icon;
@end

@interface SBUIAppIconForceTouchControllerDataProvider : NSObject
@property (nonatomic, readonly) NSString *applicationBundleIdentifier;
@property (nonatomic, readonly) UIGestureRecognizer *gestureRecognizer;
@end

@interface SBUIAppIconForceTouchController : NSObject
- (void)dismissAnimated:(BOOL)arg1 withCompletionHandler:(id)arg2;
@end

static inline NSString *ADBundleIdentifierForIcon(id icon) {
    if (!icon) return nil;

    if ([icon respondsToSelector:@selector(applicationBundleIdentifier)]) {
        NSString *bid = ((id (*)(id, SEL))objc_msgSend)(icon, @selector(applicationBundleIdentifier));
        if (bid.length) return bid;
    }

    if ([icon respondsToSelector:@selector(applicationBundleID)]) {
        NSString *bid = ((id (*)(id, SEL))objc_msgSend)(icon, @selector(applicationBundleID));
        if (bid.length) return bid;
    }

    return nil;
}

static inline NSString *ADCustomIconPathForBundleID(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    return [kADCustomIconDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", bundleID]];
}

static inline UIImage *ADCustomIconImageForBundleID(NSString *bundleID) {
    NSString *path = ADCustomIconPathForBundleID(bundleID);
    if (!path.length) return nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [UIImage imageWithContentsOfFile:path];
}

static inline id ADIconForIconImageView(id iconImageView) {
    if (!iconImageView) return nil;

    if ([iconImageView respondsToSelector:@selector(icon)]) {
        id icon = ((id (*)(id, SEL))objc_msgSend)(iconImageView, @selector(icon));
        if (icon) return icon;
    }

    if ([iconImageView respondsToSelector:@selector(iconView)]) {
        id iconView = ((id (*)(id, SEL))objc_msgSend)(iconImageView, @selector(iconView));
        if (iconView && [iconView respondsToSelector:@selector(icon)]) {
            return ((id (*)(id, SEL))objc_msgSend)(iconView, @selector(icon));
        }
    }

    return nil;
}

@interface ADAppDataActivator : NSObject
+ (UIImage *)imageNamed:(NSString *)name;
+ (SBSApplicationShortcutItem *)applicationShortcutItem;
@end

@implementation ADAppDataActivator

+ (UIImage *)imageNamed:(NSString *)name {
    return [ADHelper imageNamed:name];
}

+ (SBSApplicationShortcutItem *)applicationShortcutItem {
    SBSApplicationShortcutItem *shortcutItem = [[NSClassFromString(@"SBSApplicationShortcutItem") alloc] init];
    shortcutItem.localizedTitle = kADBrandName;
    shortcutItem.type = kADApplicationShortcutItemType;

    NSData *imageData = nil;
    if (@available(iOS 13.0, *)) {
        if ([UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark) {
            imageData = UIImagePNGRepresentation([[self imageNamed:@"AppDataIconWhite"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]);
        } else {
            imageData = UIImagePNGRepresentation([[self imageNamed:@"AppDataIcon"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]);
        }
    } else {
        imageData = UIImagePNGRepresentation([[self imageNamed:@"AppDataIcon12"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]);
    }

    if (imageData) {
        SBSApplicationShortcutCustomImageIcon *iconImage = [[NSClassFromString(@"SBSApplicationShortcutCustomImageIcon") alloc] initWithImagePNGData:imageData];
        [shortcutItem setIcon:iconImage];
    }

    return shortcutItem;
}

@end

%hook SBIconImageView

- (UIImage *)contentsImage {
    id icon = ADIconForIconImageView(self);
    NSString *bundleID = ADBundleIdentifierForIcon(icon);
    UIImage *customImage = ADCustomIconImageForBundleID(bundleID);
    if (customImage) {
        return customImage;
    }
    return %orig;
}

%new
- (void)appDataPreferencesChanged {
    @try {
        if ([self respondsToSelector:@selector(clearCachedImages)]) {
            ((void (*)(id, SEL))objc_msgSend)(self, @selector(clearCachedImages));
        }

        if ([self respondsToSelector:@selector(clearIconImageInfo)]) {
            ((void (*)(id, SEL))objc_msgSend)(self, @selector(clearIconImageInfo));
        }

        if ([self respondsToSelector:@selector(iconImageDidUpdate:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(iconImageDidUpdate:), nil);
        }

        if ([self respondsToSelector:@selector(updateImageAnimated:)]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(updateImageAnimated:), NO);
        }

        [self setNeedsLayout];
        [self setNeedsDisplay];
        [self layoutIfNeeded];
    } @catch (__unused NSException *exception) {
    }
}

%end

%hook SBIconView

- (BOOL)ad_isSupportedIcon {
    if (![self respondsToSelector:@selector(icon)]) {
        return NO;
    }

    id icon = ((id (*)(id, SEL))objc_msgSend)(self, @selector(icon));
    if (!icon) {
        return NO;
    }

    NSString *bundleID = ADBundleIdentifierForIcon(icon);
    return (bundleID.length > 0);
}

%end

%hook SBUIAppIconForceTouchControllerDataProvider

- (id)applicationShortcutItems {
    id original = %orig;
    NSMutableArray *items = original ? [original mutableCopy] : [NSMutableArray array];

    BOOL exists = NO;
    for (id item in items) {
        if ([item respondsToSelector:@selector(type)]) {
            NSString *type = ((id (*)(id, SEL))objc_msgSend)(item, @selector(type));
            if ([type isEqualToString:kADApplicationShortcutItemType]) {
                exists = YES;
                break;
            }
        }
    }

    if (!exists) {
        SBSApplicationShortcutItem *shortcutItem = [ADAppDataActivator applicationShortcutItem];
        if (shortcutItem) {
            [items addObject:shortcutItem];
        }
    }

    return items;
}

%end
