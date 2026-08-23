//
//  ADSettings.m
//  AppData
//
//  Created by Fouad Raheb on 3/29/21.
//

#import <Foundation/Foundation.h>
#import "ADAppearance.h"

// Keys
#define kSwipeUpEnabled                                     @"SwipeUpEnabled"
#define kForceTouchMenuEnabled                              @"ForceTouchMenuEnabled"
#define kAppearance                                         @"kAppearance"

#define kBlockedFromLaunchingSafariPrefix                   @"IsBlockedFromLaunchingSafari"
#define kBlockedFromLaunchingAppStorePrefix                 @"IsBlockedFromLaunchingAppStore"
#define kBlockedFromLaunchingOthersPrefix                   @"IsBlockedFromLaunchingOthers"
#define kBlockedFromBeingLaunchedPrefix                     @"IsBlockedFromBeingLaunched"
#define kCustomBlockedApplicationsPrefix                    @"CustomBlockedApplications"
#define kAutoClearCachesPrefix                              @"AutoClearCaches"

// Notification
#define kAppDataSwipeUpPreferencesChangedNotification       @"com.fouadraheb.appdata.swipeup-preferences-changed"
#define kAppDataAppearancePreferencesChangedNotification    @"com.fouadraheb.appdata.appearance-preferences-changed"

@interface ADSettings : NSObject

@property (nonatomic, strong) NSUserDefaults *userDefaults;

+ (instancetype)sharedInstance;

+ (id)objectForKey:(NSString *)key;
+ (BOOL)boolForKey:(NSString *)key;
+ (NSInteger)integerForKey:(NSString *)key;
+ (void)setObject:(id)object forKey:(NSString *)key;
+ (void)setInteger:(NSInteger)integer forKey:(NSString *)key;

#pragma mark - Activation
+ (BOOL)swipeUpEnabled;
+ (BOOL)forceTouchMenuEnabled;

#pragma mark - App Launch Control
+ (BOOL)isBlockedFromLaunchingOtherApplications:(NSString *)bundleIdentifier;
+ (void)setBlockedFromLaunchingOtherApplications:(BOOL)blocked bundleIdentifier:(NSString *)bundleIdentifier;
+ (BOOL)isBlockedFromBeingLaunched:(NSString *)bundleIdentifier;
+ (void)setBlockedFromBeingLaunched:(BOOL)blocked bundleIdentifier:(NSString *)bundleIdentifier;
+ (BOOL)shouldBlockSourceBundleIdentifier:(NSString *)sourceBundleIdentifier targetBundleIdentifier:(NSString *)targetBundleIdentifier;
+ (NSArray<NSString *> *)customBlockedApplicationsForBundleIdentifier:(NSString *)bundleIdentifier;
+ (void)setCustomBlockedApplications:(NSArray<NSString *> *)applications forBundleIdentifier:(NSString *)bundleIdentifier;

#pragma mark - Per-App Cache Automation
+ (BOOL)automaticallyClearsCachesForBundleIdentifier:(NSString *)bundleIdentifier;
+ (void)setAutomaticallyClearsCaches:(BOOL)enabled bundleIdentifier:(NSString *)bundleIdentifier;

#pragma mark - Appearance
+ (ADAppearanceStyle)appearanceStyle;
+ (NSArray <NSString *> *)appearanceValues;
+ (NSArray <NSString *> *)appearanceTitles;
+ (NSString *)titleForAppearanceStyle:(ADAppearanceStyle)style;

@end
