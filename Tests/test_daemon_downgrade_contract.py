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


if __name__ == "__main__":
    unittest.main()
