import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from save_android_artifacts import highest_saved_build, save_artifacts


class AndroidArtifactManagerTest(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.base = Path(self.workspace.name)
        self.root = self.base / "Downloads" / "CardAI-Packages"
        self.root.mkdir(parents=True)
        self.package = "com.kando.kandoApp.beta"
        self.apk = self.base / "app-debug.apk"
        self.apk.write_bytes(b"verified android package")

    def save(self, build, environment="test", package=None):
        return save_artifacts(
            self.root,
            environment,
            package or self.package,
            "1.0.7",
            build,
            {"CardAI.apk": self.apk},
            {"sourceCommit": "abc123", "sourceWorkingTreeDirty": False},
        )

    def managed_version(self, build, environment="test", timestamp=None):
        label = "Test" if environment == "test" else "Prod"
        path = self.root / self.package / "Android" / f"CardAI-{label}-1.0.7-{build}"
        path.mkdir(parents=True, exist_ok=False)
        (path / "CardAI.apk").write_bytes(b"existing package")
        if timestamp is not None:
            os.utime(path, (timestamp, timestamp))
        return path

    def test_highest_build_includes_legacy_android_deliveries_to_prevent_downgrades(self):
        self.managed_version(194)
        legacy = self.root / self.package / "CardAI-Test-1.0.7-203-Android-20261109-172557"
        legacy.mkdir()
        (legacy / "CardAI-Test.apk").write_bytes(b"legacy package")
        ios = self.root / self.package / "CardAI-Test-1.0.7-999"
        ios.mkdir()
        (ios / "Card AI Test.ipa").write_bytes(b"ios package")

        self.assertEqual(highest_saved_build(self.root, self.package, "test"), 203)
        self.assertEqual(highest_saved_build(self.root, "com.cardai.tcg", "test"), 0)
        with self.assertRaisesRegex(ValueError, "must exceed saved build 203"):
            self.save(202)

    def test_complete_save_verifies_hashes_and_prunes_only_matching_environment(self):
        oldest = self.managed_version(1, timestamp=1)
        self.managed_version(2, timestamp=2)
        self.managed_version(3, timestamp=3)
        production = self.managed_version(1, environment="production", timestamp=1)
        ios = self.root / self.package / "CardAI-Test-1.0.7-500"
        ios.mkdir(parents=True)
        (ios / "Card AI Test.ipa").write_bytes(b"ios package")

        saved = self.save(4)
        info = json.loads((saved / "build-info.json").read_text(encoding="utf-8"))
        expected_hash = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        self.assertEqual(info["primaryArtifact"], "CardAI.apk")
        self.assertEqual(info["sha256"], expected_hash)
        self.assertEqual(info["bytes"], self.apk.stat().st_size)
        self.assertEqual(info["files"]["CardAI.apk"]["sha256"], expected_hash)
        self.assertEqual(
            (saved / "SHA256SUMS.txt").read_text(encoding="utf-8"),
            f"{expected_hash}  CardAI.apk\n",
        )
        self.assertFalse(oldest.exists())
        self.assertEqual(len(list((saved.parent / ".Recovery").iterdir())), 1)
        self.assertTrue(production.exists())
        self.assertTrue(ios.exists())

    def test_failed_copy_never_publishes_or_prunes_existing_versions(self):
        existing = [self.managed_version(build, timestamp=build) for build in range(1, 4)]
        with patch("save_android_artifacts.shutil.copy2", side_effect=OSError("copy failed")):
            with self.assertRaises(OSError):
                self.save(4)
        self.assertTrue(all(path.exists() for path in existing))
        self.assertFalse((existing[0].parent / ".Recovery").exists())
        self.assertFalse((existing[0].parent / "CardAI-Test-1.0.7-4").exists())

    def test_corrupt_copy_fails_hash_verification_before_publish_or_retention(self):
        existing = [self.managed_version(build, timestamp=build) for build in range(1, 4)]

        def corrupt_copy(source, target):
            Path(target).write_bytes(b"corrupt copy")
            return target

        with patch("save_android_artifacts.shutil.copy2", side_effect=corrupt_copy):
            with self.assertRaisesRegex(OSError, "copy verification failed"):
                self.save(4)
        self.assertTrue(all(path.exists() for path in existing))
        self.assertFalse((existing[0].parent / ".Recovery").exists())
        self.assertFalse((existing[0].parent / "CardAI-Test-1.0.7-4").exists())

    def test_production_retains_seven_without_touching_test_or_ios_versions(self):
        oldest = self.managed_version(1, environment="production", timestamp=1)
        for build in range(2, 8):
            self.managed_version(build, environment="production", timestamp=build)
        test_version = self.managed_version(1, environment="test", timestamp=1)
        ios = self.root / self.package / "CardAI-Prod-1.0.7-999"
        ios.mkdir(parents=True)
        (ios / "Card AI.ipa").write_bytes(b"ios package")

        saved = self.save(8, environment="production")

        production = list(saved.parent.glob("CardAI-Prod-*"))
        self.assertEqual(len(production), 7)
        self.assertFalse(oldest.exists())
        self.assertEqual(len(list((saved.parent / ".Recovery").iterdir())), 1)
        self.assertTrue(test_version.exists())
        self.assertTrue(ios.exists())

    def test_existing_version_is_never_overwritten(self):
        existing = self.managed_version(4)
        with self.assertRaises(FileExistsError):
            self.save(4)
        self.assertEqual((existing / "CardAI.apk").read_bytes(), b"existing package")

    def test_symlink_artifacts_are_rejected(self):
        link = self.base / "linked.apk"
        try:
            link.symlink_to(self.apk)
        except OSError:
            self.skipTest("Symlinks are unavailable on this host")
        with self.assertRaises(ValueError):
            save_artifacts(
                self.root,
                "test",
                self.package,
                "1.0.7",
                4,
                {"linked.apk": link},
                {},
            )

    def test_artifact_names_cannot_escape_the_managed_version(self):
        with self.assertRaises(ValueError):
            save_artifacts(
                self.root,
                "test",
                self.package,
                "1.0.7",
                4,
                {"../escaped.apk": self.apk},
                {},
            )


if __name__ == "__main__":
    unittest.main()
