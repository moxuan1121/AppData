//
//  ADSettings.m
//  AppData
//
//  Created by Fouad Raheb on 3/29/21.
//

#import "ADSettings.h"

@implementation ADSettings

+ (instancetype)sharedInstance {
    static dispatch_once_t p = 0;
    __strong static ADSettings *_sharedInstance = nil;
    dispatch_once(&p, ^{
        _sharedInstance = [[self alloc] init];
        [_sharedInstance initialize];
    });
    return _sharedInstance;
}

- (void)initialize {
    // Load tweak preferences
    self.userDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.fouadraheb.appdata"];
    [self.userDefaults registerDefaults:self.class.defaultsDictionary];
    [self.userDefaults addObserver:self forKeyPath:kSwipeUpEnabled options:NSKeyValueObservingOptionNew context:NULL];
    [self.userDefaults addObserver:self forKeyPath:kAppearance options:NSKeyValueObservingOptionNew context:NULL];
}

- (void)observeValueForKeyPath:(NSString *) keyPath ofObject:(id) object change:(NSDictionary *) change context:(void *) context {
    if ([keyPath isEqualToString:kSwipeUpEnabled]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kAppDataSwipeUpPreferencesChangedNotification object:nil];
    } else if ([keyPath isEqualToString:kAppearance]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kAppDataAppearancePreferencesChangedNotification object:nil];
    }
}

+ (NSDictionary *)defaultsDictionary {
    return @{
        kSwipeUpEnabled:            @(YES),
        kForceTouchMenuEnabled:     @(NO),
        kAppearance:                @(ADAppearanceStyleDark),
        kPanelHeightPercentage:     @(50)
    };
}

+ (id)objectForKey:(NSString *)key {
    return [[self.sharedInstance userDefaults] objectForKey:key];
}

+ (BOOL)boolForKey:(NSString *)key {
    return [[self.sharedInstance userDefaults] boolForKey:key];
}

+ (NSInteger)integerForKey:(NSString *)key {
    return [[self.sharedInstance userDefaults] integerForKey:key];
}

+ (void)setObject:(id)object forKey:(NSString *)key {
    return [[self.sharedInstance userDefaults] setObject:object forKey:key];
}

+ (void)setInteger:(NSInteger)integer forKey:(NSString *)key {
    return [[self.sharedInstance userDefaults] setInteger:integer forKey:key];
}

#pragma mark - Activation

+ (BOOL)swipeUpEnabled {
    return [self boolForKey:kSwipeUpEnabled];
}

+ (BOOL)forceTouchMenuEnabled {
    return [self boolForKey:kForceTouchMenuEnabled];
}

#pragma mark - Panel Layout

+ (NSInteger)panelHeightPercentage {
    NSInteger percentage = [self integerForKey:kPanelHeightPercentage];
    return MIN(100, MAX(35, percentage));
}

#pragma mark - Appearance

+ (ADAppearanceStyle)appearanceStyle {
    ADAppearanceStyle currentValue = [ADSettings integerForKey:kAppearance];
    if (@available(iOS 13.0, *)) { } else { // iOS 12 or older
        if (currentValue == ADAppearanceStyleAutomatic) {
            [ADSettings setInteger:ADAppearanceStyleDark forKey:kAppearance];
            return ADAppearanceStyleDark;
        }
    }
    return currentValue;
}

+ (NSArray <NSString *> *)appearanceValues {
    if (@available(iOS 13.0, *)) {
        return @[[NSString stringWithFormat:@"%td",ADAppearanceStyleDark], [NSString stringWithFormat:@"%td",ADAppearanceStyleLight], [NSString stringWithFormat:@"%td",ADAppearanceStyleAutomatic]];
    } else {
        return @[[NSString stringWithFormat:@"%td",ADAppearanceStyleDark], [NSString stringWithFormat:@"%td",ADAppearanceStyleLight]];
    }
}

+ (NSArray <NSString *> *)appearanceTitles {
    if (@available(iOS 13.0, *)) {
        return @[[self titleForAppearanceStyle:ADAppearanceStyleDark], [self titleForAppearanceStyle:ADAppearanceStyleLight], [self titleForAppearanceStyle:ADAppearanceStyleAutomatic]];
    } else {
        return @[[self titleForAppearanceStyle:ADAppearanceStyleDark], [self titleForAppearanceStyle:ADAppearanceStyleLight]];
    }
}

+ (NSString *)titleForAppearanceStyle:(ADAppearanceStyle)style {
    switch (style) {
        case ADAppearanceStyleDark: return @"深色模式";
        case ADAppearanceStyleLight: return @"浅色模式";
        case ADAppearanceStyleAutomatic: return @"跟随系统";
        default: return @"未知";
    }
}

#pragma mark - App Launch Control

+ (NSString *)launchControlKeyWithPrefix:(NSString *)prefix bundleIdentifier:(NSString *)bundleIdentifier {
    if (prefix.length == 0 || bundleIdentifier.length == 0) return nil;
    return [NSString stringWithFormat:@"%@/%@", prefix, bundleIdentifier];
}

+ (BOOL)launchControlValueForPrefix:(NSString *)prefix bundleIdentifier:(NSString *)bundleIdentifier {
    NSString *key = [self launchControlKeyWithPrefix:prefix bundleIdentifier:bundleIdentifier];
    return key ? [self boolForKey:key] : NO;
}

+ (void)setLaunchControlValue:(BOOL)value prefix:(NSString *)prefix bundleIdentifier:(NSString *)bundleIdentifier {
    NSString *key = [self launchControlKeyWithPrefix:prefix bundleIdentifier:bundleIdentifier];
    if (key) [self setObject:@(value) forKey:key];
}

