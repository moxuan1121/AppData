//
//  ADAppData.h
//  AppData
//
//  Created by Fouad Raheb on 6/28/20.
//

#import <Foundation/Foundation.h>

@interface ADAppDataGroup : NSObject
@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, strong) NSURL *url;
+ (ADAppDataGroup *)groupWithIdentifier:(NSString *)identifier url:(NSURL *)url;
@end

@interface ADAppData : NSObject

@property (nonatomic, strong) SBIconView *iconView;
@property (nonatomic, strong) UIImage *iconImage;

- (NSString *)name;
@property (nonatomic, strong) NSString *version;
@property (nonatomic, strong) NSString *bundleIdentifier;

@property (nonatomic, assign) BOOL appStoreVendable;
@property (nonatomic, assign) BOOL isDeletable;
@property (nonatomic, strong) NSURL *bundleURL;
@property (nonatomic, strong) NSURL *dataContainerURL;
@property (nonatomic, strong) NSArray <ADAppDataGroup *> *appGroups;
@property (nonatomic, assign) NSInteger diskUsage;
@property (nonatomic, strong) NSString *diskUsageString;

// More Info
@property (nonatomic, strong) NSDictionary *entitlements;
@property (nonatomic, strong) NSArray <NSString *> *entitlementsIdentifiers;
@property (nonatomic, strong) NSString *minimumOSVersion;
@property (nonatomic, strong) NSString *internalVersion;
@property (nonatomic, strong) NSString *platformVersion;
@property (nonatomic, strong) NSArray <NSString *> *urlSchemes;
@property (nonatomic, strong) NSArray <NSString *> *queriesSchemes;
@property (nonatomic, strong) NSArray <NSString *> *activityTypes;
@property (nonatomic, strong) NSArray <NSString *> *backgroundModes;

+ (ADAppData *)appDataForBundleIdentifier:(NSString *)bundleIdentifier iconImage:(UIImage *)iconImage;
- (BOOL)isApplication;

#pragma mark - Icon Name
- (NSString *)customIconName;
- (void)setCustomIconName:(NSString *)name;

#pragma mark - AppStore
- (BOOL)hasAppStoreApp;
- (void)openInAppStore;

#pragma mark - Permissions
- (NSArray <NSDictionary *> *)getPermissions;
- (void)resetAllAppPermissions;

#pragma mark - Reset App
- (void)getAppUsageDirectorySizeWithCompletion:(void(^)(NSString *formattedSize))completion;
- (void)resetDiskContentWithCompletion:(void(^)())completion;

#pragma mark - Caches
- (void)getCachesDirectorySizeWithCompletion:(void(^)(NSString *formattedSize))completion;
- (void)clearAppCachesWithCompletion:(void(^)())completion;

#pragma mark - App Badges
- (void)setAppBadgeCount:(NSInteger)badgeCount;
- (NSInteger)appBadgeCount;

#pragma mark - Uninstall App
- (void)uninstallAppWithCompletion:(void(^)(BOOL success))completion;

#pragma mark - Downgrade & Verification (原生降级组件)
// 校验当前账号与下载账号是否匹配
- (BOOL)isAppOwnershipVerified;
// 获取应用 TrackID
- (void)fetchDowngradeTrackIDWithCompletion:(void(^)(long long trackId, NSError *error))completion;
// 获取应用历史版本
- (void)fetchDowngradeVersionsForTrackID:(long long)trackId completion:(void(^)(NSArray *versions, NSError *error))completion;
// 触发 App Store 降级下载
- (void)performDowngradeWithTrackID:(long long)trackId versionID:(long long)versionId controller:(UIViewController *)controller;

@end
