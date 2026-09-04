import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
DATA_SOURCE = (ROOT / "AppData/Classes/Controller/DataSource/ADMainDataSource.m").read_text(encoding="utf-8")
ACTIONS_BAR = (ROOT / "AppData/Classes/Controller/Cells/ADActionsBarView.m").read_text(encoding="utf-8")


class DowngradeInteractionContractTests(unittest.TestCase):
    def test_downgrade_eligibility_is_cached_before_tap(self):
        cache = DATA_SOURCE.index("BOOL downgradeAvailable =")
        handler = DATA_SOURCE.index('[actionsBar addItemWithTitle:@"降级应用"')
        menu = DATA_SOURCE.index('alertControllerWithTitle:@"应用降级"', handler)
        self.assertLess(cache, handler)
        tap_path = DATA_SOURCE[handler:menu]
        self.assertIn("if (downgradeAvailable)", tap_path)
        self.assertNotIn("hasAppStoreApp", tap_path)

    def test_action_runs_before_lazy_haptic_feedback(self):
        method = ACTIONS_BAR.index("- (void)buttonTouchUpInside:")
        end = ACTIONS_BAR.index("- (void)buttonTouchDown:", method)
        body = ACTIONS_BAR[method:end]
        self.assertLess(body.index("button.actionBlock();"), body.index("UISelectionFeedbackGenerator"))
        self.assertIn("dispatch_async(dispatch_get_main_queue()", body)

    def test_server_choice_renders_loading_before_account_inspection(self):
        choice = DATA_SOURCE.index('actionWithTitle:@"从服务器获取"')
        custom = DATA_SOURCE.index('actionWithTitle:@"自定义版本号"', choice)
        body = DATA_SOURCE[choice:custom]
        loading = body.index('setDetail:@"获取版本..."')
        account_check = body.index("downgrade_verifyOwnershipWithCompletion")
        self.assertLess(loading, account_check)
        self.assertIn("dispatch_async(dispatch_get_main_queue()", body[loading:account_check])
        self.assertIn("if (!accountReady)", body)
        self.assertIn('setDetail:@"版本回退"', body)

    def test_app_specific_metadata_is_parsed_off_main_thread(self):
        method = DATA_SOURCE.index("- (void)downgrade_verifyOwnershipWithCompletion:")
        end = DATA_SOURCE.index("- (NSArray<NSDictionary *> *)downgrade_candidateRecordsFromJSON:", method)
        body = DATA_SOURCE[method:end]
        background = body.index("dispatch_get_global_queue(QOS_CLASS_USER_INITIATED")
        metadata = body.index("downgrade_purchaserAccountName", background)
        main = body.index("dispatch_get_main_queue()", metadata)
        self.assertLess(background, metadata)
        self.assertLess(metadata, main)

    def test_version_picker_uses_reusable_cells_instead_of_alert_actions(self):
        method = DATA_SOURCE.index("- (void)downgrade_presentVersionSelection:")
        end = DATA_SOURCE.index("#pragma mark - UITableViewDataSource", method)
        body = DATA_SOURCE[method:end]
        self.assertIn("ADVersionSelectionViewController", body)
        self.assertNotIn("UIAlertAction", body)
        self.assertIn("dequeueReusableCellWithIdentifier", DATA_SOURCE)
        self.assertNotIn("indexOfObjectPassingTest", DATA_SOURCE)
        self.assertIn("indicesByKey[key]", DATA_SOURCE)


if __name__ == "__main__":
    unittest.main()
