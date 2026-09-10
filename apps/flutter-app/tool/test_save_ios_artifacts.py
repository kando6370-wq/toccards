import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from save_ios_artifacts import prune_versions, save_artifacts


class ArtifactRetentionTest(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.base = Path(self.workspace.name)
        self.root = self.base / "Downloads" / "CardAI-Packages"
        self.root.mkdir(parents=True)
        self.test_root = self.root / "com.kando.kandoApp.beta"
        self.production_root = self.root / "com.cardai.tcg"
        self.test_root.mkdir()
        self.production_root.mkdir()
        self.trash = self.base / "Trash"
        self.ipa = self.base / "Card AI Test.ipa"
        with zipfile.ZipFile(self.ipa, "w") as archive:
            archive.writestr("Payload/Runner.app/Runner", b"app binary")
        self.dsyms = self.base / "dSYMs"
        binary = self.dsyms / "Runner.app.dSYM/Contents/Resources/DWARF/Runner"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"matching symbols")

    def version(self, label, build, timestamp):
        root = self.test_root if label == "Test" else self.production_root
        path = root / f"CardAI-{label}-1.0.2-{build}"
        path.mkdir()
        (path / "Card AI.ipa").write_bytes(b"existing IPA")
        (path / "dSYMs.zip").write_bytes(b"existing symbols")
        os.utime(path, (timestamp, timestamp))
        return path

    def save(self, build):
        return save_artifacts(
            self.root, self.trash, "test", "com.kando.kandoApp.beta",
            "1.0.2", build, self.ipa, self.dsyms,
        )

    def test_new_test_package_evicts_only_oldest_test_and_preserves_both_files(self):
        # A higher build number saved earlier is still the oldest saved version.
        oldest = self.version("Test", 999, 1)
        for index in range(1, 3):
            self.version("Test", index, index + 1)
        production = [self.version("Prod", index, index) for index in range(7)]
        saved = self.save(134)
        self.assertEqual((saved / self.ipa.name).read_bytes(), self.ipa.read_bytes())
        with zipfile.ZipFile(saved / "dSYMs.zip") as archive:
            self.assertEqual(archive.testzip(), None)
            self.assertEqual(
                archive.read("dSYMs/Runner.app.dSYM/Contents/Resources/DWARF/Runner"),
                b"matching symbols",
            )
        self.assertEqual(saved.parent, self.test_root)
        self.assertEqual(len(list(self.test_root.glob("CardAI-Test-*"))), 3)
        self.assertTrue(all(path.exists() for path in production))
        self.assertFalse(oldest.exists())
        recovered = list(self.trash.iterdir())
        self.assertEqual(len(recovered), 1)
        self.assertEqual((recovered[0] / "Card AI.ipa").read_bytes(), b"existing IPA")
        self.assertEqual((recovered[0] / "dSYMs.zip").read_bytes(), b"existing symbols")

    def test_each_package_keeps_its_limit_and_unrelated_paths_are_untouched(self):
        for label in ("Test", "Prod"):
            for index in range(8):
                self.version(label, index, index)
        unrelated = self.test_root / "notes"
        unrelated.mkdir()
        link = self.test_root / "CardAI-Test-1.0.2-9999"
        link.symlink_to(self.base, target_is_directory=True)
        prune_versions(self.test_root, self.trash, "Test", 3)
        prune_versions(self.production_root, self.trash, "Prod", 7)
        for label in ("Test", "Prod"):
            root = self.test_root if label == "Test" else self.production_root
            cutoff = 5 if label == "Test" else 1
            for index in range(8):
                self.assertEqual((root / f"CardAI-{label}-1.0.2-{index}").exists(), index >= cutoff)
        self.assertEqual(len(list(self.trash.iterdir())), 6)
        self.assertTrue(unrelated.is_dir())
        self.assertTrue(link.is_symlink())

    def test_failed_symbol_packaging_does_not_publish_or_prune(self):
        old = [self.version("Test", index, index) for index in range(3)]
        with patch("save_ios_artifacts.subprocess.run", side_effect=subprocess.CalledProcessError(1, "ditto")):
            with self.assertRaises(subprocess.CalledProcessError):
                self.save(134)
        self.assertEqual(set(self.test_root.iterdir()), set(old))
        self.assertFalse(self.trash.exists())

    def test_new_production_package_evicts_only_oldest_production(self):
        oldest = self.version("Prod", 0, 1)
        for index in range(1, 7):
            self.version("Prod", index, index + 1)
        test_versions = [self.version("Test", index, index) for index in range(3)]
        saved = save_artifacts(
            self.root, self.trash, "production", "com.cardai.tcg",
            "1.0.2", 134, self.ipa, self.dsyms,
        )
        self.assertEqual(saved.parent, self.production_root)
        self.assertEqual(len(list(self.production_root.iterdir())), 7)
        self.assertFalse(oldest.exists())
        self.assertTrue(all(path.exists() for path in test_versions))

    def test_existing_version_is_never_overwritten(self):
        existing = self.version("Test", 134, 1)
        with self.assertRaises(FileExistsError):
            self.save(134)
        self.assertEqual((existing / "Card AI.ipa").read_bytes(), b"existing IPA")
        self.assertFalse(self.trash.exists())


if __name__ == "__main__":
    unittest.main()
