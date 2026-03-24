//
//  ADAppData.m
//  AppData
//
//  Created by Fouad Raheb on 6/28/20.
//

#import "ADAppData.h"
#import "NRFileManager.h"
#import "ADTCC.h"
#import "ADTerminator.h"
#import <dlfcn.h>
#import <Foundation/Foundation.h>


@interface ADAppData ()
@property (nonatomic, strong) SBApplication *sbApplication;

@property (nonatomic, strong) LSApplicationProxy *appProxy;
@end

@implementation ADAppData

#pragma mark - Helpers

+ (SBApplication *)sbApplicationForBundleIdentifier:(NSString *)bundleIdentifier {
    if ([[NSClassFromString(@"SBApplicationController") sharedInstance] respondsToSelector:@selector(applicationWithBundleIdentifier:)]) {
        return [[NSClassFromString(@"SBApplicationController") sharedInstance] applicationWithBundleIdentifier:bundleIdentifier];
    }
    return nil;
}

#pragma mark - Initializers

+ (ADAppData *)appDataForBundleIdentifier:(NSString *)bundleIdentifier iconImage:(UIImage *)iconImage {
    ADAppData *data = [[ADAppData alloc] initWithBundleIdentifier:bundleIdentifier];
    data.iconImage = iconImage;
    return data;
}

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier {
    if (self = [super init]) {
        self.sbApplication = [self.class sbApplicationForBundleIdentifier:bundleIdentifier];
        self.appProxy = [LSApplicationProxy applicationProxyForIdentifier:bundleIdentifier];
        [self loadData];
    }
    return self;
}

