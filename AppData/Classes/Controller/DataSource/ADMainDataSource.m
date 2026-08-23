//
//  ADMainDataSource.m
//  AppData
//

#import "ADMainDataSource.h"
#import "ADAppData.h"
#import "ADDataViewController.h"
#import "ADActionsBarView.h"
#import "ADTitleSectionHeaderView.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

#ifndef IS_IPAD
#define IS_IPAD (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#endif

@interface UIImage (ADApplicationIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(NSInteger)format scale:(CGFloat)scale;
@end

@interface SSAccount : NSObject
- (BOOL)isActive;
- (BOOL)isLocalAccount;
- (NSString *)accountName;
- (void)setActive:(BOOL)active;
@end

@interface SSAccountStore : NSObject
+ (id)defaultStore;
- (NSArray *)accounts;
- (BOOL)saveAccount:(id)account verifyCredentials:(BOOL)verify error:(NSError **)error;
@end

@interface SSDevice : NSObject
+ (id)currentDevice;
- (void)reloadStoreFrontIdentifier;
@end

@interface SKUIApplicationController : NSObject
- (void)_resetUserInterfaceAfterStoreFrontChange;
@end

@interface SKUIItemStateCenter : NSObject
+ (id)defaultCenter;
- (id)_newPurchasesWithItems:(id)items;
- (void)_performPurchases:(id)purchases hasBundlePurchase:(BOOL)purchase withClientContext:(id)context completionBlock:(id)block;
@end

@interface SKUIItem : NSObject
- (id)initWithLookupDictionary:(id)dictionary;
@end

@interface SKUIItemOffer : NSObject
- (id)initWithLookupDictionary:(id)dictionary;
@end

@interface SKUIClientContext : NSObject
+ (id)defaultContext;
- (id)applicationController;
@end

typedef void (^ADAppSelectionCompletion)(NSArray<NSString *> *selectedBundleIdentifiers);

@interface ADAppSelectionViewController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<LSApplicationProxy *> *applications;
@property (nonatomic, copy) NSArray<LSApplicationProxy *> *filteredApplications;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedBundleIdentifiers;
@property (nonatomic, copy) ADAppSelectionCompletion completion;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *iconCache;
- (instancetype)initWithSelectedBundleIdentifiers:(NSArray<NSString *> *)selected excludingBundleIdentifier:(NSString *)excluded completion:(ADAppSelectionCompletion)completion;
- (NSArray<LSApplicationProxy *> *)applicationsByPrioritizingSelection:(NSArray<LSApplicationProxy *> *)applications;
@end

@implementation ADAppSelectionViewController

- (instancetype)initWithSelectedBundleIdentifiers:(NSArray<NSString *> *)selected excludingBundleIdentifier:(NSString *)excluded completion:(ADAppSelectionCompletion)completion {
    if (self = [super initWithStyle:UITableViewStylePlain]) {
        self.title = @"选择指定应用";
        self.completion = completion;
        self.iconCache = [NSCache new];
        self.iconCache.countLimit = 160;
        self.selectedBundleIdentifiers = [NSMutableSet setWithArray:selected ?: @[]];
        NSArray *installed = [[NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace] allInstalledApplications] ?: @[];
        if (excluded.length > 0) {
            installed = [installed filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(LSApplicationProxy *app, NSDictionary *bindings) {
                return ![app.bundleIdentifier isEqualToString:excluded];
            }]];
        }
        self.applications = [self applicationsByPrioritizingSelection:installed];
        self.filteredApplications = self.applications;
    }
    return self;
}

- (NSArray<LSApplicationProxy *> *)applicationsByPrioritizingSelection:(NSArray<LSApplicationProxy *> *)applications {
    return [applications sortedArrayUsingComparator:^NSComparisonResult(LSApplicationProxy *left, LSApplicationProxy *right) {
        BOOL leftSelected = [self.selectedBundleIdentifiers containsObject:left.bundleIdentifier];
        BOOL rightSelected = [self.selectedBundleIdentifiers containsObject:right.bundleIdentifier];
        if (leftSelected != rightSelected) return leftSelected ? NSOrderedAscending : NSOrderedDescending;

        NSString *leftName = left.localizedName ?: left.bundleIdentifier;
        NSString *rightName = right.localizedName ?: right.bundleIdentifier;
        NSComparisonResult nameResult = [leftName localizedCaseInsensitiveCompare:rightName];
        if (nameResult != NSOrderedSame) return nameResult;
        return [left.bundleIdentifier localizedCaseInsensitiveCompare:right.bundleIdentifier];
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancelSelection)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(finishSelection)];
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索应用名称或包标识符";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.tableView.tableFooterView = [UIView new];
    self.tableView.rowHeight = 64.0;
}

- (UIImage *)displayIconForBundleIdentifier:(NSString *)bundleIdentifier {
    if (bundleIdentifier.length == 0) return nil;
    UIImage *cached = [self.iconCache objectForKey:bundleIdentifier];
    if (cached) return cached;

    UIImage *source = nil;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        source = [UIImage _applicationIconImageForBundleIdentifier:bundleIdentifier
                                                             format:0
                                                              scale:[UIScreen mainScreen].scale];
    }
    if (!source) return nil;

    CGSize iconSize = CGSizeMake(42.0, 42.0);
    UIGraphicsBeginImageContextWithOptions(iconSize, NO, 0.0);
    UIBezierPath *clipPath = [UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, iconSize} cornerRadius:9.5];
    [clipPath addClip];
    [source drawInRect:(CGRect){CGPointZero, iconSize}];
    UIImage *displayIcon = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if (displayIcon) [self.iconCache setObject:displayIcon forKey:bundleIdentifier];
    return displayIcon;
}

