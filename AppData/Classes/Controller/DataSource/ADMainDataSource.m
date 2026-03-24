//
//  ADMainDataSource.m
//  AppData
//
//  Created by Fouad Raheb on 7/15/20.
//

#import "ADMainDataSource.h"
#import "ADAppData.h"
#import "ADDataViewController.h"
#import "ADActionsBarView.h"
#import "ADTitleSectionHeaderView.h"
#import <dlfcn.h> // 需要引入 dlfcn.h 供动态加载私有库

// --- 新增：声明私有类接口，避免 performSelector 返回 BOOL 时产生的 0x1 野指针崩溃 ---
@interface SSAccount : NSObject
- (BOOL)isActive;
- (BOOL)isLocalAccount;
- (NSString *)accountName;
@end

@interface SSAccountStore : NSObject
+ (id)defaultStore;
- (NSArray *)accounts;
@end
// -------------------------------------------------------------------------

@implementation ADMainDataSource

- (instancetype)initWithAppData:(ADAppData *)data dataViewController:(ADDataViewController *)dataViewController {
    if (self = [super init]) {
        self.appData = data;
        self.dataViewController = dataViewController;
    }
    return self;
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
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"应用角标" message:@"修改或清除当前应用的角标数量" preferredStyle:UIAlertControllerStyleAlert];
                    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                        textField.text = [NSString stringWithFormat:@"%td",self.appData.appBadgeCount];
                        textField.placeholder = @"角标数量";
                        textField.textAlignment = NSTextAlignmentCenter;
                        textField.enabled = NO;
                    }];
                    [alertController addAction:[UIAlertAction actionWithTitle:@"修改" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        NSInteger count = [alertController.textFields.firstObject.text integerValue];
                        [self.appData setAppBadgeCount:count];
                        [weakActionsBar setDetail:@"已修改!" forItemAtIndex:0];
                        DISPATCH_AFTER(0.5, { [weakActionsBar setDetail:[NSString stringWithFormat:@"%td",count] forItemAtIndex:0]; });
                    }]];
                    [alertController addAction:[UIAlertAction actionWithTitle:@"清除" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        [self.appData setAppBadgeCount:0];
                        [weakActionsBar setDetail:@"已清除!" forItemAtIndex:0];
                        DISPATCH_AFTER(0.5, { [weakActionsBar setDetail:@"0" forItemAtIndex:0]; });
                    }]];
                    [alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                    
                    [self.dataViewController presentViewController:alertController animated:YES completion:^{
                        alertController.textFields.firstObject.enabled = true;
                    }];
                }];
                
                // 2. Clear Caches
                [actionsBar addItemWithTitle:@"清理缓存" detail:@"计算中..." image:[ADHelper imageNamed:@"ClearCache"] handler:^{
                    NSInteger itemIndex = 1;
                    [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                    [weakActionsBar setDetail:@"清理中..." forItemAtIndex:itemIndex];
                    DISPATCH_AFTER(0.5, {
                        [self.appData clearAppCachesWithCompletion:^{
                            [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                            [weakActionsBar setDetail:@"已清除!" forItemAtIndex:itemIndex];
                            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                            DISPATCH_AFTER(0.5, {
                                [self.appData getCachesDirectorySizeWithCompletion:^(NSString *formattedSize) {
                                    [weakActionsBar setDetail:formattedSize forItemAtIndex:itemIndex];
                                }];
                            });
                        }];
                    });
                }];
                
                // 3. Clear App Data
                [actionsBar addItemWithTitle:@"清理数据" detail:@"计算中..." image:[ADHelper imageNamed:@"ClearData"] handler:^{
                    if (self.appData.isApplication) {
                        [self showDestructiveConfirmationAlertWithTitle:@"清理应用数据" message:@"清理应用数据将只会删除应用沙盒中的“Library”和“Documents”文件夹，不会删除App Groups分组数据。" confirmTitle:@"清理" confirmHandler:^{
                            NSInteger itemIndex = 2;
                            [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                            [weakActionsBar setDetail:@"清理中..." forItemAtIndex:itemIndex];
                            DISPATCH_AFTER(0.5, {
                                [self.appData resetDiskContentWithCompletion:^{
                                    [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                    [weakActionsBar setDetail:@"已清理!" forItemAtIndex:itemIndex];
                                    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                                    DISPATCH_AFTER(0.5, {
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
                [actionsBar addItemWithTitle:@"重置权限" detail:[NSString stringWithFormat:@"%td",[self.appData getPermissions].count] image:[ADHelper imageNamed:@"ResetPermissions"] handler:^{
                    if (self.appData.isApplication) {
                        [self showDestructiveConfirmationAlertWithTitle:@"重置应用权限" message:@"这将清除该应用访问通讯录、照片、相机等的所有权限。\n下次打开该应用时会重新请求这些权限。" confirmTitle:@"重置" confirmHandler:^{
                            NSInteger itemIndex = 3;
                            [self.appData resetAllAppPermissions];
                            [weakActionsBar setDetail:@"已重置!" forItemAtIndex:itemIndex];
                            [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
                            DISPATCH_AFTER(0.5, {
                               [weakActionsBar setDetail:[NSString stringWithFormat:@"%td",[self.appData getPermissions].count] forItemAtIndex:itemIndex];
                            });
                        }];
                    }
                }];
                
                // 5. Downgrade App (原生降级组件 - 带有完整账号校验UI)
                UIImage *downgradeIcon = nil;
                if (@available(iOS 13.0, *)) { downgradeIcon = [UIImage systemImageNamed:@"arrow.down.circle"]; }
                else { downgradeIcon = [ADHelper imageNamed:@"OffloadApp"]; }
                
                [actionsBar addItemWithTitle:@"降级应用" detail:@"版本回退" image:downgradeIcon handler:^{
                    if (self.appData.isApplication) {
                        
                        // === 点击后：详细校验 Apple ID 归属并获取账号信息 ===
                        NSString *bundlePath = self.appData.bundleURL.path;
                        NSString *containerPath = [bundlePath stringByDeletingLastPathComponent];
                        NSString *metadataPath = [containerPath stringByAppendingPathComponent:@"iTunesMetadata.plist"];
                        
                        NSString *purchaserAccountEmail = @"未知账号";
                        if ([[NSFileManager defaultManager] fileExistsAtPath:metadataPath]) {
                            NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
                            NSDictionary *downloadInfo = metadata[@"com.apple.iTunesStore.downloadInfo"];
                            NSDictionary *accountInfo = downloadInfo[@"accountInfo"];
                            if (accountInfo[@"AppleID"]) {
                                purchaserAccountEmail = accountInfo[@"AppleID"];
                            }
                        }
                        
                        // 动态读取 StoreServices 框架获取当前登录账号
                        dlopen("/System/Library/PrivateFrameworks/StoreServices.framework/StoreServices", RTLD_LAZY);
                        Class SSAccountStoreClass = NSClassFromString(@"SSAccountStore");
                        NSString *activeAccountEmail = @"未登录";
                        
                        // === 修复的核心代码：改用声明接口直接调用，避免 EXC_BAD_ACCESS ===
                        if (SSAccountStoreClass) {
                            SSAccountStore *store = [SSAccountStoreClass defaultStore];
                            NSArray *accounts = [store accounts];
                            for (SSAccount *account in accounts) {
                                if ([account isActive] && ![account isLocalAccount]) {
                                    NSString *accName = [account accountName];
                                    if (accName) activeAccountEmail = accName;
                                    break;
                                }
                            }
                        }
                        // ==========================================================
                        
                        // 判断是否匹配（忽略大小写）
                        BOOL isVerified = ([activeAccountEmail caseInsensitiveCompare:purchaserAccountEmail] == NSOrderedSame);
                        
                        if (!isVerified) {
                            // 账号不符：完美还原图片的排版
                            NSString *errorMessage = [NSString stringWithFormat:@"账号不匹配。\n\n此应用由账号\n%@ 下载。\n\n当前登录的账号是\n%@。\n\n请切换到正确的 App Store 账号后再试。", purchaserAccountEmail, activeAccountEmail];
                            
                            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"无法降级" message:errorMessage preferredStyle:UIAlertControllerStyleAlert];
                            [alertController addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                            [self.dataViewController presentViewController:alertController animated:YES completion:nil];
                            
                            return; // 结束执行，不再弹出选择降级方式
                        }
                        // ==========================================
                        
                        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"降级应用" message:@"请选择降级的获取方式" preferredStyle:UIAlertControllerStyleAlert];
                        
                        // 原生：服务器获取
                        [alertController addAction:[UIAlertAction actionWithTitle:@"服务器获取" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                            NSInteger itemIndex = 4;
                            [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                            [weakActionsBar setDetail:@"获取中..." forItemAtIndex:itemIndex];
                            
                            [self.appData fetchDowngradeTrackIDWithCompletion:^(long long trackId, NSError *error) {
                                if (error) {
                                    [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                    [weakActionsBar setDetail:@"获取失败" forItemAtIndex:itemIndex];
                                    [self showConfirmationAlertWithTitle:@"错误" message:error.localizedDescription confirmTitle:@"确定" confirmStyle:UIAlertActionStyleCancel confirmHandler:nil];
                                    return;
                                }
                                
                                [self.appData fetchDowngradeVersionsForTrackID:trackId completion:^(NSArray *versions, NSError *error) {
                                    [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                    [weakActionsBar setDetail:@"版本回退" forItemAtIndex:itemIndex];
                                    
                                    if (error) {
                                        [self showConfirmationAlertWithTitle:@"错误" message:error.localizedDescription confirmTitle:@"确定" confirmStyle:UIAlertActionStyleCancel confirmHandler:nil];
                                        return;
                                    }
                                    
                                    UIAlertController *versionAlert = [UIAlertController alertControllerWithTitle:@"选择版本" message:@"请选择要降级的版本" preferredStyle:UIAlertControllerStyleActionSheet];
                                    NSArray *sortedVersions = [versions sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"release_date" ascending:NO]]];
                                    for (NSDictionary *ver in sortedVersions) {
                                        NSString *bVer = ver[@"bundle_version"] ?: @"N/A";
                                        NSString *extId = [ver[@"external_identifier"] stringValue] ?: @"";
                                        NSString *title = extId.length > 0 ? [NSString stringWithFormat:@"%@ (%@)", bVer, extId] : bVer;
                                        
                                        [versionAlert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                            [self.appData performDowngradeWithTrackID:trackId versionID:[extId longLongValue] controller:self.dataViewController];
                                        }]];
                                    }
                                    [versionAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                                    
                                    if (versionAlert.popoverPresentationController) {
                                        versionAlert.popoverPresentationController.sourceView = self.dataViewController.view;
                                        versionAlert.popoverPresentationController.sourceRect = CGRectMake(self.dataViewController.view.bounds.size.width/2, self.dataViewController.view.bounds.size.height/2, 1, 1);
                                        versionAlert.popoverPresentationController.permittedArrowDirections = 0;
                                    }
                                    [self.dataViewController presentViewController:versionAlert animated:YES completion:nil];
                                }];
                            }];
                        }]];
                        
                        // 原生：自定义版本号
                        [alertController addAction:[UIAlertAction actionWithTitle:@"自定义版本号" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                            NSInteger itemIndex = 4;
                            [weakActionsBar showLoadingIndicatorForItemAtIndex:itemIndex];
                            [weakActionsBar setDetail:@"加载中..." forItemAtIndex:itemIndex];
                            
                            [self.appData fetchDowngradeTrackIDWithCompletion:^(long long trackId, NSError *error) {
                                [weakActionsBar hideLoadingIndicatorForItemAtIndex:itemIndex];
                                [weakActionsBar setDetail:@"版本回退" forItemAtIndex:itemIndex];
                                if (error) {
                                    [self showConfirmationAlertWithTitle:@"错误" message:error.localizedDescription confirmTitle:@"确定" confirmStyle:UIAlertActionStyleCancel confirmHandler:nil];
                                    return;
                                }
                                
                                UIAlertController *inputAlert = [UIAlertController alertControllerWithTitle:@"输入版本号" message:@"请输入 App Store 目标版本的 external_identifier" preferredStyle:UIAlertControllerStyleAlert];
                                [inputAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                                    textField.placeholder = @"Version ID (例如: 852101000)";
                                    textField.keyboardType = UIKeyboardTypeNumberPad;
                                }];
                                [inputAlert addAction:[UIAlertAction actionWithTitle:@"降级" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                    NSString *vIdStr = inputAlert.textFields.firstObject.text;
                                    long long vId = [vIdStr longLongValue];
                                    if (vId > 0) {
                                        [self.appData performDowngradeWithTrackID:trackId versionID:vId controller:self.dataViewController];
                                    } else {
                                        [self showConfirmationAlertWithTitle:@"错误" message:@"无效的版本号" confirmTitle:@"确定" confirmStyle:UIAlertActionStyleCancel confirmHandler:nil];
                                    }
                                }]];
                                [inputAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                                [self.dataViewController presentViewController:inputAlert animated:YES completion:nil];
                            }];
                        }]];
                        
                        [alertController addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                        [self.dataViewController presentViewController:alertController animated:YES completion:nil];
                    }
                }];

                // 6. Uninstall App (小字改为"彻底卸载")
                [actionsBar addItemWithTitle:@"卸载应用" detail:@"彻底卸载" image:[ADHelper imageNamed:@"OffloadApp"] handler:^{
                    if (self.appData.isDeletable) {
                        [self showDestructiveConfirmationAlertWithTitle:@"卸载应用" message:@"这将彻底卸载该应用并删除其所有数据。\n此操作不可撤销！" confirmTitle:@"卸载" confirmHandler:^{
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
                
                // ============ 精准控制按钮状态 ============
                if (!self.appData.isApplication) {
                    [actionsBar setItemEnabled:NO atIndex:2]; // 清理数据
                    [actionsBar setItemEnabled:NO atIndex:3]; // 重置权限
                    [actionsBar setItemEnabled:NO atIndex:4]; // 降级应用
                } else {
                    // 只需判断是否为 App Store 应用。为防止触发原作者的方法坑，我们只对需要禁用的做操作。
                    if (![self.appData hasAppStoreApp]) {
                        [actionsBar setItemEnabled:NO atIndex:4];
                        [actionsBar setDetail:@"非商店应用" forItemAtIndex:4];
                    }
                }
                
                if (!self.appData.isDeletable) {
                    [actionsBar setItemEnabled:NO atIndex:5]; // 卸载应用
                }
                // ==========================================
                
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
        if (indexPath.row == 0) return 100;
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
        if (indexPath.row == 0 && self.appData.bundleURL) {
            [ADHelper openDirectoryAtURL:self.appData.bundleURL fromController:self.dataViewController];
        } else if (indexPath.row == 1 && self.appData.dataContainerURL) {
            [ADHelper openDirectoryAtURL:self.appData.dataContainerURL fromController:self.dataViewController];
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