- (void)loadData {
    // Version
    self.version = @"N/A";
    if ([self.appProxy respondsToSelector:@selector(shortVersionString)]) {
        if (self.appProxy.shortVersionString) {
            self.version = self.appProxy.shortVersionString;
        } else if ([self.appProxy respondsToSelector:@selector(bundleVersion)]) {
            self.version = self.appProxy.bundleVersion;
        }
    }
    
    // Bundle ID
    if ([self.appProxy respondsToSelector:@selector(bundleIdentifier)] && self.appProxy.bundleIdentifier) {
        self.bundleIdentifier = self.appProxy.bundleIdentifier;
    } else {
        self.bundleIdentifier = @"N/A";
    }
    
    // Vendable
    if ([self.appProxy respondsToSelector:@selector(isAppStoreVendable)]) {
        self.appStoreVendable = self.appProxy.isAppStoreVendable;
    }
    
    // Deletable (真实可卸载状态判断，支持巨魔)
    if ([self.appProxy respondsToSelector:@selector(isDeletable)]) {
        self.isDeletable = self.appProxy.isDeletable;
    } else {
        self.isDeletable = YES; // 低版本系统兜底处理
    }
    
    // Bundle URL
    if ([self.appProxy respondsToSelector:@selector(bundleURL)]) {
        if (self.appProxy.bundleURL) {
            self.bundleURL = self.appProxy.bundleURL;
        } else if ([self.appProxy respondsToSelector:@selector(bundleContainerURL)]) {
            self.bundleURL = self.appProxy.bundleContainerURL;
        }
    }
    
    // Data URL
    if ([self.appProxy respondsToSelector:@selector(dataContainerURL)]) {
        self.dataContainerURL = self.appProxy.dataContainerURL;
    }
    
    if ([self.appProxy respondsToSelector:@selector(groupContainerURLs)]) {
        NSMutableArray *appGroups = [NSMutableArray new];
        NSArray *sortedKeys = [self.appProxy.groupContainerURLs.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        for (NSString *key in sortedKeys) {
            NSURL *url = [self.appProxy.groupContainerURLs objectForKey:key];
            ADAppDataGroup *group = [ADAppDataGroup groupWithIdentifier:key url:url];
            [appGroups addObject:group];
        }
        self.appGroups = appGroups;
    }
    
    // Disk Usage
    if ([self.appProxy respondsToSelector:@selector(staticDiskUsage)]) {
        self.diskUsage = [self.appProxy.staticDiskUsage integerValue];
        self.diskUsageString = [NSByteCountFormatter stringFromByteCount:[self.appProxy.staticDiskUsage longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
    }
    
    // Info for more page
    [self loadMoreInfo];
}

- (void)loadMoreInfo {
    // Other Info
    self.entitlements = self.appProxy.entitlements;
    self.entitlementsIdentifiers = self.entitlements.allKeys;
    ASYNC({
        NSURL *infoPlistURL = [self.bundleURL URLByAppendingPathComponent:@"Info.plist"];
        NSDictionary *infoDictionary = [NSDictionary dictionaryWithContentsOfURL:infoPlistURL];
        
        if (infoDictionary) {
            // URL Schemes
            NSArray *bundleURLTypes = [infoDictionary objectForKey:@"CFBundleURLTypes"];
            if ([bundleURLTypes isKindOfClass:[NSArray class]]) {
                if (bundleURLTypes.firstObject && [bundleURLTypes.firstObject isKindOfClass:[NSDictionary class]]) {
                    id urlSchemes = [bundleURLTypes.firstObject objectForKey:@"CFBundleURLSchemes"];
                    if ([urlSchemes isKindOfClass:[NSArray class]]) {
                        self.urlSchemes = urlSchemes;
                    }
                }
            }
            
            // Queries Schemes
            id queriesSchemes = [infoDictionary objectForKey:@"LSApplicationQueriesSchemes"];
            if ([queriesSchemes isKindOfClass:[NSArray class]]) {
                self.queriesSchemes = queriesSchemes;
            }
            
            // Activity Types
            id activityTypes = [infoDictionary objectForKey:@"NSUserActivityTypes"];
            if ([activityTypes isKindOfClass:[NSArray class]]) {
                self.activityTypes = activityTypes;
            }
            
            // Background Modes
            id backgroundModes = [infoDictionary objectForKey:@"UIBackgroundModes"];
            if ([backgroundModes isKindOfClass:[NSArray class]]) {
                self.backgroundModes = backgroundModes;
            }
            
            // Versions
            self.minimumOSVersion = [infoDictionary objectForKey:@"MinimumOSVersion"];
            self.internalVersion = [infoDictionary objectForKey:@"CFBundleVersion"];
            self.platformVersion = [infoDictionary objectForKey:@"DTPlatformVersion"];
        }
    });
}

- (NSString *)name {
    return [self.sbApplication respondsToSelector:@selector(displayName)] ? self.sbApplication.displayName : nil;
}

// === 新增：为兼容 TSDowngradeManager 桥接的属性 ===
- (NSString *)displayName {
    return [self name];
}

- (NSString *)bundlePath {
    return self.bundleURL.path;
}
// ===========================================

- (BOOL)isApplication {
    return self.sbApplication != nil;
}

#pragma mark - Icon Name

- (NSString *)customIconName {
    return [ADSettings customAppNameForBundleIdentifier:self.bundleIdentifier];
}

- (void)setCustomIconName:(NSString *)name {
    [ADSettings setCustomAppName:name forBundleIdentifier:self.bundleIdentifier];
    if (self.iconView && [self.iconView respondsToSelector:@selector(_updateLabel)]) {
        [self.iconView _updateLabel];
    }
}

#pragma mark - AppStore

- (BOOL)hasAppStoreApp {
    return [self.appProxy respondsToSelector:@selector(itemID)] && [self.appProxy.itemID integerValue] != 0;
}

- (void)openInAppStore {
    NSString *appStoreLink = [NSString stringWithFormat:@"itms-apps://apps.apple.com/app/id%@",self.appProxy.itemID];
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:appStoreLink] options:@{} completionHandler:nil];
}

#pragma mark - Caches

- (NSURL *)cacheDirectoryURL {
    return [self.dataContainerURL URLByAppendingPathComponent:@"/Library/Caches/"];
}

- (NSURL *)tmpDirectoryURL {
    return [self.dataContainerURL URLByAppendingPathComponent:@"/tmp/"];
}

- (NSArray *)cacheDirectoriesURLs {
    NSMutableArray *caches = [NSMutableArray new];
    
    NSURL *cacheDirectoryURL = [self cacheDirectoryURL];
    if (cacheDirectoryURL) [caches addObject:cacheDirectoryURL];
    
    NSURL *tmpDirectoryURL = [self tmpDirectoryURL];
    if (tmpDirectoryURL) [caches addObject:tmpDirectoryURL];
    
    return caches;
}

- (void)getCachesDirectorySizeWithCompletion:(void(^)(NSString *formattedSize))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        unsigned long long int totalSize = 0;
        NSArray <NSURL *> *cacheDirectoriesURLs = [self cacheDirectoriesURLs];
        for (NSURL *url in cacheDirectoriesURLs) {
            if (url && [[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
                unsigned long long int folderSize = 0;
                [[NSFileManager defaultManager] nr_getAllocatedSize:&folderSize ofDirectoryAtURL:url error:nil];
                totalSize += folderSize;
            }
        }
        NSString *formattedSize = [NSByteCountFormatter stringFromByteCount:totalSize countStyle:NSByteCountFormatterCountStyleFile];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(formattedSize);
        });
    });
}

