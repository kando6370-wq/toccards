"""Build, verify and save an Android release before advancing pubspec's build number."""

import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

from save_android_artifacts import highest_saved_build, save_artifacts


APP_DIR = Path(__file__).resolve().parent.parent
TEST_PACKAGE = "com.kando.kandoApp.beta"
TEST_CERTIFICATE_SHA256 = "18ff20094a56b75f917ff8c3cbf182600de1884adb898ccea18ad12ca73248b8"
MAX_BUILD = 2_100_000_000
VERSION_LINE = re.compile(rb"(?m)^version:[ \t]*(\d+\.\d+\.\d+)\+(\d+)[ \t]*\r?$")
ANDROID_XML = "{http://schemas.android.com/apk/res/android}"


def run(command, cwd, env, capture=False):
    result = subprocess.run(
        [str(value) for value in command], cwd=cwd, env=env, text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode:
        raise RuntimeError(f"{Path(command[0]).name} failed with exit code {result.returncode}")
    return result.stdout if capture else ""


def version_numbers(value):
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)", value)
    if not match:
        raise ValueError("Unrecognized SDK version")
    return tuple(map(int, match.groups()))


def read_version(pubspec):
    contents = pubspec.read_bytes()
    matches = list(VERSION_LINE.finditer(contents))
    if len(matches) != 1:
        raise ValueError("pubspec.yaml must contain one version: major.minor.patch+build line")
    match = matches[0]
    return contents, match.group(1).decode(), int(match.group(2))


def select_build_number(current, saved, explicit=None):
    floor = max(current, saved)
    selected = floor + 1 if explicit is None else explicit
    if selected <= floor or selected > MAX_BUILD:
        raise ValueError(f"Build number must be greater than {floor} and at most {MAX_BUILD}")
    return selected


def update_build_number(pubspec, original, selected):
    if pubspec.read_bytes() != original:
        raise RuntimeError("pubspec.yaml changed during the build; its version was not overwritten")
    match = VERSION_LINE.search(original)
    replacement = original[:match.start(2)] + str(selected).encode() + original[match.end(2):]
    descriptor, temporary = tempfile.mkstemp(prefix=".pubspec-android-", dir=pubspec.parent)
    try:
        os.chmod(temporary, pubspec.stat().st_mode & 0o777)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(replacement)
            handle.flush()
            os.fsync(handle.fileno())
        if pubspec.read_bytes() != original:
            raise RuntimeError("pubspec.yaml changed during the build; its version was not overwritten")
        os.replace(temporary, pubspec)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def default_artifacts_root():
    downloads = Path.home() / "Downloads"
    if os.name == "nt":
        import winreg
        try:
            with winreg.OpenKey(
                winreg.HKEY_CURRENT_USER,
                r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders",
            ) as key:
                value, _ = winreg.QueryValueEx(key, "{374DE290-123F-4565-9164-39C4925E467B}")
                downloads = Path(os.path.expandvars(value))
        except FileNotFoundError:
            pass
    return downloads / "CardAI-Packages"


def configured_jdk(settings):
    match = re.search(r"^\s*jdk-dir:\s*(.+)$", settings, re.MULTILINE)
    return match.group(1).strip() if match and match.group(1).strip() != "(Not set)" else ""


@contextmanager
def use_jdk(flutter, directory, app_dir, environment):
    if directory is None:
        yield environment
        return
    directory = directory.resolve(strict=True)
    before = configured_jdk(run([flutter, "config", "--list"], app_dir, environment, True))
    selected_env = {**environment, "JAVA_HOME": str(directory)}
    try:
        run([flutter, "config", f"--jdk-dir={directory}"], app_dir, selected_env)
        yield selected_env
    finally:
        run([flutter, "config", f"--jdk-dir={before}"], app_dir, environment)
        restored = configured_jdk(run([flutter, "config", "--list"], app_dir, environment, True))
        if restored != before:
            raise RuntimeError("Flutter's temporary JDK setting was not restored")


