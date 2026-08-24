from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = (ROOT / "AppData" / "Classes" / "Controller" / "ADDataViewController.m").read_text(encoding="utf-8")
TWEAK = (ROOT / "AppData" / "AppData.xm").read_text(encoding="utf-8")
HEADERS = (ROOT / "AppData" / "Headers.h").read_text(encoding="utf-8")


class IconActivationContractTests(unittest.TestCase):
    def test_panel_icon_no_longer_launches_application(self):
        combined = CONTROLLER + HEADERS
        self.assertNotIn("didTapOpenApplicationIcon", combined)
        self.assertNotIn("openApplicationWithBundleID", combined)

    def test_bundle_identifier_has_application_fallback(self):
        self.assertIn("ADBundleIdentifierForSpringBoardIcon", TWEAK)
        self.assertIn("[icon application]", TWEAK)
        self.assertIn("ADBundleIdentifierForIcon", CONTROLLER)

    def test_nested_icon_image_and_system_image_fallback_exist(self):
        self.assertIn("ADFindIconImageView", CONTROLLER)
        self.assertIn("_applicationIconImageForBundleIdentifier", CONTROLLER)

    def test_non_app_icon_filters_remain(self):
        self.assertIn("SBFolderIcon", TWEAK)
        self.assertIn("SBWidgetIcon", TWEAK)

    def test_modern_swipe_is_attached_to_stable_icon_touch_view(self):
        self.assertIn("adAppDataSwipeGestureRecognizer", TWEAK)
        self.assertIn("presentControllerFromSBIconView:self fromContextMenu:NO", TWEAK)
        self.assertIn("- (void)didMoveToWindow", TWEAK)
        self.assertIn("- (void)didMoveToSuperview", TWEAK)
        self.assertIn("- (void)layoutSubviews", TWEAK)
        self.assertIn("if (@available(iOS 13.0, *))", TWEAK)

    def test_icon_reuse_rechecks_after_window_attachment(self):
        self.assertIn("dispatch_async(dispatch_get_main_queue()", TWEAK)
        self.assertGreaterEqual(TWEAK.count("ad_updateAppDataSwipeGestureAvailability"), 6)

    def test_folder_icons_do_not_mutate_temporary_scroll_containers(self):
        self.assertNotIn("desktopScrollView", CONTROLLER)
        self.assertNotIn("scrollView.panGestureRecognizer.enabled = NO", CONTROLLER)
        self.assertNotIn("scrollView.scrollEnabled = NO", CONTROLLER)

    def test_folder_close_disables_instead_of_detaching_touch_recognizer(self):
        start = TWEAK.index("%new\n- (void)ad_updateAppDataSwipeGestureAvailability")
        end = TWEAK.index("- (void)ad_appDataSwipePreferenceChanged", start)
        body = TWEAK[start:end]
        self.assertIn("adAppDataSwipeGestureRecognizer.enabled = shouldInstall", body)
        self.assertNotIn("removeGestureRecognizer", body)
        self.assertIn("removeObserver:self", TWEAK)


if __name__ == "__main__":
    unittest.main()