- (void)clearAppCachesWithCompletion:(void(^)())completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSArray <NSURL *> *cacheDirectoriesURLs = [self cacheDirectoriesURLs];
        for (NSURL *url in cacheDirectoriesURLs) {
            [self.class deleteContentsOfDirectoryAtURL:url];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    });
}

+ (void)deleteContentsOfDirectoryAtURL:(NSURL *)url {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:url includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:nil];
    NSURL *child;
    while ((child = [enumerator nextObject])) {
        [fm removeItemAtURL:child error:NULL];
    }
}

#pragma mark - App Badges

- (NSInteger)appBadgeCount {
    if ([self.sbApplication respondsToSelector:@selector(badgeValue)]) {
        return [[self.sbApplication badgeValue] integerValue];
    } else if ([self.sbApplication respondsToSelector:@selector(badgeNumberOrString)]) {
        return [[self.sbApplication badgeNumberOrString] integerValue];
    }
    return 0;
}

- (void)setAppBadgeCount:(NSInteger)badgeCount {
    if ([self.sbApplication respondsToSelector:@selector(setBadgeValue:)]) {
        [self.sbApplication setBadgeValue:[NSNumber numberWithInteger:badgeCount]];
    } else {
        [self.sbApplication setBadgeNumberOrString:[NSNumber numberWithInteger:badgeCount]];
    }
}

#pragma mark - Permissions
// 还原：这里回退为了原版基于 CFBundleRef 的代码
- (NSArray <NSDictionary *> *)getPermissions {
    CFBundleRef bundle = CFBundleCreate(kCFAllocatorDefault, (CFURLRef)self.appProxy.bundleURL);
    if (bundle) {
        NSArray *information = TCCAccessCopyInformationForBundle(bundle);
        CFRelease(bundle);
        return information;
    }
    return nil;
}

- (void)resetAllAppPermissions {
    SBSApplicationTerminationAssertionRef assertion = SBSApplicationTerminationAssertionCreateWithError(NULL, self.bundleIdentifier, 1, NULL);
    
    [self _resetAllAppPermissions];
    
    if (assertion) {
        SBSApplicationTerminationAssertionInvalidate(assertion);
    }
}

- (void)_resetAllAppPermissions {
    CFBundleRef bundle = CFBundleCreate(kCFAllocatorDefault, (CFURLRef)self.appProxy.bundleURL);
    if (bundle) {
        TCCAccessResetForBundle(kTCCServiceAll, bundle);
        CFRelease(bundle);
    }
    
    // Reset location permission
    [CLLocationManager setAuthorizationStatusByType:kCLAuthorizationStatusNotDetermined forBundleIdentifier:self.bundleIdentifier];
}

#pragma mark - Reset App

- (NSURL *)appLibraryDirectoryURL {
    return [self.dataContainerURL URLByAppendingPathComponent:@"/Library/"];
}

- (NSURL *)appDocumentsDirectoryURL {
    return [self.dataContainerURL URLByAppendingPathComponent:@"/Documents/"];
}

- (NSArray *)appGroupDirectoryURLs {
    NSMutableArray *appGroupDirectoryURLs = [NSMutableArray new];
    for (ADAppDataGroup *group in self.appGroups){
        [appGroupDirectoryURLs addObject:group.url];
    }
    return appGroupDirectoryURLs;
}

- (NSArray *)appUsageDirectoriesURLs {
    NSMutableArray *appUsageDir = [NSMutableArray new];
    
    NSURL *appLibraryDirectoryURL = [self appLibraryDirectoryURL];
    if (appLibraryDirectoryURL) [appUsageDir addObject:appLibraryDirectoryURL];
    
    NSURL *tmpDirectoryURL = [self tmpDirectoryURL];
    if (tmpDirectoryURL) [appUsageDir addObject:tmpDirectoryURL];
    
    NSURL *appDocumentsDirectoryURL = [self appDocumentsDirectoryURL];
    if (appDocumentsDirectoryURL) [appUsageDir addObject:appDocumentsDirectoryURL];
    
    return appUsageDir;
}

- (void)getAppUsageDirectorySizeWithCompletion:(void(^)(NSString *formattedSize))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        unsigned long long int totalSize = 0;
        NSArray <NSURL *> *appUsageDirectoriesURLs = [self appUsageDirectoriesURLs];
        for (NSURL *url in appUsageDirectoriesURLs) {
            if (url && [[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
                unsigned long long int folderSize = 0;
                [[NSFileManager defaultManager] nr_getAllocatedSize:&folderSize ofDirectoryAtURL:url error:nil];
                totalSize += folderSize;
            }
        }
        NSString *formattedSize = [NSByteCountFormatter stringFromByteCount:totalSize countStyle:NSByteCountFormatterCountStyleFile];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(formattedSize);
        });
    });
}

