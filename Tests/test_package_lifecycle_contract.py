from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "AppData" / "Package"
CONTROL = (PACKAGE / "DEBIAN" / "control").read_text(encoding="utf-8")
POSTINST = (PACKAGE / "DEBIAN" / "postinst").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "build.yml").read_text(encoding="utf-8")


class PackageLifecycleContractTests(unittest.TestCase):
    def test_package_uses_native_tweakinject_layout(self):
        self.assertTrue((PACKAGE / "usr" / "lib" / "TweakInject" / "AppData.plist").is_file())
        self.assertFalse((PACKAGE / "Library" / "MobileSubstrate").exists())
        self.assertIn("Package_RootHide/usr/lib/TweakInject/", WORKFLOW)
        self.assertNotIn("Package_RootHide/Library/MobileSubstrate", WORKFLOW)

    def test_uninstall_has_no_maintainer_scripts(self):
        self.assertFalse((PACKAGE / "DEBIAN" / "prerm").exists())
        self.assertFalse((PACKAGE / "DEBIAN" / "postrm").exists())
        self.assertIn('test ! -e "$verify_dir/prerm"', WORKFLOW)
        self.assertIn('test ! -e "$verify_dir/postrm"', WORKFLOW)

    def test_upgrade_recovery_never_overwrites_ellekit_paths(self):
        self.assertIn('[ "$1" = "configure" ]', POSTINST)
        self.assertIn("[ -d /usr/lib/TweakInject ]", POSTINST)
        self.assertIn("[ ! -e /Library/MobileSubstrate/DynamicLibraries ]", POSTINST)
        self.assertIn("[ ! -L /Library/MobileSubstrate/DynamicLibraries ]", POSTINST)
        self.assertIn("ln -s /usr/lib/TweakInject /Library/MobileSubstrate/DynamicLibraries", POSTINST)
        self.assertNotIn("/var/jb", POSTINST)
        self.assertNotIn("ln -sf", POSTINST)
        self.assertNotIn("rm ", POSTINST)

    def test_roothide_dependency_and_version_are_explicit(self):
        self.assertIn("Version: 1.8.15", CONTROL)
        self.assertIn("roothide", CONTROL)
        self.assertIn("Architecture: iphoneos-arm", CONTROL)

    def test_workflow_rejects_legacy_compatibility_paths(self):
        self.assertIn("Unsafe MobileSubstrate path found in package data", WORKFLOW)
        self.assertIn("./usr/lib/TweakInject/AppData.dylib", WORKFLOW)
        self.assertIn("./usr/lib/TweakInject/AppData.plist", WORKFLOW)
        self.assertIn("Rootless /var/jb payload found in RootHide package", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