+ (BOOL)isBlockedFromLaunchingOtherApplications:(NSString *)bundleIdentifier {
    return [self launchControlValueForPrefix:kBlockedFromLaunchingSafariPrefix bundleIdentifier:bundleIdentifier]
        && [self launchControlValueForPrefix:kBlockedFromLaunchingAppStorePrefix bundleIdentifier:bundleIdentifier]
        && [self launchControlValueForPrefix:kBlockedFromLaunchingOthersPrefix bundleIdentifier:bundleIdentifier];
}

+ (void)setBlockedFromLaunchingOtherApplications:(BOOL)blocked bundleIdentifier:(NSString *)bundleIdentifier {
    [self setLaunchControlValue:blocked prefix:kBlockedFromLaunchingSafariPrefix bundleIdentifier:bundleIdentifier];
    [self setLaunchControlValue:blocked prefix:kBlockedFromLaunchingAppStorePrefix bundleIdentifier:bundleIdentifier];
    [self setLaunchControlValue:blocked prefix:kBlockedFromLaunchingOthersPrefix bundleIdentifier:bundleIdentifier];
}

+ (BOOL)isBlockedFromBeingLaunched:(NSString *)bundleIdentifier {
    return [self launchControlValueForPrefix:kBlockedFromBeingLaunchedPrefix bundleIdentifier:bundleIdentifier];
}

+ (void)setBlockedFromBeingLaunched:(BOOL)blocked bundleIdentifier:(NSString *)bundleIdentifier {
    [self setLaunchControlValue:blocked prefix:kBlockedFromBeingLaunchedPrefix bundleIdentifier:bundleIdentifier];
}

+ (NSArray<NSString *> *)customBlockedApplicationsForBundleIdentifier:(NSString *)bundleIdentifier {
    NSString *key = [self launchControlKeyWithPrefix:kCustomBlockedApplicationsPrefix bundleIdentifier:bundleIdentifier];
    id value = key ? [self objectForKey:key] : nil;
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

+ (void)setCustomBlockedApplications:(NSArray<NSString *> *)applications forBundleIdentifier:(NSString *)bundleIdentifier {
    NSString *key = [self launchControlKeyWithPrefix:kCustomBlockedApplicationsPrefix bundleIdentifier:bundleIdentifier];
    if (!key) return;
    NSArray *uniqueApplications = [[[NSSet setWithArray:applications ?: @[]] allObjects]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [self setObject:uniqueApplications forKey:key];
}

#pragma mark - Per-App Cache Automation

+ (BOOL)automaticallyClearsCachesForBundleIdentifier:(NSString *)bundleIdentifier {
    return [self launchControlValueForPrefix:kAutoClearCachesPrefix bundleIdentifier:bundleIdentifier];
}

+ (void)setAutomaticallyClearsCaches:(BOOL)enabled bundleIdentifier:(NSString *)bundleIdentifier {
    [self setLaunchControlValue:enabled prefix:kAutoClearCachesPrefix bundleIdentifier:bundleIdentifier];
}

+ (BOOL)shouldBlockSourceBundleIdentifier:(NSString *)sourceBundleIdentifier targetBundleIdentifier:(NSString *)targetBundleIdentifier {
    if (sourceBundleIdentifier.length == 0 || targetBundleIdentifier.length == 0) return NO;
    if ([sourceBundleIdentifier isEqualToString:targetBundleIdentifier]) return NO;

    if ([[self customBlockedApplicationsForBundleIdentifier:sourceBundleIdentifier]
            containsObject:targetBundleIdentifier]) return YES;

    // Only enforce requests with a real third-party source. This preserves icon launches,
    // SpringBoard restores, lock-screen transitions, system launches and AppData actions.
    NSSet *systemLaunchSources = [NSSet setWithObjects:
        @"com.apple.springboard", @"com.apple.backboardd", @"com.apple.frontboard.systemappservices",
        @"com.apple.runningboardd", @"com.apple.assertiond", nil];
    if ([systemLaunchSources containsObject:sourceBundleIdentifier]) return NO;

    NSString *sourcePrefix = kBlockedFromLaunchingOthersPrefix;
    if ([targetBundleIdentifier isEqualToString:@"com.apple.mobilesafari"]
        || [targetBundleIdentifier isEqualToString:@"com.apple.SafariViewService"]) {
        sourcePrefix = kBlockedFromLaunchingSafariPrefix;
    } else if ([targetBundleIdentifier isEqualToString:@"com.apple.AppStore"]
               || [targetBundleIdentifier isEqualToString:@"com.apple.MobileStore"]
               || [targetBundleIdentifier isEqualToString:@"com.apple.ios.StoreKitUIService"]) {
        sourcePrefix = kBlockedFromLaunchingAppStorePrefix;
    }

    if ([self launchControlValueForPrefix:sourcePrefix bundleIdentifier:sourceBundleIdentifier]) return YES;

    if ([self isBlockedFromBeingLaunched:targetBundleIdentifier]) {
        BOOL isSafariSource = [sourceBundleIdentifier isEqualToString:@"com.apple.mobilesafari"]
            || [sourceBundleIdentifier isEqualToString:@"com.apple.SafariViewService"];
        // Match NoRedirect's safety rule: ordinary Apple/system sources remain allowed,
        // while Safari and SafariViewService are treated as identifiable external sources.
        if ([sourceBundleIdentifier hasPrefix:@"com.apple."] && !isSafariSource) return NO;
        return YES;
    }
    return NO;
}

@end