- (void)resetDiskContentWithCompletion:(void(^)())completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SBSApplicationTerminationAssertionRef assertion = SBSApplicationTerminationAssertionCreateWithError(NULL, self.bundleIdentifier, 1, NULL);
        
        NSArray <NSURL *> *appUsage = [self appUsageDirectoriesURLs];
        for (NSURL *url in appUsage) {
            [self.class deleteContentsOfDirectoryAtURL:url];
        }
        
        // Recreate Preferences folder
        if ([self appLibraryDirectoryURL]) {
            [[NSFileManager defaultManager] createDirectoryAtURL:[[self appLibraryDirectoryURL] URLByAppendingPathComponent:@"Preferences" isDirectory:YES] withIntermediateDirectories:YES attributes:nil error:NULL];
        }
        
        // Reset all permissions (这里保留我们修改过的 isApplication 逻辑)
        if (self.isApplication) {
            [self _resetAllAppPermissions];
        }

        if (assertion) {
            SBSApplicationTerminationAssertionInvalidate(assertion);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    });
}

#pragma mark - Uninstall App
// 这里的卸载逻辑保留了我们改写的彻底卸载
- (void)uninstallAppWithCompletion:(void(^)(BOOL success))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL result = NO;
        id workspace = [NSClassFromString(@"LSApplicationWorkspace") performSelector:@selector(defaultWorkspace)];
        
        if ([workspace respondsToSelector:@selector(uninstallApplication:withOptions:error:)]) {
            NSError *error = nil;
            result = [workspace uninstallApplication:self.bundleIdentifier withOptions:nil error:&error];
            if (error) {
                NSLog(@"[AppData] Uninstall error: %@", error);
            }
        } else if ([workspace respondsToSelector:@selector(uninstallApplication:withOptions:)]) {
            result = [workspace uninstallApplication:self.bundleIdentifier withOptions:nil];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(result);
        });
    });
}

@end

#pragma mark - 原生降级组件实现

// 1. 账号匹配校验
- (BOOL)isAppOwnershipVerified {
    // 动态加载服务
    dlopen("/System/Library/PrivateFrameworks/StoreServices.framework/StoreServices", RTLD_LAZY);
    Class SSAccountStoreClass = NSClassFromString(@"SSAccountStore");
    if (!SSAccountStoreClass) return NO;
    
    id store = [SSAccountStoreClass performSelector:@selector(defaultStore)];
    NSArray *accounts = [store performSelector:@selector(accounts)];
    NSString *activeAccountEmail = nil;
    
    // 获取当前活动账号
    for (id account in accounts) {
        if ([[account performSelector:@selector(isActive)] boolValue] && ![[account performSelector:@selector(isLocalAccount)] boolValue]) {
            activeAccountEmail = [account performSelector:@selector(accountName)];
            break;
        }
    }
    if (!activeAccountEmail) return NO;
    
    // 获取购买账号
    NSString *bundlePath = self.bundleURL.path;
    NSString *containerPath = [bundlePath stringByDeletingLastPathComponent];
    NSString *metadataPath = [containerPath stringByAppendingPathComponent:@"iTunesMetadata.plist"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:metadataPath]) return NO;
    
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
    NSDictionary *downloadInfo = metadata[@"com.apple.iTunesStore.downloadInfo"];
    NSDictionary *accountInfo = downloadInfo[@"accountInfo"];
    NSString *purchaserAccountEmail = accountInfo[@"AppleID"];
    
    if (!purchaserAccountEmail) return NO;
    
    return ([activeAccountEmail caseInsensitiveCompare:purchaserAccountEmail] == NSOrderedSame);
}

// 2. 获取 TrackID
- (void)fetchDowngradeTrackIDWithCompletion:(void(^)(long long trackId, NSError *error))completion {
    NSString *countryCode = @"us"; // 默认美区兜底
    NSLocale *locale = [NSLocale currentLocale];
    NSString *code = [locale objectForKey:NSLocaleCountryCode];
    if (code) countryCode = [code lowercaseString];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://itunes.apple.com/lookup?bundleId=%@&limit=1&media=software&country=%@", self.bundleIdentifier, countryCode]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { completion(0, error); return; }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *results = json[@"results"];
            if ([results isKindOfClass:[NSArray class]] && results.count > 0) {
                long long trackId = [results.firstObject[@"trackId"] longLongValue];
                completion(trackId, nil);
            } else {
                completion(0, [NSError errorWithDomain:@"AppData" code:404 userInfo:@{NSLocalizedDescriptionKey: @"未能在 App Store 找到该应用，或不支持降级"}]);
            }
        });
    }] resume];
}