def android_tools(flutter, app_dir, environment):
    doctor = run([flutter, "doctor", "-v"], app_dir, environment, True)
    sdk_match = re.search(r"Android SDK at (.+)", doctor)
    java_match = re.search(r"Java binary at:\s*(.+)", doctor)
    if not sdk_match or not java_match:
        raise RuntimeError("Flutter doctor did not identify its Android SDK and actual Java executable")
    java = Path(java_match.group(1).strip())
    if os.name == "nt" and not java.suffix:
        java = java.with_suffix(".exe")
    java_result = subprocess.run([str(java), "-version"], text=True, capture_output=True, env=environment)
    java_version = java_result.stdout + java_result.stderr
    match = re.search(r'version "(21\.\d+\.\d+)', java_version)
    build = re.search(r"21\.0\.13\+(\d+)", java_version)
    if java_result.returncode or not match or version_numbers(match.group(1)) < (21, 0, 13):
        raise RuntimeError("Android builds require the patched JDK 21.0.13+9 or a newer JDK 21 patch")
    if version_numbers(match.group(1)) == (21, 0, 13) and (not build or int(build.group(1)) < 9):
        raise RuntimeError("JDK 21.0.13 must be build 9 or later")
    build_tools = Path(sdk_match.group(1).strip()) / "build-tools"
    candidates = [path for path in build_tools.iterdir() if re.fullmatch(r"\d+\.\d+\.\d+", path.name)]
    if not candidates:
        raise RuntimeError("Android SDK build-tools are missing")
    selected = max(candidates, key=lambda path: version_numbers(path.name))
    suffix = ".exe" if os.name == "nt" else ""
    tools = {name: selected / (name + suffix) for name in ["aapt", "zipalign"]}
    tools["apksigner"] = selected / ("apksigner.bat" if os.name == "nt" else "apksigner")
    if not all(path.is_file() for path in tools.values()):
        raise RuntimeError("Selected Android build-tools do not contain aapt, apksigner and zipalign")
    tools["java"] = java
    tools["jarsigner"] = java.parent / ("jarsigner.exe" if os.name == "nt" else "jarsigner")
    tools["keytool"] = java.parent / ("keytool.exe" if os.name == "nt" else "keytool")
    return tools, {**environment, "JAVA_HOME": str(java.parent.parent)}


def verify_native_libraries(artifact):
    libraries = []
    with zipfile.ZipFile(artifact) as archive:
        if archive.testzip() is not None:
            raise ValueError("Android artifact has a corrupt ZIP entry")
        for name in archive.namelist():
            if not re.fullmatch(r"(?:base/)?lib/[^/]+/[^/]+\.so", name):
                continue
            data = archive.read(name)
            if data[:4] != b"\x7fELF" or data[4] not in (1, 2) or data[5] not in (1, 2):
                raise ValueError(f"Invalid ELF library: {name}")
            is_64 = data[4] == 2
            if is_64:
                endian = "<" if data[5] == 1 else ">"
                offset = struct.unpack_from(endian + "Q", data, 32)[0]
                size, count = struct.unpack_from(endian + "HH", data, 54)
                loads = []
                for index in range(count):
                    segment = struct.unpack_from(endian + "IIQQQQQQ", data, offset + index * size)
                    if segment[0] == 1:
                        loads.append(segment)
                if not loads or any(segment[7] < 16384 or (segment[3] - segment[2]) % 16384 for segment in loads):
                    raise ValueError(f"64-bit ELF library is not 16 KB aligned: {name}")
            libraries.append({"name": name, "is64Bit": is_64})
    if not any(item["is64Bit"] for item in libraries):
        raise ValueError("Android artifact contains no 64-bit native libraries")
    return {"nativeLibraries": len(libraries), "native64BitLibraries": sum(item["is64Bit"] for item in libraries), "elf64Bit16KB": True}


