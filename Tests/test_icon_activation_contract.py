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

    def test_swipe_is_attached_only_to_the_icon_image_layer(self):
        self.assertNotIn("adAppDataSwipeGestureRecognizer", TWEAK)
        self.assertNotIn("presentControllerFromSBIconView:self fromContextMenu:NO", TWEAK)
        self.assertIn("ADApplicationIconViewForImageView(self)", TWEAK)
        self.assertIn("presentControllerFromSBIconView:iconView fromContextMenu:NO", TWEAK)

    def test_icon_image_rechecks_after_window_attachment(self):
        self.assertIn("%hook SBIconImageView", TWEAK)
        self.assertIn("- (void)didMoveToWindow", TWEAK)
        self.assertGreaterEqual(TWEAK.count("ad_updateSwipeGestureAvailability"), 3)

    def test_folder_icons_do_not_mutate_temporary_scroll_containers(self):
        self.assertNotIn("desktopScrollView", CONTROLLER)
        self.assertNotIn("scrollView.panGestureRecognizer.enabled = NO", CONTROLLER)
        self.assertNotIn("scrollView.scrollEnabled = NO", CONTROLLER)

    def test_folder_close_does_not_run_icon_view_lifecycle_hooks(self):
        modern_group = TWEAK[TWEAK.index("%group IOS13_AND_NEWER_HOOKS"):]
        self.assertNotIn("- (void)didMoveToSuperview", modern_group)
        self.assertNotIn("- (void)layoutSubviews", modern_group)
        self.assertNotIn("- (void)dealloc", modern_group)
        self.assertNotIn("dispatch_async(dispatch_get_main_queue()", modern_group)


if __name__ == "__main__":
    unittest.main()