// 3. 获取版本列表
- (void)fetchDowngradeVersionsForTrackID:(long long)trackId completion:(void(^)(NSArray *versions, NSError *error))completion {
    NSString *serverURL = @"https://apis.bilin.eu.org/history/";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%lld", serverURL, trackId]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { completion(nil, error); return; }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *versions = json[@"data"];
            if ([versions isKindOfClass:[NSArray class]] && versions.count > 0) {
                completion(versions, nil);
            } else {
                completion(nil, [NSError errorWithDomain:@"AppData" code:404 userInfo:@{NSLocalizedDescriptionKey: @"未能获取到历史版本数据"}]);
            }
        });
    }] resume];
}

// 4. 执行私有 API 降级
- (void)performDowngradeWithTrackID:(long long)trackId versionID:(long long)versionId controller:(UIViewController *)controller {
    // 动态加载 StoreKitUI
    dlopen("/System/Library/PrivateFrameworks/StoreKitUI.framework/StoreKitUI", RTLD_LAZY);
    Class SKUIItemOfferClass = NSClassFromString(@"SKUIItemOffer");
    Class SKUIItemClass = NSClassFromString(@"SKUIItem");
    Class SKUIItemStateCenterClass = NSClassFromString(@"SKUIItemStateCenter");
    Class SKUIClientContextClass = NSClassFromString(@"SKUIClientContext");
    
    if (!SKUIItemOfferClass || !SKUIItemClass || !SKUIItemStateCenterClass) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"错误" message:@"无法加载系统的 App Store 下载组件" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
            [controller presentViewController:alert animated:YES completion:nil];
        });
        return;
    }
    
    NSString *adamId = [NSString stringWithFormat:@"%lld", trackId];
    NSString *appExtVrsId = [NSString stringWithFormat:@"%lld", versionId];
    NSString *offerString = [NSString stringWithFormat:@"productType=C&price=0&salableAdamId=%@&pricingParameters=pricingParameter&appExtVrsId=%@&clientBuyId=1&installed=0&trolled=1", adamId, appExtVrsId];
    
    // 初始化私有 API 对象
    id offer = [[SKUIItemOfferClass alloc] performSelector:NSSelectorFromString(@"initWithLookupDictionary:") withObject:@{@"buyParams": offerString}];
    id item = [[SKUIItemClass alloc] performSelector:NSSelectorFromString(@"initWithLookupDictionary:") withObject:@{@"_itemOffer": adamId}];
    
    [item setValue:offer forKey:@"_itemOffer"];
    [item setValue:@"iosSoftware" forKey:@"_itemKindString"];
    [item setValue:@(versionId) forKey:@"_versionIdentifier"];
    
    id center = [SKUIItemStateCenterClass performSelector:NSSelectorFromString(@"defaultCenter")];
    id context = [SKUIClientContextClass performSelector:NSSelectorFromString(@"defaultContext")];
    NSArray *items = @[item];
    id purchases = [center performSelector:NSSelectorFromString(@"_newPurchasesWithItems:") withObject:items];
    
    // 组装并触发购买方法 (安全避免崩溃)
    SEL sel = NSSelectorFromString(@"_performPurchases:hasBundlePurchase:withClientContext:completionBlock:");
    NSMethodSignature *sig = [center methodSignatureForSelector:sel];
    if (sig) {
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:sel];
        [inv setTarget:center];
        [inv setArgument:&purchases atIndex:2];
        BOOL hasBundle = NO;
        [inv setArgument:&hasBundle atIndex:3];
        [inv setArgument:&context atIndex:4];
        
        id block = ^(id arg1){ 
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"降级已触发" message:@"应用已经开始下载，请返回桌面或 App Store 查看下载进度。" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                [controller presentViewController:alert animated:YES completion:nil];
            });
        };
        id copiedBlock = [block copy];
        [inv setArgument:&copiedBlock atIndex:5];
        [inv invoke];
    }
}


@implementation ADAppDataGroup

+ (ADAppDataGroup *)groupWithIdentifier:(NSString *)identifier url:(NSURL *)url {
    ADAppDataGroup *group = [ADAppDataGroup new];
    group.identifier = identifier;
    group.url = url;
    return group;
}

@end