- (void)cancelSelection {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)finishSelection {
    NSArray *selected = [[self.selectedBundleIdentifiers allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    if (self.completion) self.completion(selected);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text;
    if (query.length == 0) {
        self.filteredApplications = self.applications;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(LSApplicationProxy *app, NSDictionary *bindings) {
            return [app.localizedName localizedCaseInsensitiveContainsString:query]
                || [app.bundleIdentifier localizedCaseInsensitiveContainsString:query];
        }];
        self.filteredApplications = [self.applications filteredArrayUsingPredicate:predicate];
    }
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredApplications.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *reuseIdentifier = @"ADRedirectAppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    LSApplicationProxy *app = self.filteredApplications[indexPath.row];
    cell.textLabel.text = app.localizedName ?: app.bundleIdentifier;
    cell.detailTextLabel.text = app.bundleIdentifier;
    cell.imageView.image = [self displayIconForBundleIdentifier:app.bundleIdentifier];
    cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    cell.imageView.clipsToBounds = YES;
    cell.accessoryType = [self.selectedBundleIdentifiers containsObject:app.bundleIdentifier]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    LSApplicationProxy *app = self.filteredApplications[indexPath.row];
    if ([self.selectedBundleIdentifiers containsObject:app.bundleIdentifier]) {
        [self.selectedBundleIdentifiers removeObject:app.bundleIdentifier];
    } else if (app.bundleIdentifier.length > 0) {
        [self.selectedBundleIdentifiers addObject:app.bundleIdentifier];
    }
    self.applications = [self applicationsByPrioritizingSelection:self.applications];
    [self updateSearchResultsForSearchController:self.searchController];
}

@end

@implementation ADMainDataSource

- (instancetype)initWithAppData:(ADAppData *)data dataViewController:(ADDataViewController *)dataViewController {
    if (self = [super init]) {
        self.appData = data;
        self.dataViewController = dataViewController;
    }
    return self;
}

#pragma mark - Launch Control

- (NSString *)launchControlSummary {
    NSString *bundleIdentifier = self.appData.bundleIdentifier;
    BOOL blocksOutgoing = [ADSettings isBlockedFromLaunchingOtherApplications:bundleIdentifier];
    BOOL blocksIncoming = [ADSettings isBlockedFromBeingLaunched:bundleIdentifier];
    NSString *summary = @"未启用";
    if (blocksOutgoing && blocksIncoming) summary = @"双向禁止";
    else if (blocksOutgoing) summary = @"禁止跳出";
    else if (blocksIncoming) summary = @"禁止唤起";
    NSUInteger customCount = [ADSettings customBlockedApplicationsForBundleIdentifier:bundleIdentifier].count;
    return customCount > 0 ? @"启用指定" : summary;
}

- (void)showCustomBlockedApplicationPickerWithActionsBar:(ADActionsBarView *)actionsBar itemIndex:(NSInteger)itemIndex {
    NSString *bundleIdentifier = self.appData.bundleIdentifier;
    NSArray *selected = [ADSettings customBlockedApplicationsForBundleIdentifier:bundleIdentifier];
    ADAppSelectionViewController *picker = [[ADAppSelectionViewController alloc]
        initWithSelectedBundleIdentifiers:selected
        excludingBundleIdentifier:bundleIdentifier
        completion:^(NSArray<NSString *> *selectedBundleIdentifiers) {
            [ADSettings setCustomBlockedApplications:selectedBundleIdentifiers forBundleIdentifier:bundleIdentifier];
            [actionsBar setDetail:[self launchControlSummary] forItemAtIndex:itemIndex];
        }];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:picker];
    navigationController.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        navigationController.sheetPresentationController.detents = @[
            UISheetPresentationControllerDetent.mediumDetent,
            UISheetPresentationControllerDetent.largeDetent
        ];
        navigationController.sheetPresentationController.prefersGrabberVisible = YES;
    }
    [self.dataViewController presentViewController:navigationController animated:YES completion:nil];
}

- (void)showLaunchControlMenuWithActionsBar:(ADActionsBarView *)actionsBar itemIndex:(NSInteger)itemIndex {
    NSString *bundleIdentifier = self.appData.bundleIdentifier;
    if (bundleIdentifier.length == 0) return;

    BOOL blocksOutgoing = [ADSettings isBlockedFromLaunchingOtherApplications:bundleIdentifier];
    BOOL blocksIncoming = [ADSettings isBlockedFromBeingLaunched:bundleIdentifier];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"跳转控制"
                                                                  message:@"按 App 单独控制跨应用启动。系统启动、桌面图标、AppData 面板、自身唤起及无法识别真实第三方来源的请求始终放行。"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *outgoingTitle = [NSString stringWithFormat:@"%@ 禁止启动其他应用程序", blocksOutgoing ? @"✓" : @"○"];
    [menu addAction:[UIAlertAction actionWithTitle:outgoingTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [ADSettings setBlockedFromLaunchingOtherApplications:!blocksOutgoing bundleIdentifier:bundleIdentifier];
        [actionsBar setDetail:[self launchControlSummary] forItemAtIndex:itemIndex];
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    }]];

    NSString *incomingTitle = [NSString stringWithFormat:@"%@ 禁止被其他应用程序启动", blocksIncoming ? @"✓" : @"○"];
    [menu addAction:[UIAlertAction actionWithTitle:incomingTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [ADSettings setBlockedFromBeingLaunched:!blocksIncoming bundleIdentifier:bundleIdentifier];
        [actionsBar setDetail:[self launchControlSummary] forItemAtIndex:itemIndex];
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    }]];

    NSUInteger customCount = [ADSettings customBlockedApplicationsForBundleIdentifier:bundleIdentifier].count;
    NSString *customTitle = customCount > 0
        ? [NSString stringWithFormat:@"选择指定应用（已选 %tu 个）", customCount]
        : @"选择指定应用";
    [menu addAction:[UIAlertAction actionWithTitle:customTitle style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self showCustomBlockedApplicationPickerWithActionsBar:actionsBar itemIndex:itemIndex];
        });
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (IS_IPAD && menu.popoverPresentationController) {
        menu.popoverPresentationController.sourceView = self.dataViewController.view;
        menu.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.dataViewController.view.bounds), CGRectGetMidY(self.dataViewController.view.bounds), 1, 1);
        menu.popoverPresentationController.permittedArrowDirections = 0;
    }
    [self.dataViewController presentViewController:menu animated:YES completion:nil];
}

#pragma mark - Downgrade Core Logic

- (void)showDowngradeMessage:(NSString *)message title:(NSString *)title {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
    if (IS_IPAD) {
        self.dataViewController.dockDismissed = [ADDataViewController dismissFloatingDockIfNeededWithCompletion:^{
            [self.dataViewController presentViewController:alert animated:YES completion:nil];
        }];
    } else {
        [self.dataViewController presentViewController:alert animated:YES completion:nil];
    }
}

- (NSArray<NSString *> *)downgrade_supportedAppStoreCountryCodes {
    return @[
        @"cn", @"us",
        @"ae", @"ag", @"ai", @"al", @"am", @"ao", @"ar", @"at", @"au", @"az",
        @"bb", @"be", @"bf", @"bg", @"bh", @"bj", @"bm", @"bn", @"bo", @"br",
        @"bs", @"bt", @"bw", @"by", @"bz",
        @"ca", @"cg", @"ch", @"ci", @"cl", @"cm", @"co", @"cr", @"cv", @"cy", @"cz",
        @"de", @"dk", @"dm", @"do", @"dz",
        @"ec", @"ee", @"eg", @"es",
        @"fi", @"fj", @"fm", @"fr",
        @"gb", @"gd", @"gh", @"gm", @"gr", @"gt", @"gw", @"gy",
        @"hk", @"hn", @"hr", @"hu",
        @"id", @"ie", @"il", @"in", @"is", @"it",
        @"jm", @"jo", @"jp",
        @"ke", @"kg", @"kh", @"kn", @"kr", @"kw", @"ky", @"kz",
        @"la", @"lb", @"lc", @"lk", @"lr", @"lt", @"lu", @"lv",
        @"md", @"mg", @"mk", @"ml", @"mn", @"mo", @"mr", @"ms", @"mt", @"mu", @"mw", @"mx", @"my",
        @"na", @"ne", @"ng", @"ni", @"nl", @"no", @"np", @"nz",
        @"om",
        @"pa", @"pe", @"pg", @"ph", @"pk", @"pl", @"pt", @"pw", @"py",
        @"qa",
        @"ro", @"ru", @"rw",
        @"sa", @"sb", @"sc", @"se", @"sg", @"si", @"sk", @"sl", @"sn", @"sr", @"st", @"sv", @"sz",
        @"tc", @"td", @"th", @"tj", @"tm", @"tn", @"tr", @"tt", @"tw", @"tz",
        @"ua", @"ug", @"uy", @"uz",
        @"vc", @"ve", @"vg", @"vn",
        @"ye",
        @"za", @"zm", @"zw"
    ];
}

