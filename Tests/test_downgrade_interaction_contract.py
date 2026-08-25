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


if __name__ == "__main__":
    unittest.main()
