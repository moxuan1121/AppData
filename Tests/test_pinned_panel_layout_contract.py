import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTROLLER = (ROOT / "AppData/Classes/Controller/ADDataViewController.m").read_text(encoding="utf-8")
DATA_SOURCE = (ROOT / "AppData/Classes/Controller/DataSource/ADMainDataSource.m").read_text(encoding="utf-8")


class PinnedPanelLayoutContractTests(unittest.TestCase):
    def test_phone_panel_uses_half_screen(self):
        self.assertIn("config.screenPercentage = 50.0;", CONTROLLER)

    def test_management_table_is_fixed_and_not_scrollable(self):
        self.assertIn("self.managementTableView.scrollEnabled = NO;", CONTROLLER)
        layout = CONTROLLER[CONTROLLER.index("- (void)layoutTableViews"):CONTROLLER.index("#pragma mark - Actions")]
        self.assertIn("self.managementTableView.frame", layout)
        self.assertIn("CGRectGetMaxY(self.managementTableView.frame)", layout)
        self.assertNotIn("contentInset", layout)

    def test_directory_table_contains_only_scrollable_sections(self):
        self.assertIn("tableView == self.dataViewController.managementTableView ? 1 : 2", DATA_SOURCE)
        self.assertIn("tableView == self.dataViewController.managementTableView ? 0 : section + 1", DATA_SOURCE)


if __name__ == "__main__":
    unittest.main()
