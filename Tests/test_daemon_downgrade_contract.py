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
        primary = SOURCE.index("- (void)_downgrade_installWithTrackID:")
        daemon = SOURCE.index("AppStoreDaemon.framework/AppStoreDaemon", primary)
        fallback_call = SOURCE.index("_fallback_downgrade_installWithTrackID", daemon)
        self.assertLess(daemon, fallback_call)

    def test_redownload_purchase_contains_external_version(self):
        for required in (
            "ASDPurchase",
            "ASDPurchaseManager",
            "setBuyParameters:",
            "setIsRedownload:",
            "setItemID:",
            "setBundleID:",
            "setIsUpdate:",
            "setIsBackgroundUpdate:",
            "setCreatesJobs:",
            "setDisplaysOnLockScreen:",
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
        self.assertIn("[targetAccount setActive:YES]", SOURCE)
        self.assertNotIn("setActive:(account == targetAccount)", SOURCE)
        self.assertIn("com.storeswitcher.active.txt", SOURCE)
        self.assertIn("com.storeswitcher.accounts_changed", SOURCE)
        self.assertNotIn("setPassword", SOURCE)
        self.assertNotIn("passwordTextField", SOURCE)

    def test_daemon_reply_survives_panel_dismissal(self):
        self.assertIn("ADMainDataSource *strongDataSource = self", SOURCE)
        self.assertIn("[strongDataSource downgrade_writeDiagnosticForError", SOURCE)

    def test_daemon_result_object_is_checked_without_password_retry_loop(self):
        self.assertIn('NSSelectorFromString(@"success")', SOURCE)
        self.assertIn('NSSelectorFromString(@"error")', SOURCE)
        self.assertIn("if (purchaseSucceeded) {", SOURCE)
        self.assertNotIn("attempt:1", SOURCE)
        self.assertIn("downgrade_writeDiagnosticForError", SOURCE)
        self.assertIn("com.moxuan.appdata.downgrade-diagnostic.plist", SOURCE)
        for forbidden in ("password", "token", "cookie", "DSID"):
            self.assertNotIn('@"' + forbidden + '"', SOURCE)

    def test_store_switch_is_automatic_and_original_store_is_restored(self):
        self.assertNotIn('alertControllerWithTitle:@"需要切换账号"', SOURCE)
        self.assertNotIn('actionWithTitle:@"切换并继续"', SOURCE)
        self.assertIn("ADDowngradeOriginalStoreAccountKey", SOURCE)
        self.assertIn("downgrade_restoreOriginalStoreAccount", SOURCE)
        self.assertIn("downgrade_beginConservativeStoreRestoreMonitoring", SOURCE)
        self.assertIn("downgrade_installedVersionSignatureForBundleIdentifier", SOURCE)
        self.assertIn("2 * 60 * 60", SOURCE)
        self.assertIn("30 * NSEC_PER_SEC", SOURCE)

    def test_purchase_callbacks_do_not_restore_storefront_early(self):
        fallback_start = SOURCE.index("- (void)_fallback_downgrade_installWithTrackID:")
        primary_start = SOURCE.index("- (void)_downgrade_installWithTrackID:")
        fallback_body = SOURCE[fallback_start:primary_start]
        primary_body = SOURCE[primary_start:SOURCE.index("- (void)downgrade_installWithTrackID:", primary_start)]
        self.assertNotIn("[strongDataSource downgrade_restoreOriginalStoreAccount]", fallback_body)
        self.assertNotIn("[strongDataSource downgrade_restoreOriginalStoreAccount]", primary_body)
        self.assertIn("replacement is committed", fallback_body)

    def test_unknown_purchaser_never_silently_uses_current_account(self):
        ownership = SOURCE.index("- (void)downgrade_verifyOwnershipWithCompletion:")
        history = SOURCE.index("- (NSArray<NSDictionary *> *)downgrade_candidateRecordsFromJSON:", ownership)
        body = SOURCE[ownership:history]
        self.assertNotIn("purchaserName.length == 0 ||", body)
        self.assertIn("downgrade_presentSavedAccountSelectionWithMessage", body)
        self.assertIn("无法从应用元数据自动确认购买账号", body)

    def test_original_account_switch_timing_is_preserved(self):
        self.assertIn("saveAccount:targetAccount verifyCredentials:NO error:nil", SOURCE)
        self.assertIn("0.5 * NSEC_PER_SEC", SOURCE)

    def test_daemon_error_follows_original_storekitui_fallback(self):
        failure = SOURCE.index("AppStoreDaemon purchase failed")
        fallback = SOURCE.index("[strongDataSource _fallback_downgrade_installWithTrackID", failure)
        self.assertLess(failure, fallback)
        self.assertNotIn("downgrade_configureAppStoreDialogObserver", SOURCE)
        self.assertNotIn("setPresentingSceneIdentifier:", SOURCE)
        self.assertNotIn("setShouldCancelForInstalledBundleItems:", SOURCE)

    def test_three_history_id_sources_remain_unchanged(self):
        timbrd = SOURCE.index("https://api.timbrd.com/apple/app-version/index.php?id=%@")
        agzy = SOURCE.index("https://app.agzy.cn/searchVersion?appid=%@")
        bilin = SOURCE.index("https://apis.bilin.eu.org/history/%@")
        self.assertLess(timbrd, agzy)
        self.assertLess(agzy, bilin)

    def test_success_closes_panel_without_started_alert(self):
        self.assertNotIn("已发起降级", SOURCE)
        self.assertNotIn("降级任务已提交", SOURCE)
        self.assertGreaterEqual(SOURCE.count("dismissImmediately"), 2)


if __name__ == "__main__":
    unittest.main()
