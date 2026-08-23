//
//  ADHelper.m
//  AppData
//
//  Created by Fouad Raheb on 6/29/20.
//

#import "ADHelper.h"
#import <dlfcn.h>

#if __has_include(<rootless.h>)
#import <rootless.h>
#endif

@interface ADHelper ()
@property (nonatomic, strong) NSBundle *resoucesBundle;
@end

@implementation ADHelper

static NSString *ADCompatiblePath(NSString *rootRelativePath) {
#if __has_include(<rootless.h>)
    return JBROOT_PATH_NSSTRING(rootRelativePath);
#else
    NSString *rootfulPath = rootRelativePath;
    NSString *rootlessPath = [@"/var/jb" stringByAppendingString:rootRelativePath];

    Dl_info info = {0};
    if (dladdr((const void *)&ADCompatiblePath, &info) && info.dli_fname) {
        NSString *imagePath = [NSString stringWithUTF8String:info.dli_fname];

        NSArray<NSString *> *markers = @[
            @"/Library/MobileSubstrate/",
            @"/usr/lib/TweakInject/",
            @"/Library/PreferenceBundles/",
            @"/Library/Application Support/"
        ];

        for (NSString *marker in markers) {
            NSRange range = [imagePath rangeOfString:marker];
            if (range.location != NSNotFound) {
                NSString *jbRoot = [imagePath substringToIndex:range.location];
                if (jbRoot.length > 0) {
                    return [jbRoot stringByAppendingString:rootRelativePath];
                }
                break;
            }
        }
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:rootlessPath]) {
        return rootlessPath;
    }

    return rootfulPath;
#endif
}

+ (instancetype)sharedInstance {
    static dispatch_once_t p = 0;
    __strong static ADHelper *_sharedInstance = nil;
    dispatch_once(&p, ^{
        _sharedInstance = [[self alloc] init];
        // Create resources bundle
        _sharedInstance.resoucesBundle = [NSBundle bundleWithPath:ADCompatiblePath(@"/Library/Application Support/AppData/Resources.bundle")];
    });
    return _sharedInstance;
}

#pragma mark - Resources

+ (UIImage *)imageNamed:(NSString *)imageName {
    return [UIImage imageNamed:imageName inBundle:ADHelper.sharedInstance.resoucesBundle];
}

#pragma mark - Helpers

+ (void)openDirectoryAtURL:(NSURL *)url fromController:(UIViewController *)controller {
    NSString *path = [url.path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"filza://"]]) {
        NSURL *filzaURL = [NSURL URLWithString:[@"filza://view" stringByAppendingString:path]];
        [[UIApplication sharedApplication] openURL:filzaURL options:@{} completionHandler:nil];
    } else if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"ifile://"]]) {
        NSURL *ifileURL = [NSURL URLWithString:[@"ifile://file://" stringByAppendingString:path]];
        [[UIApplication sharedApplication] openURL:ifileURL options:@{} completionHandler:nil];
    } else {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AppData" message:@"请安装 Filza 后再打开所选目录。" preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [controller presentViewController:alertController animated:YES completion:nil];
    }
}

+ (SBSApplicationShortcutItem *)applicationShortcutItem {
    SBSApplicationShortcutItem *shortcutItem = [[NSClassFromString(@"SBSApplicationShortcutItem") alloc] init];
    shortcutItem.localizedTitle = @"AppData";
    shortcutItem.type = kSBApplicationShortcutItemType;
    
    NSData *imageData = nil;
    if (@available(iOS 13, *)) {
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