- (void)downgrade_fetchTrackIDWithCountryCodes:(NSArray<NSString *> *)countryCodes
                                         index:(NSInteger)index
                                    completion:(void(^)(long long trackId, NSError *err))completion {
    if (index >= countryCodes.count) {
        if (completion) {
            completion(0, [NSError errorWithDomain:@"Downgrade"
                                              code:404
                                          userInfo:@{NSLocalizedDescriptionKey: @"已尝试所有支持的 App Store 地区，仍未找到该应用"}]);
        }
        return;
    }

    NSString *bundleId = self.appData.bundleIdentifier;
    NSString *countryCode = countryCodes[index];
    NSString *urlString = [NSString stringWithFormat:@"https://itunes.apple.com/lookup?bundleId=%@&limit=1&media=software&country=%@", bundleId, countryCode];
    NSURL *url = [NSURL URLWithString:urlString];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:[NSURLRequest requestWithURL:url]
                                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self downgrade_fetchTrackIDWithCountryCodes:countryCodes index:index + 1 completion:completion];
            });
            return;
        }

        NSDictionary *json = nil;
        if (data) {
            json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        }
        NSArray *results = json[@"results"];

        if ([results isKindOfClass:[NSArray class]] && results.count > 0) {
            long long trackId = [results.firstObject[@"trackId"] longLongValue];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(trackId, nil);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self downgrade_fetchTrackIDWithCountryCodes:countryCodes index:index + 1 completion:completion];
            });
        }
    }];
    [task resume];
}

- (void)downgrade_fetchTrackIDWithCompletion:(void(^)(long long trackId, NSError *err))completion {
    NSArray<NSString *> *countryCodes = [self downgrade_supportedAppStoreCountryCodes];
    [self downgrade_fetchTrackIDWithCountryCodes:countryCodes index:0 completion:completion];
}

- (NSString *)downgrade_safeStringFromValue:(id)value maximumLength:(NSUInteger)maximumLength {
    NSString *string = nil;
    if ([value isKindOfClass:[NSString class]]) {
        string = value;
    } else if ([value isKindOfClass:[NSNumber class]]) {
        string = [(NSNumber *)value stringValue];
    }
    string = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (string.length == 0 || string.length > maximumLength) return nil;
    return string;
}

- (BOOL)downgrade_requireActiveStoreAccount {
    Class accountStoreClass = objc_getClass("SSAccountStore");
    if (!accountStoreClass || ![accountStoreClass respondsToSelector:@selector(defaultStore)]) {
        [self showDowngradeMessage:@"无法读取 App Store 登录状态，请确认已在 App Store 登录后重试。" title:@"无法检查账号"];
        return NO;
    }

    SSAccountStore *store = [accountStoreClass defaultStore];
    for (SSAccount *account in [store accounts]) {
        if ([account respondsToSelector:@selector(isActive)] && [account isActive] &&
            (![account respondsToSelector:@selector(isLocalAccount)] || ![account isLocalAccount])) {
            return YES;
        }
    }

    [self showDowngradeMessage:@"当前未登录 App Store 账号，请先登录后再试。" title:@"未登录账号"];
    return NO;
}

- (SSAccount *)downgrade_activeStoreAccountFromStore:(SSAccountStore *)store {
    for (SSAccount *account in [store accounts]) {
        if ([account isActive] && ![account isLocalAccount]) return account;
    }
    return nil;
}

- (NSString *)downgrade_purchaserAccountName {
    NSString *bundlePath = self.appData.bundleURL.path;
    NSString *metadataPath = [[bundlePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"iTunesMetadata.plist"];
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
    id value = metadata[@"com.apple.iTunesStore.downloadInfo"][@"accountInfo"][@"AppleID"];
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : nil;
}

- (BOOL)switchStoreAccountTo:(SSAccount *)targetAccount error:(NSError **)error {
    if (!targetAccount) return NO;
    SSAccountStore *store = [objc_getClass("SSAccountStore") defaultStore];
    NSArray *accounts = [store accounts];
    SSAccount *previousAccount = [self downgrade_activeStoreAccountFromStore:store];
    for (SSAccount *account in accounts) {
        [account setActive:(account == targetAccount)];
    }

    // This must verify through StoreServices. With NO, the account becomes active
    // before the system password sheet finishes and the original downgrade request
    // is resumed too early. StoreServices retains the authenticated account session;
    // AppData never receives or stores the password itself.
    NSError *verificationError = nil;
    BOOL saved = [store saveAccount:targetAccount verifyCredentials:YES error:&verificationError];
    if (!saved || verificationError) {
        // A secondary Media & Purchases account can be saved and usable while
        // StoreServices refuses to verify it from SpringBoard (commonly after
        // switching back to the iCloud account's storefront). Match StoreSwitcher:
        // persist that already-known account without verification and let the
        // AppStoreDaemon purchase request perform any authentication it requires.
        NSLog(@"[AppData Downgrade] StoreServices verification unavailable; retrying saved-account switch (%@/%ld)",
              verificationError.domain ?: @"unknown", (long)verificationError.code);
        NSError *switchError = nil;
        saved = [store saveAccount:targetAccount verifyCredentials:NO error:&switchError];
        if (!saved || switchError) {
            if (error) *error = switchError ?: verificationError;
        }
    }
    if (!saved || (error && *error)) {
        for (SSAccount *account in accounts) {
            [account setActive:(account == previousAccount)];
        }
        if (previousAccount) {
            [store saveAccount:previousAccount verifyCredentials:NO error:nil];
        }
        return NO;
    }

    NSString *accountName = [targetAccount accountName];
    if (accountName.length > 0) {
        [accountName writeToFile:@"/var/mobile/Library/Preferences/com.storeswitcher.active.txt"
                      atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.storeswitcher.accounts_changed"), NULL, NULL, YES);
    id device = [objc_getClass("SSDevice") currentDevice];
    if ([device respondsToSelector:@selector(reloadStoreFrontIdentifier)]) [device reloadStoreFrontIdentifier];
    id applicationController = [[objc_getClass("SKUIClientContext") defaultContext] applicationController];
    if ([applicationController respondsToSelector:@selector(_resetUserInterfaceAfterStoreFrontChange)]) {
        [applicationController _resetUserInterfaceAfterStoreFrontChange];
    }
    return YES;
}

- (void)downgrade_verifyOwnershipWithCompletion:(void(^)(BOOL success))completion {
    if (![self downgrade_requireActiveStoreAccount]) {
        if (completion) completion(NO);
        return;
    }

    SSAccountStore *store = [objc_getClass("SSAccountStore") defaultStore];
    SSAccount *activeAccount = [self downgrade_activeStoreAccountFromStore:store];
    NSString *activeName = [activeAccount accountName];
    NSString *purchaserName = [self downgrade_purchaserAccountName];
    if (purchaserName.length == 0 || [activeName caseInsensitiveCompare:purchaserName] == NSOrderedSame) {
        if (completion) completion(YES);
        return;
    }

    __block SSAccount *purchaserAccount = nil;
    for (SSAccount *account in [store accounts]) {
        if (![account isLocalAccount] && [[account accountName] caseInsensitiveCompare:purchaserName] == NSOrderedSame) {
            purchaserAccount = account;
            break;
        }
    }

    NSString *message = [NSString stringWithFormat:@"当前账号与购买账号不一致。\n购买账号：%@\n当前账号：%@", purchaserName, activeName ?: @"未知"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要切换账号" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        if (completion) completion(NO);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"切换并继续" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        if (!purchaserAccount) {
            [self showDowngradeMessage:@"设备中没有保存该购买账号，请先在 App Store 登录该账号。" title:@"无法切换"];
            if (completion) completion(NO);
            return;
        }
        NSError *switchError = nil;
        if (![self switchStoreAccountTo:purchaserAccount error:&switchError]) {
            NSLog(@"[AppData Downgrade] persistent account switch failed: %@", switchError.localizedDescription ?: @"unknown error");
            [self showDowngradeMessage:@"账号切换失败，请在 App Store 中手动切换后重试。" title:@"切换失败"];
            if (completion) completion(NO);
            return;
        }
        // Let StoreServices publish the selected account/storefront before rebuilding
        // the purchase request. AppStoreDaemon handles any remaining authentication.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.75 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
            if (completion) completion(YES);
        });
    }]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self.dataViewController presentViewController:alert animated:YES completion:nil];
    });
}

