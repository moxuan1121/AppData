//
//  ADDataViewController.h
//  AppData
//
//  Created by Fouad Raheb on 6/29/20.
//

#import <UIKit/UIKit.h>
#import "ADAppData.h"

@interface ADDataViewController : UIViewController

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITableView *managementTableView;
@property (nonatomic, strong) UITableView *moreTableView;

@property (nonatomic, assign) BOOL dockDismissed;

- (instancetype)initWithAppData:(ADAppData *)data;

+ (void)presentControllerFromSBIconView:(SBIconView *)iconView fromContextMenu:(BOOL)contextMenu;

- (void)switchTableViews;

- (void)dismiss;
- (void)dismissImmediately;

// 修复警告：将参数补全为 void(^)(void) 与 .m 文件保持一致
+ (BOOL)dismissFloatingDockIfNeededWithCompletion:(void(^)(void))completion;
+ (void)presentFloatingDockIfNeeded;

@end
