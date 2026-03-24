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

#ifndef IS_IPAD
#define IS_IPAD (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#endif

// ================= 新增：降级功能需要的私有 API 声明 =================
@interface SSAccount : NSObject
- (BOOL)isActive;
- (BOOL)isLocalAccount;
- (NSString *)accountName;
@end

@interface SSAccountStore : NSObject
+ (id)defaultStore;
- (NSArray *)accounts;
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
@end
// ===============================================================

@implementation ADMainDataSource

- (instancetype)initWithAppData:(ADAppData *)data dataViewController:(ADDataViewController *)dataViewController {
    if (self = [super init]) {
        self.appData = data;
        self.dataViewController = dataViewController;
    }
    return self;
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

- (void)downgrade_verifyOwnershipWithCompletion:(void(^)(BOOL))completion {
    __block NSString *activeAccountEmail = nil;
    id store = [objc_getClass("SSAccountStore") defaultStore];
    for (id account in [store accounts]) {
        if ([account isActive] && ![account isLocalAccount]) {
            activeAccountEmail = [account accountName];
            break;
        }
    }
    if (!activeAccountEmail) {
        [self showDowngradeMessage:@"未找到登录的 App Store 账号" title:@"验证失败"];
        if (completion) completion(NO);
        return;
    }

    NSString *bundlePath = self.appData.bundleURL.path;
    NSString *containerPath = [bundlePath stringByDeletingLastPathComponent];
    NSString *metadataPath = [containerPath stringByAppendingPathComponent:@"iTunesMetadata.plist"];
    NSString *purchaserAccountEmail = nil;

    if ([[NSFileManager defaultManager] fileExistsAtPath:metadataPath]) {
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
        NSDictionary *downloadInfo = metadata[@"com.apple.iTunesStore.downloadInfo"];
        NSDictionary *accountInfo = downloadInfo[@"accountInfo"];
        purchaserAccountEmail = accountInfo[@"AppleID"];
    }

    if (!purchaserAccountEmail) {
        [self showDowngradeMessage:@"无法读取该应用的购买者账号信息，请确认应用来源于 App Store。" title:@"验证失败"];
        if (completion) completion(NO);
        return;
    }

    if ([activeAccountEmail caseInsensitiveCompare:purchaserAccountEmail] == NSOrderedSame) {
        if (completion) completion(YES);
    } else {
        NSString *msg = [NSString stringWithFormat:@"账号不匹配。\n购买者: %@\n当前登录: %@", purchaserAccountEmail, activeAccountEmail];
        [self showDowngradeMessage:msg title:@"验证失败"];
        if (completion) completion(NO);
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

- (void)downgrade_fetchVersionsForTrackID:(long long)trackId completion:(void(^)(NSArray *versions, NSError *err))completion {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://apis.bilin.eu.org/history/%lld", trackId]];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:[NSURLRequest requestWithURL:url] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) { if(completion) completion(nil, error); return; }
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *versions = json[@"data"];
            if ([versions isKindOfClass:[NSArray class]] && versions.count > 0) {
                if (completion) completion(versions, nil);
            } else {
                if (completion) completion(nil, [NSError errorWithDomain:@"Downgrade" code:404 userInfo:@{NSLocalizedDescriptionKey: @"未找到历史版本记录"}]);
            }
        });
    }];
    [task resume];
}