- (NSArray<NSDictionary *> *)downgrade_candidateRecordsFromJSON:(id)json depth:(NSUInteger)depth {
    if (depth > 4 || !json) return @[];
    if ([json isKindOfClass:[NSArray class]]) {
        NSMutableArray *records = [NSMutableArray array];
        for (id value in (NSArray *)json) {
            if ([value isKindOfClass:[NSDictionary class]]) [records addObject:value];
        }
        return records;
    }
    if (![json isKindOfClass:[NSDictionary class]]) return @[];

    NSDictionary *dictionary = (NSDictionary *)json;
    NSArray *containerKeys = @[@"data", @"versions", @"result", @"results", @"list", @"items"];
    for (NSString *key in containerKeys) {
        id child = dictionary[key];
        NSArray *records = [self downgrade_candidateRecordsFromJSON:child depth:depth + 1];
        if (records.count > 0) return records;
    }
    return @[];
}

- (NSDictionary *)downgrade_normalizedVersionRecord:(NSDictionary *)record
                                               appID:(NSString *)appID
                                              source:(NSString *)source {
    if (![record isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *versionIDKeys = @[@"external_identifier", @"versionId", @"version_id", @"id"];
    NSArray *versionKeys = @[@"bundle_version", @"version", @"bundleShortVersionString"];
    NSArray *dateKeys = @[@"created_at", @"createTime", @"updateTime", @"date", @"time", @"release_date"];
    NSArray *sizeKeys = @[@"size", @"fileSize", @"fileSizeBytes"];

    NSString *(^firstString)(NSArray *) = ^NSString *(NSArray *keys) {
        for (NSString *key in keys) {
            NSString *value = [self downgrade_safeStringFromValue:record[key] maximumLength:128];
            if (value) return value;
        }
        return nil;
    };
    NSString *versionID = firstString(versionIDKeys);
    NSString *version = firstString(versionKeys);
    if (!versionID || !version) return nil;

    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if (versionID.length > 32 || [versionID rangeOfCharacterFromSet:nonDigits].location != NSNotFound || versionID.longLongValue <= 0) return nil;
    NSCharacterSet *allowedVersionCharacters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-+() "];
    if (version.length > 64 || [version rangeOfCharacterFromSet:[allowedVersionCharacters invertedSet]].location != NSNotFound) return nil;

    NSString *date = firstString(dateKeys) ?: @"";
    NSString *size = firstString(sizeKeys) ?: @"";
    return @{ @"appId": appID, @"version": version, @"versionId": versionID,
              @"date": date, @"size": size, @"source": source };
}

- (NSArray<NSDictionary *> *)downgrade_normalizedVersionsFromJSON:(id)json appID:(NSString *)appID source:(NSString *)source {
    NSMutableArray *versions = [NSMutableArray array];
    for (NSDictionary *record in [self downgrade_candidateRecordsFromJSON:json depth:0]) {
        NSDictionary *normalized = [self downgrade_normalizedVersionRecord:record appID:appID source:source];
        if (normalized) [versions addObject:normalized];
    }
    return versions;
}

- (void)downgrade_fetchVersionProviders:(NSArray<NSDictionary *> *)providers
                                  index:(NSUInteger)index
                                  appID:(NSString *)appID
                                results:(NSMutableArray<NSDictionary *> *)results
                               seenKeys:(NSMutableSet<NSString *> *)seenKeys
                                 errors:(NSMutableArray<NSString *> *)errors
                             completion:(void(^)(NSArray *versions, NSError *err))completion {
    if (index >= providers.count) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (results.count > 0) {
                if (completion) completion([results copy], nil);
            } else {
                NSString *details = errors.count > 0 ? [errors componentsJoinedByString:@"；"] : @"所有数据源均未返回有效版本";
                NSError *error = [NSError errorWithDomain:@"Downgrade.VersionHistory" code:404 userInfo:@{NSLocalizedDescriptionKey: [@"未找到历史版本记录：" stringByAppendingString:details]}];
                if (completion) completion(nil, error);
            }
        });
        return;
    }

    NSDictionary *provider = providers[index];
    NSString *name = provider[@"name"];
    NSString *urlString = [NSString stringWithFormat:provider[@"url"], appID];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:12.0];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 12.0;
    configuration.timeoutIntervalForResource = 18.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        NSString *failure = nil;
        NSArray *normalized = @[];
        NSInteger statusCode = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (networkError) {
            failure = @"网络错误";
        } else if (statusCode < 200 || statusCode >= 300) {
            failure = [NSString stringWithFormat:@"HTTP %ld", (long)statusCode];
        } else if (data.length == 0 || data.length > 5 * 1024 * 1024) {
            failure = @"响应为空或过大";
        } else {
            NSError *jsonError = nil;
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError || (! [json isKindOfClass:[NSDictionary class]] && ![json isKindOfClass:[NSArray class]])) {
                failure = @"JSON 格式异常";
            } else {
                normalized = [self downgrade_normalizedVersionsFromJSON:json appID:appID source:name];
                if (normalized.count == 0) failure = @"没有有效版本";
            }
        }

        if (failure) {
            [errors addObject:[NSString stringWithFormat:@"%@：%@", name, failure]];
            NSLog(@"[AppData Downgrade] provider=%@ failed: %@", name, failure);
        } else {
            NSUInteger added = 0;
            for (NSDictionary *version in normalized) {
                NSString *key = [NSString stringWithFormat:@"%@|%@", version[@"versionId"], version[@"version"]];
                if (![seenKeys containsObject:key]) {
                    [seenKeys addObject:key];
                    [results addObject:version];
                    added++;
                } else {
                    // Keep provider priority, but let later providers fill metadata gaps.
                    NSUInteger existingIndex = [results indexOfObjectPassingTest:^BOOL(NSDictionary *existing, NSUInteger idx, BOOL *stop) {
                        NSString *existingKey = [NSString stringWithFormat:@"%@|%@", existing[@"versionId"], existing[@"version"]];
                        return [existingKey isEqualToString:key];
                    }];
                    if (existingIndex != NSNotFound) {
                        NSMutableDictionary *filled = [results[existingIndex] mutableCopy];
                        if ([filled[@"date"] length] == 0 && [version[@"date"] length] > 0) filled[@"date"] = version[@"date"];
                        if ([filled[@"size"] length] == 0 && [version[@"size"] length] > 0) filled[@"size"] = version[@"size"];
                        results[existingIndex] = [filled copy];
                    }
                }
            }
            NSLog(@"[AppData Downgrade] provider=%@ valid=%lu added=%lu", name, (unsigned long)normalized.count, (unsigned long)added);
        }
        [session finishTasksAndInvalidate];
        [self downgrade_fetchVersionProviders:providers index:index + 1 appID:appID results:results seenKeys:seenKeys errors:errors completion:completion];
    }];
    [task resume];
}

- (void)downgrade_fetchVersionsForTrackID:(long long)trackId completion:(void(^)(NSArray *versions, NSError *err))completion {
    NSString *appID = [NSString stringWithFormat:@"%lld", trackId];
    NSArray *providers = @[
        @{ @"name": @"timbrd", @"url": @"https://api.timbrd.com/apple/app-version/index.php?id=%@" },
        @{ @"name": @"agzy", @"url": @"https://app.agzy.cn/searchVersion?appid=%@" },
        @{ @"name": @"bilin", @"url": @"https://apis.bilin.eu.org/history/%@" }
    ];
    [self downgrade_fetchVersionProviders:providers index:0 appID:appID results:[NSMutableArray array] seenKeys:[NSMutableSet set] errors:[NSMutableArray array] completion:completion];
}