def verify_artifact(artifact, kind, package, version, build, tools, bundletool, app_dir, environment, expected_certificate=None):
    if kind == "apk":
        badging = run([tools["aapt"], "dump", "badging", artifact], app_dir, environment, True)
        expected = f"package: name='{package}' versionCode='{build}' versionName='{version}'"
        target = re.search(r"targetSdkVersion:'(\d+)'", badging)
        if expected not in badging or "sdkVersion:'24'" not in badging or not target or int(target.group(1)) < 36:
            raise ValueError("APK package, version or supported SDK range does not match the selected release")
        signature = run([tools["apksigner"], "verify", "--verbose", "--print-certs", artifact], app_dir, environment, True)
        digest = re.search(r"Signer #1 certificate SHA-256 digest:\s*([a-fA-F0-9]{64})", signature)
        if not digest:
            raise ValueError("APK verification did not return a signing certificate")
        run([tools["zipalign"], "-c", "-P", "16", "4", artifact], app_dir, environment)
        checks = {"signature": True, "certificateSha256": digest.group(1).lower(), "zipAlign16KB": True}
    else:
        command = [tools["java"], "-jar", bundletool]
        run(command + ["validate", f"--bundle={artifact}"], app_dir, environment)
        manifest = ET.fromstring(run(command + ["dump", "manifest", f"--bundle={artifact}"], app_dir, environment, True))
        if (manifest.get("package"), manifest.get(ANDROID_XML + "versionName"), manifest.get(ANDROID_XML + "versionCode")) != (package, version, str(build)):
            raise ValueError("AAB package and version do not match the selected release")
        sdk = manifest.find("uses-sdk")
        if sdk is None or sdk.get(ANDROID_XML + "minSdkVersion") != "24" or int(sdk.get(ANDROID_XML + "targetSdkVersion", "0")) < 36:
            raise ValueError("AAB minimum or target SDK does not meet the release contract")
        run([tools["jarsigner"], "-verify", artifact], app_dir, environment)
        certificate = run([tools["keytool"], "-printcert", "-jarfile", artifact], app_dir, environment, True)
        digest = re.search(r"SHA256:\s*([a-fA-F0-9:]+)", certificate)
        if not digest or len(digest.group(1).replace(":", "")) != 64:
            raise ValueError("AAB verification did not return an upload signing certificate")
        checks = {"signature": True, "certificateSha256": digest.group(1).replace(":", "").lower(), "bundletoolValidated": True}
    if not expected_certificate or checks["certificateSha256"] != expected_certificate:
        raise ValueError("Final signing certificate does not match the approved Android certificate")
    return {**checks, "approvedCertificateMatched": True, **verify_native_libraries(artifact)}


