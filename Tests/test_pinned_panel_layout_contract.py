import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTROLLER = (ROOT / "AppData/Classes/Controller/ADDataViewController.m").read_text(encoding="utf-8")
DATA_SOURCE = (ROOT / "AppData/Classes/Controller/DataSource/ADMainDataSource.m").read_text(encoding="utf-8")


class PinnedPanelLayoutContractTests(unittest.TestCase):
    def test_phone_panel_height_tracks_visible_content_and_stays_bottom_aligned(self):
        self.assertIn("ADDynamicPanelHeightForAppData", CONTROLLER)
        self.assertIn("config.customFrameHandler", CONTROLLER)
        self.assertIn("MIN(desiredPanelHeight, CGRectGetHeight(bounds))", CONTROLLER)
        self.assertIn("CGRectGetMaxY(bounds) - panelHeight", CONTROLLER)
        self.assertNotIn("config.screenPercentage = 50.0;", CONTROLLER)

    def test_main_panel_tables_do_not_scroll(self):
        self.assertIn("self.managementTableView.scrollEnabled = NO;", CONTROLLER)
        self.assertIn("self.tableView.scrollEnabled = NO;", CONTROLLER)
        self.assertIn("self.tableView.bounces = NO;", CONTROLLER)
        layout = CONTROLLER[CONTROLLER.index("- (void)layoutTableViews"):CONTROLLER.index("#pragma mark - Actions")]
        self.assertIn("self.managementTableView.frame", layout)
        self.assertIn("CGRectGetMaxY(self.managementTableView.frame)", layout)
        self.assertNotIn("contentInset", layout)

    def test_directory_table_contains_only_directory_sections(self):
        self.assertIn("tableView == self.dataViewController.managementTableView ? 1 : 2", DATA_SOURCE)
        self.assertIn("tableView == self.dataViewController.managementTableView ? 0 : section + 1", DATA_SOURCE)

    def test_empty_sections_do_not_reserve_invisible_header_or_footer_space(self):
        self.assertIn(".length > 0 ? 25.0 : CGFLOAT_MIN", DATA_SOURCE)
        self.assertIn("return CGFLOAT_MIN;", DATA_SOURCE)


if __name__ == "__main__":
    unittest.main()