- (void)_fallback_downgrade_installWithTrackID:(long long)trackId versionID:(long long)versionId {
    static dispatch_once_t storeKitLoadToken;
    static void *storeKitUIHandle = NULL;
    dispatch_once(&storeKitLoadToken, ^{
        storeKitUIHandle = dlopen("/System/Library/PrivateFrameworks/StoreKitUI.framework/StoreKitUI", RTLD_LAZY | RTLD_LOCAL);
    });
    if (!storeKitUIHandle || !objc_getClass("SKUIItemOffer") || !objc_getClass("SKUIItem") ||
        !objc_getClass("SKUIItemStateCenter") || !objc_getClass("SKUIClientContext")) {
        NSLog(@"[AppData Downgrade] StoreKitUI fallback is unavailable");
        [self showDowngradeMessage:@"当前系统不支持降级下载通道。" title:@"提交失败"];
        return;
    }

    NSString *adamId = [NSString stringWithFormat:@"%lld", trackId];
    NSString *appExtVrsId = [NSString stringWithFormat:@"%lld", versionId];
    NSString *offerString = [NSString stringWithFormat:@"productType=C&price=0&salableAdamId=%@&pricingParameters=pricingParameter&appExtVrsId=%@&clientBuyId=1&installed=0&trolled=1", adamId, appExtVrsId];

    NSDictionary *offerDict = @{@"buyParams": offerString};
    NSDictionary *itemDict = @{@"_itemOffer": adamId};

    id offer = [[objc_getClass("SKUIItemOffer") alloc] initWithLookupDictionary:offerDict];
    id item = [[objc_getClass("SKUIItem") alloc] initWithLookupDictionary:itemDict];
    [item setValue:offer forKey:@"_itemOffer"];
    [item setValue:@"iosSoftware" forKey:@"_itemKindString"];
    [item setValue:@(versionId) forKey:@"_versionIdentifier"];

    id center = [objc_getClass("SKUIItemStateCenter") defaultCenter];
    NSArray *items = @[item];

    [center _performPurchases:[center _newPurchasesWithItems:items] hasBundlePurchase:NO withClientContext:[objc_getClass("SKUIClientContext") defaultContext] completionBlock:^(id arg1){}];
}

- (void)downgrade_installWithTrackID:(long long)trackId versionID:(long long)versionId {
    NSString *adamId = [NSString stringWithFormat:@"%lld", trackId];
    NSString *appExtVrsId = [NSString stringWithFormat:@"%lld", versionId];
    NSString *buyParameters = [NSString stringWithFormat:@"productType=C&price=0&salableAdamId=%@&pricingParameters=pricingParameter&appExtVrsId=%@&clientBuyId=1&installed=0&trolled=1", adamId, appExtVrsId];

    static dispatch_once_t loadToken;
    static void *appStoreDaemonHandle = NULL;
    dispatch_once(&loadToken, ^{
        appStoreDaemonHandle = dlopen("/System/Library/PrivateFrameworks/AppStoreDaemon.framework/AppStoreDaemon", RTLD_LAZY | RTLD_LOCAL);
    });

    Class purchaseClass = NSClassFromString(@"ASDPurchase");
    Class managerClass = NSClassFromString(@"ASDPurchaseManager");
    if (!appStoreDaemonHandle || !purchaseClass || !managerClass) {
        NSLog(@"[AppData Downgrade] AppStoreDaemon unavailable; using StoreKitUI fallback");
        [self _fallback_downgrade_installWithTrackID:trackId versionID:versionId];
        return;
    }

    @try {
        id purchase = [[purchaseClass alloc] init];
        SEL setBuyParametersSelector = NSSelectorFromString(@"setBuyParameters:");
        SEL setIsRedownloadSelector = NSSelectorFromString(@"setIsRedownload:");
        if (!purchase || ![purchase respondsToSelector:setBuyParametersSelector]) {
            @throw [NSException exceptionWithName:@"AppDataASDPurchaseUnavailable" reason:@"ASDPurchase does not accept buy parameters" userInfo:nil];
        }
        ((void (*)(id, SEL, id))objc_msgSend)(purchase, setBuyParametersSelector, buyParameters);
        if ([purchase respondsToSelector:setIsRedownloadSelector]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(purchase, setIsRedownloadSelector, YES);
        }

        id manager = nil;
        for (NSString *singletonName in @[@"sharedManager", @"sharedInstance", @"defaultManager"]) {
            SEL singletonSelector = NSSelectorFromString(singletonName);
            if ([managerClass respondsToSelector:singletonSelector]) {
                manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, singletonSelector);
                if (manager) break;
            }
        }
        if (!manager) {
            @throw [NSException exceptionWithName:@"AppDataASDManagerUnavailable" reason:@"ASDPurchaseManager singleton is unavailable" userInfo:nil];
        }

        SEL startSelector = NSSelectorFromString(@"startPurchase:withResultHandler:");
        if ([manager respondsToSelector:startSelector]) {
            __weak typeof(self) weakSelf = self;
            void (^resultHandler)(id, NSError *) = ^(id result, NSError *error) {
                if (!error) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSLog(@"[AppData Downgrade] AppStoreDaemon rejected request; using StoreKitUI fallback: %@", error.localizedDescription ?: @"unknown error");
                    [weakSelf _fallback_downgrade_installWithTrackID:trackId versionID:versionId];
                });
            };
            ((void (*)(id, SEL, id, id))objc_msgSend)(manager, startSelector, purchase, resultHandler);
            NSLog(@"[AppData Downgrade] submitted through AppStoreDaemon");
            return;
        }

        SEL performSelector = NSSelectorFromString(@"_performPurchases:hasBundlePurchase:withClientContext:completionBlock:");
        if ([manager respondsToSelector:performSelector]) {
            id context = [objc_getClass("SKUIClientContext") defaultContext];
            ((void (*)(id, SEL, id, BOOL, id, id))objc_msgSend)(manager, performSelector, @[purchase], NO, context, ^(id result) {});
            NSLog(@"[AppData Downgrade] submitted through AppStoreDaemon purchase manager");
            return;
        }

        @throw [NSException exceptionWithName:@"AppDataASDSelectorUnavailable" reason:@"No supported AppStoreDaemon purchase selector" userInfo:nil];
    } @catch (NSException *exception) {
        NSLog(@"[AppData Downgrade] AppStoreDaemon invocation failed; using StoreKitUI fallback: %@", exception.reason ?: @"unknown error");
        [self _fallback_downgrade_installWithTrackID:trackId versionID:versionId];
    }
}

- (void)downgrade_presentVersionSelection:(NSArray *)versions trackID:(long long)trackId {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择版本" message:@"请选择要降级的版本" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *sortedVersions = [versions sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO]]];

    for (NSDictionary *ver in sortedVersions) {
        NSString *bVer = ver[@"version"] ?: @"暂无";
        NSString *extId = ver[@"versionId"] ?: @"";
        NSString *source = ver[@"source"] ?: @"";
        NSString *title = [NSString stringWithFormat:@"%@ (%@) · %@", bVer, extId, source];

        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            long long versionId = [ver[@"versionId"] longLongValue];
            [self downgrade_installWithTrackID:trackId versionID:versionId];
            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
            [self.dataViewController dismissImmediately];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (IS_IPAD && alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.dataViewController.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.dataViewController.view.bounds.size.width / 2.0, self.dataViewController.view.bounds.size.height / 2.0, 1.0, 1.0);
        alert.popoverPresentationController.permittedArrowDirections = 0;
    }
    [self.dataViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (!self.appData) {
        return 0;
    }
    return 3;
}

- (NSInteger)tableView:(nonnull UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isContainersSection:section]) {
        NSInteger rows = 0;
        if (self.appData.bundleURL) rows++;
        if (self.appData.dataContainerURL) rows++;
        return rows;
    } else if ([self isAppGroupsSection:section]) {
        return self.appData.appGroups.count;
    } else if ([self isManageSection:section]) {
        return 2;
    }
    return 0;
}

