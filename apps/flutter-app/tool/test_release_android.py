import argparse
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from release_android import (
    build_release,
    read_version,
    select_build_number,
    update_build_number,
    use_jdk,
    verify_artifact,
    verify_native_libraries,
)


class AndroidReleaseTest(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.base = Path(self.workspace.name)
        self.app = self.base / "app"
        self.app.mkdir()
        self.pubspec = self.app / "pubspec.yaml"
        self.original = b"name: example\r\nversion: 1.0.7+194\r\n"
        self.pubspec.write_bytes(self.original)
        config = self.app / "config/test.json"
        config.parent.mkdir()
        config.write_text(json.dumps({"APP_ENV": "test"}))
        self.flutter = self.base / "flutter"
        self.flutter.touch()
        self.args = argparse.Namespace(
            env="test", artifact=None, config=None, build_number=None,
            bundletool=None, artifacts_root=self.base / "packages",
            flutter=str(self.flutter), jdk=None, expected_certificate_sha256=None,
            skip_analyze=False, dry_run=False,
        )

    def command(self, command, cwd, env, capture=False):
        words = [str(word) for word in command]
        if words[1:3] == ["--version", "--machine"]:
            return json.dumps({"frameworkVersion": "3.47.9", "dartSdkVersion": "3.13.7"})
        if words[:3] == ["git", "rev-parse", "HEAD"]:
            return "source-commit\n"
        if words[:3] == ["git", "status", "--porcelain"]:
            return " M tool/release_android.py\n"
        if words[1:] == ["--version"]:
            return f"Daemon JVM: {self.base / 'jdk'} (from JAVA_HOME)\n"
        if words[1:3] == ["build", "apk"]:
            artifact = self.app / "build/app/outputs/flutter-apk/app-debug.apk"
            artifact.parent.mkdir(parents=True)
            artifact.write_bytes(b"verified APK fixture")
        return ""

    def release(self, runner=None, validator=None):
        with patch("release_android.run", side_effect=runner or self.command), \
             patch("release_android.android_tools", return_value=({"java": self.base / "jdk/bin/java"}, {})), \
             patch("release_android.verify_artifact", side_effect=validator or (lambda *args: {"signature": True})):
            return build_release(self.args, self.app, {})

    def test_number_outruns_both_shared_pubspec_and_previous_android_deliveries(self):
        self.assertEqual(select_build_number(194, 203), 204)
        self.assertEqual(select_build_number(210, 203), 211)
        for explicit in [0, 194, 203, 2_100_000_001]:
            with self.subTest(explicit=explicit), self.assertRaises(ValueError):
                select_build_number(194, 203, explicit)

    def test_success_saves_verified_package_before_updating_only_the_build_counter(self):
        saved = self.release()
        self.assertEqual(self.pubspec.read_bytes(), self.original.replace(b"+194", b"+195"))
        info = json.loads((saved / "build-info.json").read_text())
        self.assertEqual(info["buildNumber"], 195)
        self.assertTrue(info["sourceWorkingTreeDirty"])
        self.assertTrue((saved / info["primaryArtifact"]).is_file())
        self.assertEqual(read_version(self.pubspec)[1:], ("1.0.7", 195))

    def test_build_failure_does_not_advance_version_or_publish_artifacts(self):
        def fail_build(command, *args):
            if str(command[1]) == "build":
                raise RuntimeError("build failed")
            return self.command(command, *args)
        with self.assertRaisesRegex(RuntimeError, "build failed"):
            self.release(runner=fail_build)
        self.assertEqual(self.pubspec.read_bytes(), self.original)
        self.assertFalse(self.args.artifacts_root.exists())

    def test_clean_checkout_regenerates_native_plugins_before_no_pub_build(self):
        registrant = self.app / "android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java"

        def prepare_plugins(command, *args):
            words = [str(word) for word in command]
            if words[1:3] == ["pub", "get"]:
                self.assertIn("--enforce-lockfile", words)
                registrant.parent.mkdir(parents=True)
                registrant.write_text("SharedPreferencesPlugin")
            if words[1:3] == ["build", "apk"]:
                self.assertTrue(
                    registrant.is_file(),
                    "A clean checkout must register native plugins before shipping an APK that reads preferences at startup.",
                )
            return self.command(command, *args)

        self.release(runner=prepare_plugins)

    def test_failed_locked_dependency_setup_cannot_ship_stale_native_plugins(self):
        def fail_dependency_setup(command, *args):
            if [str(word) for word in command[1:3]] == ["pub", "get"]:
                raise RuntimeError("locked dependency setup failed")
            return self.command(command, *args)

        with self.assertRaisesRegex(RuntimeError, "locked dependency setup failed"):
            self.release(runner=fail_dependency_setup)
        self.assertEqual(self.pubspec.read_bytes(), self.original)
        self.assertFalse(self.args.artifacts_root.exists())

    def test_verification_failure_cannot_publish_or_advance_a_broken_apk(self):
        def reject(*args):
            raise ValueError("wrong APK identity")
        with self.assertRaisesRegex(ValueError, "wrong APK identity"):
            self.release(validator=reject)
        self.assertEqual(self.pubspec.read_bytes(), self.original)
        self.assertFalse(self.args.artifacts_root.exists())

    def test_failed_archive_never_advances_the_shared_ios_android_counter(self):
        with patch("release_android.save_artifacts", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                self.release()
        self.assertEqual(self.pubspec.read_bytes(), self.original)

    def test_concurrent_version_change_is_preserved_instead_of_overwriting_ios_release(self):
        def change_during_build(command, *args):
            result = self.command(command, *args)
            if str(command[1]) == "build":
                self.pubspec.write_bytes(self.original.replace(b"+194", b"+210"))
            return result
        with self.assertRaisesRegex(RuntimeError, "changed during"):
            self.release(runner=change_during_build)
        self.assertIn(b"+210", self.pubspec.read_bytes())
        self.assertFalse(self.args.artifacts_root.exists())

    def test_version_update_preserves_line_endings_and_rejects_a_changed_source(self):
        update_build_number(self.pubspec, self.original, 204)
        self.assertEqual(self.pubspec.read_bytes(), self.original.replace(b"+194", b"+204"))
        with self.assertRaises(RuntimeError):
            update_build_number(self.pubspec, self.original, 205)

    def test_production_without_external_identity_fails_before_using_test_signing(self):
        self.args.env = "production"
        with patch("release_android.run") as command, self.assertRaisesRegex(ValueError, "ANDROID_APPLICATION_ID"):
            build_release(self.args, self.app, {})
        command.assert_not_called()
        self.assertEqual(self.pubspec.read_bytes(), self.original)

    def test_explicit_jdk_is_restored_even_if_a_build_fails(self):
        jdk = self.base / "jdk"
        jdk.mkdir()
        configured = "old-jdk"

        def command(args, *unused):
            nonlocal configured
            if args[1:] == ["config", "--list"]:
                return f"jdk-dir: {configured}\n"
            configured = str(args[2]).split("=", 1)[1]
            return ""

        with patch("release_android.run", side_effect=command):
            with self.assertRaisesRegex(RuntimeError, "failed inside"):
                with use_jdk(self.flutter, jdk, self.app, {}):
                    self.assertEqual(configured, str(jdk.resolve()))
                    raise RuntimeError("failed inside")
        self.assertEqual(configured, "old-jdk")


class AndroidNativeValidationTest(unittest.TestCase):
    def artifact(self, directory, alignment=16384, address=0):
        data = bytearray(120)
        data[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<Q", data, 32, 64)
        struct.pack_into("<HH", data, 54, 56, 1)
        struct.pack_into("<IIQQQQQQ", data, 64, 1, 5, 0, address, 0, 120, 120, alignment)
        artifact = Path(directory) / "test.apk"
        with zipfile.ZipFile(artifact, "w") as archive:
            archive.writestr("lib/arm64-v8a/libexample.so", data)
        return artifact

    def test_aligned_native_package_is_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(verify_native_libraries(self.artifact(directory))["native64BitLibraries"], 1)

    def test_old_page_alignment_or_incongruent_load_segment_blocks_publication(self):
        for alignment, address in [(4096, 0), (16384, 1)]:
            with self.subTest(alignment=alignment, address=address), tempfile.TemporaryDirectory() as directory:
                with self.assertRaisesRegex(ValueError, "not 16 KB aligned"):
                    verify_native_libraries(self.artifact(directory, alignment, address))

    def test_aab_with_wrong_package_is_rejected_even_if_bundletool_validation_passes(self):
        manifest = '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="wrong.package" android:versionName="1.0.7" android:versionCode="204"/>'
        with patch("release_android.run", side_effect=["", manifest]):
            with self.assertRaisesRegex(ValueError, "AAB package"):
                verify_artifact(Path("release.aab"), "appbundle", "com.cardai.tcg", "1.0.7", 204, {"java": Path("java")}, Path("bundletool.jar"), Path("."), {})

    def test_signed_apk_with_an_unapproved_certificate_cannot_be_published(self):
        badging = "package: name='com.kando.kandoApp.beta' versionCode='204' versionName='1.0.7'\nsdkVersion:'24'\ntargetSdkVersion:'36'\n"
        signature = "Signer #1 certificate SHA-256 digest: " + "a" * 64
        tools = {name: Path(name) for name in ["aapt", "apksigner", "zipalign"]}
        with patch("release_android.run", side_effect=[badging, signature, ""]):
            with self.assertRaisesRegex(ValueError, "approved Android certificate"):
                verify_artifact(Path("test.apk"), "apk", "com.kando.kandoApp.beta", "1.0.7", 204, tools, None, Path("."), {}, "b" * 64)

    def test_apk_target_below_the_supported_release_contract_is_rejected(self):
        badging = "package: name='com.kando.kandoApp.beta' versionCode='204' versionName='1.0.7'\nsdkVersion:'24'\ntargetSdkVersion:'35'\n"
        with patch("release_android.run", return_value=badging):
            with self.assertRaisesRegex(ValueError, "supported SDK"):
                verify_artifact(Path("test.apk"), "apk", "com.kando.kandoApp.beta", "1.0.7", 204, {"aapt": Path("aapt")}, None, Path("."), {}, "a" * 64)

    def test_bundletool_cannot_allow_an_aab_to_drop_supported_android_versions(self):
        manifest = '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.cardai.tcg" android:versionName="1.0.7" android:versionCode="204"><uses-sdk android:minSdkVersion="25" android:targetSdkVersion="36"/></manifest>'
        with patch("release_android.run", side_effect=["", manifest]):
            with self.assertRaisesRegex(ValueError, "minimum or target SDK"):
                verify_artifact(Path("release.aab"), "appbundle", "com.cardai.tcg", "1.0.7", 204, {"java": Path("java")}, Path("bundletool.jar"), Path("."), {}, "a" * 64)


if __name__ == "__main__":
    unittest.main()
