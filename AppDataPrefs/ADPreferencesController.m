//
//  ADPreferencesController.m
//  AppDataPrefs
//

#import "ADPreferencesController.h"
#import "ADSettings.h"

#import "ADSwitchTableViewCell.h"
#import "ADHeaderTableViewCell.h"
#import "ADSelectListTableViewController.h"

@interface ADPreferencesInfoViewController : UITableViewController
@end

@interface ADPreferencesController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation ADPreferencesController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 实现四个角圆圆的卡片风格
    UITableViewStyle style = UITableViewStyleGrouped;
    if (@available(iOS 13.0, *)) {
        style = UITableViewStyleInsetGrouped; // iOS 13+ 的圆角分组样式
    }
    
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:style];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor].active =  YES;
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active =  YES;
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active =  YES;
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active =  YES;
    
    [self.tableView registerClass:[ADHeaderTableViewCell class] forCellReuseIdentifier:ADHeaderTableViewCell.reuseIdentifier];
    [self.tableView registerClass:[ADSwitchTableViewCell class] forCellReuseIdentifier:ADSwitchTableViewCell.reuseIdentifier];
    
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1;
        case 1: return 2;
        case 2: return 1;
        case 3: return 1;
        case 4: return 3; // 修改点：将开发者区块的行数改为 3
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        ADHeaderTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ADHeaderTableViewCell.reuseIdentifier];
        cell.titleLabel.text = @"AppData";
        cell.detailLabel.text = @"在主屏幕查看与管理应用数据";
        return cell;
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            ADSwitchTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ADSwitchTableViewCell.reuseIdentifier];
            [cell configureWithTitle:@"向上滑动图标" switchKey:kSwipeUpEnabled];
            return cell;
        } else if (indexPath.row == 1) {
            ADSwitchTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ADSwitchTableViewCell.reuseIdentifier];
            [cell configureWithTitle:@"三维触控菜单" switchKey:kForceTouchMenuEnabled];
            return cell;
        }
    } else if (indexPath.section == 2) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AppearanceCellIdentifier"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"AppearanceCellIdentifier"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.textLabel.text = @"面板外观";
        }
        cell.detailTextLabel.text = [ADSettings titleForAppearanceStyle:[ADSettings integerForKey:kAppearance]];
        return cell;
    } else if (indexPath.section == 3) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"InfoCellIdentifier"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"InfoCellIdentifier"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.textLabel.text = @"使用说明";
        }
        return cell;
    } else if (indexPath.section == 4) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DeveloperCellIdentifier"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"DeveloperCellIdentifier"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Fouad Raheb";
            cell.detailTextLabel.text = @"社交主页";
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"源代码";
            cell.detailTextLabel.text = @"GitHub 源代码";
        } else if (indexPath.row == 2) { // 修改点：新增二改开发显示栏
            cell.textLabel.text = @"二改开发";
            cell.detailTextLabel.text = @"iosdump";
        }
        return cell;
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 1: return @"激活方式";
        case 2: return nil;
        case 4: return @"开发者";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case 1: return @"可以通过向上滑动应用图标，或者点击重按图标弹出的菜单中的按钮来激活 AppData 面板。";
        default: return nil;
    }
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 1: return ADSwitchTableViewCell.height;
        default: return UITableViewAutomaticDimension;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        
        UITableViewStyle style = UITableViewStyleGrouped;
        if (@available(iOS 13.0, *)) {
            style = UITableViewStyleInsetGrouped;
        }
        
        ADSelectListTableViewController *listController = [[ADSelectListTableViewController alloc] initWithStyle:style
                                                                                                       title:@"面板外观"
                                                                                                       items:[ADSettings appearanceTitles]
                                                                                                      values:[ADSettings appearanceValues]
                                                                                                currentValue:[NSString stringWithFormat:@"%td",[ADSettings appearanceStyle]]
                                                                                             popViewOnSelect:YES
                                                                                                 changeBlock:^(NSString *value) {
            [ADSettings setInteger:[value integerValue] forKey:kAppearance];
            cell.detailTextLabel.text = [ADSettings titleForAppearanceStyle:[value integerValue]];
        }];
        [self.navigationController pushViewController:listController animated:YES];
    } else if (indexPath.section == 3) {
        [self.navigationController pushViewController:[ADPreferencesInfoViewController new] animated:YES];
    } else if (indexPath.section == 4) {
        if (indexPath.item == 0) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://twitter.com/FouadRaheb"] options:@{} completionHandler:nil];
        } else if (indexPath.item == 1) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/FouadRaheb/AppData"] options:@{} completionHandler:nil];
        } else if (indexPath.item == 2) { // 修改点：新增二改开发的跳转链接
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://t.me/iosdumpzzz"] options:@{} completionHandler:nil];
        }
    }
}

@end

@implementation ADPreferencesInfoViewController

- (instancetype)initWithStyle:(UITableViewStyle)style {
    UITableViewStyle insetStyle = UITableViewStyleGrouped;
    if (@available(iOS 13.0, *)) {
        insetStyle = UITableViewStyleInsetGrouped; // 圆角
    }
    if (self = [super initWithStyle:insetStyle]) {
        self.title = @"使用说明";
    }
    return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"- 点击包名(Bundle ID)即可复制\n"
           @"- 打开文件夹目录需要安装 Filza 插件或应用\n"
           @"- 清理缓存将删除应用沙盒下的 Caches 和 Tmp 文件夹\n"
           @"- 清理应用数据将删除 Library、Documents 和 Tmp 文件夹，并重置应用权限";
}

@end