- (BOOL)isManageSection:(NSInteger)section {
    return section == 0;
}
- (BOOL)isContainersSection:(NSInteger)section {
    return section == 1;
}
- (BOOL)isAppGroupsSection:(NSInteger)section {
    return section == 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isContainersSection:indexPath.section] || [self isAppGroupsSection:indexPath.section]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"InfoCellIdentifier"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"InfoCellIdentifier"];
            cell.backgroundColor = [UIColor clearColor];
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
            cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        }
        cell.accessoryView = [ADAppearance.sharedInstance tableCellChevronImageView];
        [ADAppearance applyStylesToCell:cell];
        if ([self isContainersSection:indexPath.section]) {
            if (indexPath.row == 0) {
                cell.textLabel.text = @"应用目录";
                cell.detailTextLabel.text = self.appData.bundleURL.path;
            } else if (indexPath.row == 1) {
                cell.textLabel.text = @"数据目录";
                cell.detailTextLabel.text = self.appData.dataContainerURL.path;
            }
        } else if ([self isAppGroupsSection:indexPath.section]) {
            ADAppDataGroup *group = [self.appData.appGroups objectAtIndex:indexPath.row];
            cell.textLabel.text = group.identifier;
            cell.detailTextLabel.text = group.url.path;
        }
        return cell;
    } else if ([self isManageSection:indexPath.section]) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ManageCellIdentifier"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"ManageCellIdentifier"];
                cell.backgroundColor = [UIColor clearColor];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                cell.accessoryType = UITableViewCellAccessoryNone;

                ADActionsBarView *actionsBar = [[ADActionsBarView alloc] init];
                actionsBar.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:actionsBar];
                [actionsBar.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor].active = YES;
                [actionsBar.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor].active = YES;
                [actionsBar.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor].active = YES;
                [actionsBar.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor].active = YES;
                __weak ADActionsBarView *weakActionsBar = actionsBar;

                // 1. Clear Caches
                ADActionBarBlock clearCacheHandler = ^{
                    NSInteger itemIndex = 0;
                    [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                    [weakActionsBar setDetail:@"清理中..." forItemAtIndex:itemIndex];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        [self.appData clearAppCachesWithCompletion:^{
                            [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                            [weakActionsBar setDetail:@"已清除!" forItemAtIndex:itemIndex];
                            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                if ([ADSettings automaticallyClearsCachesForBundleIdentifier:self.appData.bundleIdentifier]) {
                                    [weakActionsBar setDetail:@"自动清理" forItemAtIndex:itemIndex];
                                } else {
                                    [self.appData getCachesDirectorySizeWithCompletion:^(NSString *formattedSize) {
                                        [weakActionsBar setDetail:formattedSize forItemAtIndex:itemIndex];
                                    }];
                                }
                            });
                        }];
                    });
                };
                ADActionBarBlock autoClearCacheHandler = ^{
                    NSString *bundleIdentifier = self.appData.bundleIdentifier;
                    BOOL enabled = ![ADSettings automaticallyClearsCachesForBundleIdentifier:bundleIdentifier];
                    [ADSettings setAutomaticallyClearsCaches:enabled bundleIdentifier:bundleIdentifier];
                    if (enabled) {
                        [weakActionsBar setDetail:@"自动清理" forItemAtIndex:0];
                        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                    } else {
                        [weakActionsBar setDetail:@"计算中..." forItemAtIndex:0];
                        [self.appData getCachesDirectorySizeWithCompletion:^(NSString *formattedSize) {
                            [weakActionsBar setDetail:formattedSize forItemAtIndex:0];
                        }];
                        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeWarning];
                    }
                };
                [actionsBar addItemWithTitle:@"清理缓存"
                                      detail:@"计算中..."
                                       image:[ADHelper imageNamed:@"ClearCache"]
                                     handler:clearCacheHandler
                            longPressHandler:autoClearCacheHandler];

                // 2. Clear App Data
                [actionsBar addItemWithTitle:@"清理数据"
                                      detail:@"计算中..."
                                       image:[ADHelper imageNamed:@"ClearData"]
                                     handler:^{
                    if (self.appData.isApplication) {
                        [self showDestructiveConfirmationAlertWithTitle:@"清理应用数据" message:@"清理应用数据将只会删除应用沙盒中的“Library”和“Documents”文件夹，不会删除App Groups分组数据。" confirmTitle:@"清理" confirmHandler:^{
                            NSInteger itemIndex = 1;
                            [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                            [weakActionsBar setDetail:@"清理中..." forItemAtIndex:itemIndex];
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                [self.appData resetDiskContentWithCompletion:^{
                                    [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                    [weakActionsBar setDetail:@"已清理!" forItemAtIndex:itemIndex];
                                    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                        [self.appData getAppUsageDirectorySizeWithCompletion:^(NSString *formattedSize) {
                                            [weakActionsBar setDetail:formattedSize forItemAtIndex:itemIndex];
                                        }];
                                    });
                                }];
                            });
                        }];
                    }
                }];

                // 3. Reset Permissions
                [actionsBar addItemWithTitle:@"重置权限"
                                      detail:[NSString stringWithFormat:@"%td",[self.appData getPermissions].count]
                                       image:[ADHelper imageNamed:@"ResetPermissions"]
                                     handler:^{
                    if (self.appData.isApplication) {
                        [self showDestructiveConfirmationAlertWithTitle:@"重置应用权限" message:@"这将清除该应用访问通讯录、照片、相机等的所有权限。\n下次打开该应用时会重新请求这些权限。"
                                                           confirmTitle:@"重置" confirmHandler:^{
                            NSInteger itemIndex = 2;
                            [self.appData resetAllAppPermissions];
                            [weakActionsBar setDetail:@"已重置!" forItemAtIndex:itemIndex];
                            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                               [weakActionsBar setDetail:[NSString stringWithFormat:@"%td",[self.appData getPermissions].count] forItemAtIndex:itemIndex];
                            });
                        }];
                    }
                }];

                // 4. Downgrade App
                UIImage *downgradeImage = nil;
                if (@available(iOS 13.0, *)) {
                    downgradeImage = [UIImage systemImageNamed:@"arrow.down.circle"];
                }
                if (!downgradeImage) {
                    downgradeImage = [ADHelper imageNamed:@"ClearData"];
                }

                [actionsBar addItemWithTitle:@"降级应用"
                                      detail:@"版本回退"
                                       image:downgradeImage
                                     handler:^{
                    if (self.appData.isApplication && [self.appData hasAppStoreApp]) {
                        NSInteger itemIndex = 4;
                        UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"应用降级"
                                                                                             message:@"请选择降级方式"
                                                                                      preferredStyle:UIAlertControllerStyleAlert];

                        [actionSheet addAction:[UIAlertAction actionWithTitle:@"从服务器获取" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                            [self downgrade_verifyOwnershipWithCompletion:^(BOOL accountReady) {
                                if (!accountReady) return;
                                [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                                [weakActionsBar setDetail:@"查询信息..." forItemAtIndex:itemIndex];
                                [self downgrade_fetchTrackIDWithCompletion:^(long long trackId, NSError *error) {
                                    if (error || trackId == 0) {
                                        [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                        [weakActionsBar setDetail:@"获取失败" forItemAtIndex:itemIndex];
                                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                            [weakActionsBar setDetail:@"版本回退" forItemAtIndex:itemIndex];
                                        });
                                        [self showDowngradeMessage:error ? error.localizedDescription : @"未知错误" title:@"获取失败"];
                                        return;
                                    }

                                    [weakActionsBar setDetail:@"获取版本..." forItemAtIndex:itemIndex];
                                    [self downgrade_fetchVersionsForTrackID:trackId completion:^(NSArray *versions, NSError *err) {
                                        [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                        [weakActionsBar setDetail:@"版本回退" forItemAtIndex:itemIndex];

                                        if (err) {
                                            [self showDowngradeMessage:err.localizedDescription title:@"获取失败"];
                                            return;
                                        }
                                        [self downgrade_presentVersionSelection:versions trackID:trackId];
                                    }];
                                }];
                            }];
                        }]];

                        [actionSheet addAction:[UIAlertAction actionWithTitle:@"自定义版本号" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                            UIAlertController *inputAlert = [UIAlertController alertControllerWithTitle:@"自定义版本号"
                                                                                               message:@"请输入要降级的版本号"
                                                                                        preferredStyle:UIAlertControllerStyleAlert];
                            [inputAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                                textField.placeholder = @"请输入版本号";
                                textField.keyboardType = UIKeyboardTypeNumberPad;
                            }];

                            [inputAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                            [inputAlert addAction:[UIAlertAction actionWithTitle:@"降级" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                                NSString *vidStr = inputAlert.textFields.firstObject.text;
                                long long versionId = [vidStr longLongValue];
                                if (versionId <= 0) {
                                    [self showDowngradeMessage:@"请输入正确的版本号" title:@"输入错误"];
                                    return;
                                }

                                [self downgrade_verifyOwnershipWithCompletion:^(BOOL accountReady) {
                                    if (!accountReady) return;
                                    [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                                    [weakActionsBar setDetail:@"查询信息..." forItemAtIndex:itemIndex];
                                    [self downgrade_fetchTrackIDWithCompletion:^(long long trackId, NSError *error) {
                                        if (error || trackId == 0) {
                                            [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                            [weakActionsBar setDetail:@"获取失败" forItemAtIndex:itemIndex];
                                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                                [weakActionsBar setDetail:@"版本回退" forItemAtIndex:itemIndex];
                                            });
                                            [self showDowngradeMessage:error ? error.localizedDescription : @"未知错误" title:@"获取失败"];
                                            return;
                                        }

                                        [weakActionsBar setDetail:@"验证版本..." forItemAtIndex:itemIndex];
                                        [self downgrade_fetchVersionsForTrackID:trackId completion:^(NSArray *versions, NSError *err) {
                                            if (err || ![versions isKindOfClass:[NSArray class]]) {
                                                [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                                [weakActionsBar setDetail:@"获取失败" forItemAtIndex:itemIndex];
                                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                                    [weakActionsBar setDetail:@"版本回退" forItemAtIndex:itemIndex];
                                                });
                                                [self showDowngradeMessage:err ? err.localizedDescription : @"获取历史版本失败" title:@"验证失败"];
                                                return;
                                            }

                                            BOOL found = NO;
                                            for (NSDictionary *ver in versions) {
                                                long long extId = [ver[@"versionId"] longLongValue];
                                                if (extId == versionId) {
                                                    found = YES;
                                                    break;
                                                }
                                            }

                                            if (!found) {
                                                [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                                [weakActionsBar setDetail:@"无效版本" forItemAtIndex:itemIndex];
                                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                                    [weakActionsBar setDetail:@"版本回退" forItemAtIndex:itemIndex];
                                                });
                                                [self showDowngradeMessage:@"输入的版本号不存在" title:@"无效版本号"];
                                                return;
                                            }

                                            [weakActionsBar setDetail:@"触发下载..." forItemAtIndex:itemIndex];
                                            [self downgrade_installWithTrackID:trackId versionID:versionId];
                                            [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                                            [self.dataViewController dismissImmediately];
                                        }];
                                    }];
                                }];
                            }]];

                            if (IS_IPAD) {
                                self.dataViewController.dockDismissed = [ADDataViewController dismissFloatingDockIfNeededWithCompletion:^{
                                    [self.dataViewController presentViewController:inputAlert animated:YES completion:nil];
                                }];
                            } else {
                                [self.dataViewController presentViewController:inputAlert animated:YES completion:nil];
                            }
                        }]];

                        [actionSheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

                        [self.dataViewController presentViewController:actionSheet animated:YES completion:nil];
                    }
                }];

                // 5. Uninstall App
                [actionsBar addItemWithTitle:@"卸载应用"
                                      detail:@"彻底卸载"
                                       image:[ADHelper imageNamed:@"OffloadApp"]
                                     handler:^{
                    if (self.appData.isDeletable) {
                        [self showDestructiveConfirmationAlertWithTitle:@"卸载应用" message:@"这将彻底卸载该应用并删除其所有数据。\n此操作不可撤销！"
                                                           confirmTitle:@"卸载" confirmHandler:^{
                            NSInteger itemIndex = 3;
                            [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];

                            [self.appData uninstallAppWithCompletion:^(BOOL success) {
                                [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                if (success) {
                                    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                                    [self.dataViewController dismiss];
                                } else {
                                    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeError];
                                    UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"错误" message:@"卸载应用失败。" preferredStyle:UIAlertControllerStyleAlert];
                                    [errorAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                                    [self.dataViewController presentViewController:errorAlert animated:YES completion:nil];
                                }
                            }];
                        }];
                    }
                }];

                // 将卸载放在降级之前。
                UIView *uninstallItem = [actionsBar.arrangedSubviews objectAtIndex:4];
                [actionsBar insertArrangedSubview:uninstallItem atIndex:3];

                // 6. Redirect / per-app launch control (tap and long press use the same menu).
                UIImage *redirectImage = nil;
                if (@available(iOS 13.0, *)) {
                    redirectImage = [UIImage systemImageNamed:@"arrow.left.arrow.right.circle"];
                }
                if (!redirectImage) redirectImage = [ADHelper imageNamed:@"ResetPermissions"];
                NSInteger launchControlIndex = 5;
                ADActionBarBlock launchControlHandler = ^{
                    [self showLaunchControlMenuWithActionsBar:weakActionsBar itemIndex:launchControlIndex];
                };
                [actionsBar addItemWithTitle:@"跳转控制"
                                      detail:[self launchControlSummary]
                                       image:redirectImage
                                     handler:launchControlHandler
                            longPressHandler:launchControlHandler];

                if (!self.appData.isApplication) {
                    [actionsBar setItemEnabled:NO atIndex:1];
                    [actionsBar setItemEnabled:NO atIndex:2];
                    [actionsBar setItemEnabled:NO atIndex:5];
                }

                if ([self.appData hasAppStoreApp]) {
                    [actionsBar setItemEnabled:YES atIndex:4];
                    [actionsBar setDetail:@"版本回退" forItemAtIndex:4];
                } else {
                    [actionsBar setItemEnabled:NO atIndex:4];
                    [actionsBar setDetail:@"非商店应用" forItemAtIndex:4];
                }

                if (!self.appData.isDeletable) {
                    [actionsBar setItemEnabled:NO atIndex:3];
                }

                if ([ADSettings automaticallyClearsCachesForBundleIdentifier:self.appData.bundleIdentifier]) {
                    [actionsBar setDetail:@"自动清理" forItemAtIndex:0];
                } else {
                    [actionsBar showLoadingIndicatorForItemAtIndex:0];
                    [self.appData getCachesDirectorySizeWithCompletion:^(NSString *formattedSize) {
                        [actionsBar setDetail:formattedSize forItemAtIndex:0];
                        [actionsBar hideLoadingIndicatorForItemAtIndex:0];
                    }];
                }

                [actionsBar showLoadingIndicatorForItemAtIndex:1];
                [self.appData getAppUsageDirectorySizeWithCompletion:^(NSString *formattedSize) {
                    [actionsBar setDetail:formattedSize forItemAtIndex:1];
                    [actionsBar hideLoadingIndicatorForItemAtIndex:1];
                }];
            }
            return cell;
        } else if (indexPath.row == 1) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MoreInfoCellIdentifier"];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"MoreInfoCellIdentifier"];
                cell.backgroundColor = [UIColor clearColor];
            }
            cell.accessoryView = [ADAppearance.sharedInstance tableCellChevronImageView];
            cell.textLabel.text = @"更多信息";
            [ADAppearance applyStylesToCell:cell];
            return cell;
        }
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isManageSection:indexPath.section] && indexPath.row == 0) {
        if ([cell respondsToSelector:@selector(setSeparatorInset:)]) {
            [cell setSeparatorInset:UIEdgeInsetsZero];
        }
        if ([cell respondsToSelector:@selector(setLayoutMargins:)]) {
            [cell setLayoutMargins:UIEdgeInsetsZero];
        }
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self titleForHeaderInSection:section];
    if (title) {
        ADTitleSectionHeaderView *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:ADTitleSectionHeaderView.reuseIdentifier];
        [header configureHeaderWithTitle:[title uppercaseString]];
        return header;
    }
    return nil;
}

