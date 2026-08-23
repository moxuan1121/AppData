from pathlib import Path
import unittest


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "AppData"
    / "Classes"
    / "Controller"
    / "DataSource"
    / "ADMainDataSource.m"
).read_text(encoding="utf-8")


class DaemonDowngradeContractTests(unittest.TestCase):
    def test_appstoredaemon_is_primary_and_storekitui_is_fallback(self):
        primary = SOURCE.index("- (void)downgrade_installWithTrackID:")
        daemon = SOURCE.index("AppStoreDaemon.framework/AppStoreDaemon", primary)
        fallback_call = SOURCE.index("_fallback_downgrade_installWithTrackID", daemon)
        self.assertLess(daemon, fallback_call)

    def test_redownload_purchase_contains_external_version(self):
        for required in (
            "ASDPurchase",
            "ASDPurchaseManager",
            "setBuyParameters:",
            "setIsRedownload:",
            "appExtVrsId=%@",
            "installed=0",
        ):
            self.assertIn(required, SOURCE)

    def test_private_framework_calls_are_runtime_guarded(self):
        self.assertIn("dlopen(\"/System/Library/PrivateFrameworks/AppStoreDaemon.framework/AppStoreDaemon\"", SOURCE)
        self.assertIn("respondsToSelector:startSelector", SOURCE)
        self.assertIn("@catch (NSException *exception)", SOURCE)

    def test_account_switch_reuses_saved_credentials_without_storing_password(self):
        self.assertIn("downgrade_requireActiveStoreAccount", SOURCE)
        self.assertIn("当前未登录 App Store 账号", SOURCE)
        saved_switch = SOURCE.index("saveAccount:targetAccount verifyCredentials:NO")
        switch_marker = SOURCE.index("com.storeswitcher.active.txt", saved_switch)
        resume = SOURCE.index("if (completion) completion(YES);", switch_marker)
        self.assertLess(saved_switch, switch_marker)
        self.assertLess(switch_marker, resume)
        self.assertNotIn("saveAccount:targetAccount verifyCredentials:YES", SOURCE)
        self.assertIn("saveAccount:previousAccount verifyCredentials:NO", SOURCE)
        self.assertIn("com.storeswitcher.active.txt", SOURCE)
        self.assertIn("com.storeswitcher.accounts_changed", SOURCE)
        self.assertNotIn("setPassword", SOURCE)
        self.assertNotIn("passwordTextField", SOURCE)

    def test_daemon_reply_survives_panel_dismissal(self):
        self.assertIn("ADMainDataSource *strongDataSource = self", SOURCE)
        self.assertIn("[strongDataSource _fallback_downgrade_installWithTrackID", SOURCE)

    def test_success_closes_panel_without_started_alert(self):
        self.assertNotIn("已发起降级", SOURCE)
        self.assertNotIn("降级任务已提交", SOURCE)
        self.assertGreaterEqual(SOURCE.count("dismissImmediately"), 2)


if __name__ == "__main__":
    unittest.main()
