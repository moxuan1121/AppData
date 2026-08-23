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


if __name__ == "__main__":
    unittest.main()