- (NSString *)titleForHeaderInSection:(NSInteger)section {
    if ([self isContainersSection:section]) {
        return self.appData.isApplication ? @"沙盒目录" : nil;
    } else if ([self isAppGroupsSection:section]) {
        return !self.appData.appGroups || self.appData.appGroups.count == 0 ? nil : @"应用分组 (App Groups)";
    } else if ([self isManageSection:section]) {
        return @"管理";
    }
    return nil;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isManageSection:indexPath.section]) {
        if (indexPath.row == 0) {
            return 100;
        }
        return 45;
    }
    return 50;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 25;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self isManageSection:indexPath.section]) {
        if (indexPath.row == 1) {
            [self.dataViewController switchTableViews];
        }
    } else if ([self isContainersSection:indexPath.section] || [self isAppGroupsSection:indexPath.section]) {
        [self didSelectContainerOrAppGroupSectionAtIndexPath:indexPath];
    }
}

- (void)didSelectContainerOrAppGroupSectionAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isContainersSection:indexPath.section]) {
        if (indexPath.row == 0) {
            if (self.appData.bundleURL) {
                [ADHelper openDirectoryAtURL:self.appData.bundleURL fromController:self.dataViewController];
            }
        } else if (indexPath.row == 1) {
            if (self.appData.dataContainerURL) {
                [ADHelper openDirectoryAtURL:self.appData.dataContainerURL fromController:self.dataViewController];
            }
        }
    } else if ([self isAppGroupsSection:indexPath.section]) {
        ADAppDataGroup *group = [self.appData.appGroups objectAtIndex:indexPath.row];
        if (group.url) {
            [ADHelper openDirectoryAtURL:group.url fromController:self.dataViewController];
        }
    }
}