- (void)downgrade_installWithTrackID:(long long)trackId versionID:(long long)versionId {
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

- (void)downgrade_presentVersionSelection:(NSArray *)versions trackID:(long long)trackId {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择版本" message:@"请选择要降级的版本" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *sortedVersions = [versions sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"release_date" ascending:NO]]];

    for (NSDictionary *ver in sortedVersions) {
        NSString *bVer = ver[@"bundle_version"] ?: @"N/A";
        NSString *extId = [ver[@"external_identifier"] stringValue] ?: @"";
        NSString *title = extId.length > 0 ? [NSString stringWithFormat:@"%@ (%@)", bVer, extId] : bVer;

        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            long long versionId = [ver[@"external_identifier"] longLongValue];
            [self downgrade_installWithTrackID:trackId versionID:versionId];
            [self showDowngradeMessage:@"降级任务已提交，等待验证账户。" title:@"已发起降级"];
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

                // 1. Update Badge
                [actionsBar addItemWithTitle:@"修改角标"
                                      detail:[NSString stringWithFormat:@"%td",[self.appData appBadgeCount]]
                                       image:[ADHelper imageNamed:@"ClearBadge"]
                                     handler:^{
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"应用角标"
                                                                                             message:@"修改或清除当前应用的角标数量"
                                                                                      preferredStyle:UIAlertControllerStyleAlert];
                    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                        textField.text = [NSString stringWithFormat:@"%td",self.appData.appBadgeCount];
                        textField.placeholder = @"角标数量";
                        textField.textAlignment = NSTextAlignmentCenter;
                        textField.enabled = NO;
                    }];
                    [alertController addAction:[UIAlertAction actionWithTitle:@"修改" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        UITextField *field = alertController.textFields.firstObject;
                        NSInteger count = [field.text integerValue];
                        [self.appData setAppBadgeCount:count];
                        [weakActionsBar setDetail:@"已修改!" forItemAtIndex:0];
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                            [weakActionsBar setDetail:[NSString stringWithFormat:@"%td",count] forItemAtIndex:0];
                        });
                        if (self.dataViewController.dockDismissed && IS_IPAD) [ADDataViewController presentFloatingDockIfNeeded];
                    }]];
                    [alertController addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [self.appData setAppBadgeCount:0];
                        [weakActionsBar setDetail:@"已清除!" forItemAtIndex:0];
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                            [weakActionsBar setDetail:@"0" forItemAtIndex:0];
                        });
                        if (self.dataViewController.dockDismissed && IS_IPAD) [ADDataViewController presentFloatingDockIfNeeded];
                    }]];
                    [alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                        if (self.dataViewController.dockDismissed && IS_IPAD) [ADDataViewController presentFloatingDockIfNeeded];
                    }]];

                    if (IS_IPAD) {
                        self.dataViewController.dockDismissed = [ADDataViewController dismissFloatingDockIfNeededWithCompletion:^{
                            [self.dataViewController presentViewController:alertController animated:YES completion:^{
                                alertController.textFields.firstObject.enabled = true;
                            }];
                        }];
                    } else {
                        [self.dataViewController presentViewController:alertController animated:YES completion:^{
                            alertController.textFields.firstObject.enabled = true;
                        }];
                    }
                }];

                // 2. Clear Caches
                [actionsBar addItemWithTitle:@"清理缓存"
                                      detail:@"计算中..."
                                       image:[ADHelper imageNamed:@"ClearCache"]
                                     handler:^{
                    NSInteger itemIndex = 1;
                    [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                    [weakActionsBar setDetail:@"清理中..." forItemAtIndex:itemIndex];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        [self.appData clearAppCachesWithCompletion:^{
                            [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                            [weakActionsBar setDetail:@"已清除!" forItemAtIndex:itemIndex];
                            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                [self.appData getCachesDirectorySizeWithCompletion:^(NSString *formattedSize) {
                                    [weakActionsBar setDetail:formattedSize forItemAtIndex:itemIndex];
                                }];
                            });
                        }];
                    });
                }];

                // 3. Clear App Data
                [actionsBar addItemWithTitle:@"清理数据"
                                      detail:@"计算中..."
                                       image:[ADHelper imageNamed:@"ClearData"]
                                     handler:^{
                    if (self.appData.isApplication) {
                        [self showDestructiveConfirmationAlertWithTitle:@"清理应用数据" message:@"清理应用数据将只会删除应用沙盒中的“Library”和“Documents”文件夹，不会删除App Groups分组数据。" confirmTitle:@"清理" confirmHandler:^{
                            NSInteger itemIndex = 2;
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

                // 4. Reset Permissions
                [actionsBar addItemWithTitle:@"重置权限"
                                      detail:[NSString stringWithFormat:@"%td",[self.appData getPermissions].count]
                                       image:[ADHelper imageNamed:@"ResetPermissions"]
                                     handler:^{
                    if (self.appData.isApplication) {
                        [self showDestructiveConfirmationAlertWithTitle:@"重置应用权限" message:@"这将清除该应用访问通讯录、照片、相机等的所有权限。\n下次打开该应用时会重新请求这些权限。"
                                                           confirmTitle:@"重置" confirmHandler:^{
                            NSInteger itemIndex = 3;
                            [self.appData resetAllAppPermissions];
                            [weakActionsBar setDetail:@"已重置!" forItemAtIndex:itemIndex];
                            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                               [weakActionsBar setDetail:[NSString stringWithFormat:@"%td",[self.appData getPermissions].count] forItemAtIndex:itemIndex];
                            });
                        }];
                    }
                }];

                // 5. Downgrade App
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
                            [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                            [weakActionsBar setDetail:@"验证账号..." forItemAtIndex:itemIndex];

                            [self downgrade_verifyOwnershipWithCompletion:^(BOOL success) {
                                if (!success) {
                                    [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                    [weakActionsBar setDetail:@"版本回退" forItemAtIndex:itemIndex];
                                    return;
                                }

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
                                if (versionId <= 0) return;

                                [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                                [weakActionsBar setDetail:@"验证账号..." forItemAtIndex:itemIndex];

                                [self downgrade_verifyOwnershipWithCompletion:^(BOOL success) {
                                    if (!success) {
                                        [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                        [weakActionsBar setDetail:@"版本回退" forItemAtIndex:itemIndex];
                                        return;
                                    }

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

                                        [weakActionsBar setDetail:@"触发下载..." forItemAtIndex:itemIndex];
                                        [self downgrade_installWithTrackID:trackId versionID:versionId];
                                        [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                        [weakActionsBar setDetail:@"已发起!" forItemAtIndex:itemIndex];
                                        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                            [weakActionsBar setDetail:@"版本回退" forItemAtIndex:itemIndex];
                                        });
                                        [self showDowngradeMessage:@"降级任务已提交至 App Store，等待验证账户。" title:@"已发起降级"];
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

                // 6. Uninstall App
                [actionsBar addItemWithTitle:@"卸载应用"
                                      detail:@"彻底卸载"
                                       image:[ADHelper imageNamed:@"OffloadApp"]
                                     handler:^{
                    if (self.appData.isDeletable) {
                        [self showDestructiveConfirmationAlertWithTitle:@"卸载应用" message:@"这将彻底卸载该应用并删除其所有数据。\n此操作不可撤销！"
                                                           confirmTitle:@"卸载" confirmHandler:^{
                            NSInteger itemIndex = 5;
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

                // 基础启用状态
                if (!self.appData.isApplication) {
                    [actionsBar setItemEnabled:NO atIndex:2];
                    [actionsBar setItemEnabled:NO atIndex:3];
                }

                // --- 核心逻辑：判断是否为 App Store 应用 ---
                if ([self.appData hasAppStoreApp]) {
                    [actionsBar setItemEnabled:YES atIndex:4];
                    [actionsBar setDetail:@"版本回退" forItemAtIndex:4];
                } else {
                    [actionsBar setItemEnabled:NO atIndex:4];
                    [actionsBar setDetail:@"非商店应用" forItemAtIndex:4];
                }

                if (!self.appData.isDeletable) {
                    [actionsBar setItemEnabled:NO atIndex:5];
                }

                // Set Cache Size
                [actionsBar showLoadingIndicatorForItemAtIndex:1];
                [self.appData getCachesDirectorySizeWithCompletion:^(NSString *formattedSize) {
                    [actionsBar setDetail:formattedSize forItemAtIndex:1];
                    [actionsBar hideLoadingIndicatorForItemAtIndex:1];
                }];

                // Set App Data Size
                [actionsBar showLoadingIndicatorForItemAtIndex:2];
                [self.appData getAppUsageDirectorySizeWithCompletion:^(NSString *formattedSize) {
                    [actionsBar setDetail:formattedSize forItemAtIndex:2];
                    [actionsBar hideLoadingIndicatorForItemAtIndex:2];
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
                [actions addObject:[UIAction actionWithTitle:@"复制 Identifier" image:nil identifier:@"copy-action" handler:^(__kindof UIAction * _Nonnull action) {
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
