import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTROLLER = (ROOT / "AppData/Classes/Controller/ADDataViewController.m").read_text(encoding="utf-8")
DATA_SOURCE = (ROOT / "AppData/Classes/Controller/DataSource/ADMainDataSource.m").read_text(encoding="utf-8")
SETTINGS = (ROOT / "AppData/Classes/Helpers/ADSettings.m").read_text(encoding="utf-8")
PREFERENCES = (ROOT / "AppDataPrefs/ADPreferencesController.m").read_text(encoding="utf-8")


class PinnedPanelLayoutContractTests(unittest.TestCase):
    def test_phone_panel_uses_saved_height_with_fifty_percent_default(self):
        self.assertIn("config.screenPercentage = [ADSettings panelHeightPercentage];", CONTROLLER)
        self.assertIn("kPanelHeightPercentage:     @(50)", SETTINGS)
        self.assertIn("MIN(100, MAX(35, percentage))", SETTINGS)

    def test_management_table_is_fixed_and_directory_table_can_scroll(self):
        self.assertIn("self.managementTableView.scrollEnabled = NO;", CONTROLLER)
        self.assertNotIn("self.tableView.scrollEnabled = NO;", CONTROLLER)
        layout = CONTROLLER[CONTROLLER.index("- (void)layoutTableViews"):CONTROLLER.index("#pragma mark - Actions")]
        self.assertIn("self.managementTableView.frame", layout)
        self.assertIn("CGRectGetMaxY(self.managementTableView.frame)", layout)
        self.assertNotIn("contentInset", layout)

    def test_directory_table_contains_only_directory_sections(self):
        self.assertIn("tableView == self.dataViewController.managementTableView ? 1 : 2", DATA_SOURCE)
        self.assertIn("tableView == self.dataViewController.managementTableView ? 0 : section + 1", DATA_SOURCE)

    def test_settings_exposes_manual_panel_height_slider(self):
        self.assertIn("面板高度", PREFERENCES)
        self.assertIn("minimumValue = 35.0", PREFERENCES)
        self.assertIn("maximumValue = 100.0", PREFERENCES)
        self.assertIn("panelHeightSliderChanged:", PREFERENCES)


if __name__ == "__main__":
    unittest.main()