#pragma mark - UITableViewDelegate / Copy Action

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    return (action == @selector(copy:));
}

- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    if (action == @selector(copy:)) {
        if ([self isContainersSection:indexPath.section] || [self isAppGroupsSection:indexPath.section]) {
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            if (cell.detailTextLabel.text) [[UIPasteboard generalPasteboard] setString:cell.detailTextLabel.text];
        }
    }
}

#pragma mark - UITableViewDelegate / Context Menu

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point  API_AVAILABLE(ios(13.0)) {
    if ([self isContainersSection:indexPath.section] || [self isAppGroupsSection:indexPath.section]) {
        UIContextMenuConfiguration *configuration = [UIContextMenuConfiguration configurationWithIdentifier:indexPath
                                                                                          previewProvider:nil
                                                                                           actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
            NSMutableArray *actions = [NSMutableArray new];
            [actions addObject:[UIAction actionWithTitle:@"在 Filza 中打开" image:nil identifier:@"open-action" handler:^(__kindof UIAction * _Nonnull action) {
                [self didSelectContainerOrAppGroupSectionAtIndexPath:indexPath];
            }]];

            [actions addObject:[UIAction actionWithTitle:@"复制路径" image:nil identifier:@"copy-action" handler:^(__kindof UIAction * _Nonnull action) {
                UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
                if (cell.detailTextLabel.text) [[UIPasteboard generalPasteboard] setString:cell.detailTextLabel.text];
            }]];

            if ([self isAppGroupsSection:indexPath.section]) {
                [actions addObject:[UIAction actionWithTitle:@"复制标识符" image:nil identifier:@"copy-action" handler:^(__kindof UIAction * _Nonnull action) {
                    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
                    if (cell.textLabel.text) [[UIPasteboard generalPasteboard] setString:cell.textLabel.text];
                }]];
            }

            NSString *title = @"";
            if ([self isContainersSection:indexPath.section]) {
                if (indexPath.row == 0) title = @"应用目录";
                else if (indexPath.row == 1) title = @"数据目录";
            } else if ([self isAppGroupsSection:indexPath.section]) {
                title = @"应用分组";
            }

            return [UIMenu menuWithTitle:title children:actions];
        }];
        return configuration;
    }
    return nil;
}

- (UITargetedPreview *)tableView:(UITableView *)tableView previewForHighlightingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration API_AVAILABLE(ios(13.0)) {
    NSIndexPath *indexPath = (NSIndexPath *)[configuration identifier];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    UIPreviewParameters *parameters = [UIPreviewParameters new];
    parameters.backgroundColor = [UIColor clearColor];
    if ([self isAppGroupsSection:indexPath.section]) {
        return [[UITargetedPreview alloc] initWithView:cell parameters:parameters];
    } else {
        return [[UITargetedPreview alloc] initWithView:cell.detailTextLabel parameters:parameters];
    }
}

- (nullable UITargetedPreview *)tableView:(UITableView *)tableView previewForDismissingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration API_AVAILABLE(ios(13.0)) {
    return [self tableView:tableView previewForHighlightingContextMenuWithConfiguration:configuration];
}

#pragma mark - Helpers

- (void)showDestructiveConfirmationAlertWithTitle:(NSString *)title message:(NSString *)message confirmTitle:(NSString *)confirmTitle confirmHandler:(void(^)())confirmHandler {
    return [self showConfirmationAlertWithTitle:title message:message confirmTitle:confirmTitle confirmStyle:UIAlertActionStyleDestructive confirmHandler:confirmHandler];
}

- (void)showConfirmationAlertWithTitle:(NSString *)title message:(NSString *)message confirmTitle:(NSString *)confirmTitle confirmStyle:(UIAlertActionStyle)style confirmHandler:(void(^)())confirmHandler {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:confirmTitle style:style handler:^(UIAlertAction * _Nonnull action) {
        if (confirmHandler) confirmHandler();
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self.dataViewController presentViewController:alertController animated:YES completion:nil];
}

@end