def build_release(args, app_dir=APP_DIR, environment=None):
    environment = dict(os.environ if environment is None else environment)
    original, version, current = read_version(app_dir / "pubspec.yaml")
    kind = args.artifact or ("apk" if args.env == "test" else "appbundle")
    if args.env == "test" and kind != "apk":
        raise ValueError("Test deliveries must be installable Debug APKs")
    package = TEST_PACKAGE if args.env == "test" else environment.get("ANDROID_APPLICATION_ID", "").strip()
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+", package):
        raise ValueError("A valid external ANDROID_APPLICATION_ID is required for production")
    if args.env == "production" and package == TEST_PACKAGE:
        raise ValueError("Production must not use the test application ID")
    certificate_key = "ANDROID_TEST_CERTIFICATE_SHA256" if args.env == "test" else "ANDROID_UPLOAD_CERTIFICATE_SHA256"
    expected_certificate = args.expected_certificate_sha256 or environment.get(certificate_key) or (TEST_CERTIFICATE_SHA256 if args.env == "test" else "")
    expected_certificate = re.sub(r"[:\s]", "", expected_certificate).lower()
    if not re.fullmatch(r"[a-f0-9]{64}", expected_certificate):
        raise ValueError(f"A verified {certificate_key} is required")
    config_path = args.config or Path(environment.get("RELEASE_ENV_CONFIG", str(app_dir / "config" / f"{args.env}.json")))
    config_path = config_path.resolve(strict=True)
    config = json.loads(config_path.read_text(encoding="utf-8-sig"))
    if config.get("APP_ENV") != args.env:
        raise ValueError("Release config APP_ENV does not match the selected environment")
    defines = {}
    bundletool = args.bundletool or (Path(environment["BUNDLETOOL_JAR"]) if environment.get("BUNDLETOOL_JAR") else None)
    if args.env == "production":
        required = ["ANDROID_KEYSTORE_PATH", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD", "ANDROID_STORE_PASSWORD", "ANDROID_FIREBASE_CONFIG_PATH"]
        if any(not environment.get(key) for key in required):
            raise ValueError("Production requires externally injected signing and Firebase configuration")
        if not Path(environment["ANDROID_KEYSTORE_PATH"]).is_file():
            raise ValueError("Production upload keystore does not exist")
        for key in ["GOOGLE_SERVER_CLIENT_ID", "ANDROID_PLAY_CLOUD_PROJECT_NUMBER"]:
            value = environment.get(key) or config.get(key)
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"Production requires {key}")
            defines[key] = value.strip()
    firebase = environment.get("ANDROID_FIREBASE_CONFIG_PATH", "").strip()
    if firebase:
        native_config = json.loads(Path(firebase).read_text(encoding="utf-8-sig"))
        packages = {client.get("client_info", {}).get("android_client_info", {}).get("package_name") for client in native_config.get("client", [])}
        if package not in packages:
            raise ValueError("External Firebase config does not contain the selected Android package")
    if kind == "appbundle" and (bundletool is None or not bundletool.is_file()):
        raise ValueError("AAB validation requires --bundletool or BUNDLETOOL_JAR")
    saved = highest_saved_build(args.artifacts_root, package, args.env)
    selected = select_build_number(current, saved, args.build_number)
    plan = {"environment": args.env, "applicationId": package, "version": f"{version}+{selected}", "artifactType": kind, "currentBuild": current, "highestSavedAndroidBuild": saved}
    if args.dry_run:
        print(json.dumps({**plan, "dryRun": True, "built": False}, indent=2))
        return None
    flutter = shutil.which(args.flutter) or (args.flutter if Path(args.flutter).is_file() else None)
    if not flutter:
        raise ValueError("Flutter executable not found; use --flutter to select the patched SDK")
    flutter = Path(flutter).resolve()
    sdk = json.loads(run([flutter, "--version", "--machine"], app_dir, environment, True))
    if version_numbers(sdk["frameworkVersion"]) < (3, 47, 9) or version_numbers(sdk["dartSdkVersion"]) < (3, 13, 7):
        raise ValueError("Flutter >=3.47.9 and Dart >=3.13.7 are required")
    dart = flutter.parent / "cache" / "dart-sdk" / "bin" / ("dart.exe" if os.name == "nt" else "dart")
    run([dart, app_dir / "tool/validate_release_config.dart", config_path, args.env], app_dir, environment)
    source = run(["git", "rev-parse", "HEAD"], app_dir, environment, True).strip()
    dirty = bool(run(["git", "status", "--porcelain"], app_dir, environment, True).strip())
    if args.env == "production" and dirty:
        raise ValueError("Production releases require an approved clean checkout")
    # Native plugin registrants are ignored generated files and may be absent
    # even when package_config.json is already available for --no-pub builds.
    run([flutter, "pub", "get", "--enforce-lockfile"], app_dir, environment)
    with use_jdk(flutter, args.jdk, app_dir, environment) as build_env:
        tools, build_env = android_tools(flutter, app_dir, build_env)
        build_env.setdefault("GRADLE_OPTS", '-Dorg.gradle.jvmargs="-Xmx2048m -XX:MaxMetaspaceSize=768m -XX:ReservedCodeCacheSize=256m" -Dorg.gradle.workers.max=1 -Dorg.gradle.parallel=false')
        wrapper = app_dir / "android" / ("gradlew.bat" if os.name == "nt" else "gradlew")
        gradle_version = run([wrapper, "--version"], app_dir / "android", build_env, True)
        daemon = re.search(r"Daemon JVM:\s*(.+)", gradle_version)
        expected_java_home = str(tools["java"].parent.parent).replace("\\", "/").lower()
        if not daemon or expected_java_home not in daemon.group(1).replace("\\", "/").lower():
            raise RuntimeError("Actual Gradle daemon JVM does not match Flutter's selected patched JDK")
        if not args.skip_analyze:
            run([flutter, "analyze", "--no-pub"], app_dir, build_env)
        symbols = app_dir / "build/android-symbols" / args.env / f"{version}-{selected}"
        command = [flutter, "build", kind, "--debug" if args.env == "test" else "--release", "--no-pub", f"--build-name={version}", f"--build-number={selected}", f"--dart-define-from-file={config_path}"]
        command += [f"--dart-define={key}={value}" for key, value in defines.items()]
        command += ["--android-project-arg=kotlin.incremental=false", "--android-project-arg=kotlin.compiler.execution.strategy=in-process"]
        if args.env == "production":
            command.append(f"--split-debug-info={symbols}")
        print(json.dumps(plan, indent=2), flush=True)
        run(command, app_dir, build_env)
        mode = "debug" if args.env == "test" else "release"
        artifact = app_dir / (f"build/app/outputs/flutter-apk/app-{mode}.apk" if kind == "apk" else "build/app/outputs/bundle/release/app-release.aab")
        checks = verify_artifact(artifact, kind, package, version, selected, tools, bundletool, app_dir, build_env, expected_certificate)
        if (app_dir / "pubspec.yaml").read_bytes() != original:
            raise RuntimeError("pubspec.yaml changed during the build; no version was published")
        label = "Test" if args.env == "test" else "Prod"
        name = f"CardAI-{label}-{version}-{selected}.{'apk' if kind == 'apk' else 'aab'}"
        artifacts = {name: artifact}
        mapping = app_dir / "build/app/outputs/mapping/release/mapping.txt"
        if args.env == "production":
            artifacts.update({path.name: path for path in symbols.glob("*.symbols")})
            if mapping.is_file():
                artifacts["mapping.txt"] = mapping
        metadata = {**plan, "platform": "android", "version": version, "buildNumber": selected, "sourceCommit": source, "sourceWorkingTreeDirty": dirty, "primaryArtifact": name, "flutter": sdk["frameworkVersion"], "dart": sdk["dartSdkVersion"], "gradleJvm": daemon.group(1).strip(), "analyzeRun": not args.skip_analyze, "validation": checks, "realDeviceAcceptance": "not run"}
        destination = save_artifacts(args.artifacts_root, args.env, package, version, selected, artifacts, metadata)
        update_build_number(app_dir / "pubspec.yaml", original, selected)
    print(f"[release-android] Saved: {destination}")
    print(f"[release-android] pubspec.yaml updated to {version}+{selected}; commit it when appropriate.")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", choices=["test", "production"], default="production")
    parser.add_argument("--artifact", choices=["apk", "appbundle"])
    parser.add_argument("--build-number", type=int)
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--jdk", type=Path)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--bundletool", type=Path)
    parser.add_argument("--expected-certificate-sha256")
    parser.add_argument("--artifacts-root", type=Path, default=default_artifacts_root())
    parser.add_argument("--skip-analyze", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        build_release(args)
    except (OSError, ValueError, RuntimeError, KeyError, ET.ParseError, zipfile.BadZipFile) as error:
        print(f"[release-android] ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
