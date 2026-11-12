"""Save verified Android deliverables and retain recoverable version history."""

import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile
import uuid


MAX_BUILD_NUMBER = 2_100_000_000
PACKAGE_ID = re.compile(r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+")
SEMANTIC_VERSION = re.compile(r"\d+\.\d+\.\d+")
MANAGED_VERSION = re.compile(r"CardAI-(Test|Prod)-(\d+\.\d+\.\d+)-(\d+)")
LEGACY_VERSION = re.compile(
    r"CardAI-(Test|Prod)-(\d+\.\d+\.\d+)-(\d+)-Android-.+",
)


def _label(environment):
    try:
        return {"test": "Test", "production": "Prod"}[environment]
    except KeyError as error:
        raise ValueError(f"Unsupported environment: {environment}") from error


def _validate_identity(package_id, version, build):
    if not PACKAGE_ID.fullmatch(package_id):
        raise ValueError(f"Invalid Android package ID: {package_id}")
    if not SEMANTIC_VERSION.fullmatch(version):
        raise ValueError(f"Invalid semantic version: {version}")
    if not isinstance(build, int) or isinstance(build, bool) or not 0 < build <= MAX_BUILD_NUMBER:
        raise ValueError(f"Invalid Android build number: {build}")


def _resolved(path):
    return path.resolve(strict=False)


def _require_within(path, parent, label):
    try:
        _resolved(path).relative_to(_resolved(parent))
    except ValueError as error:
        raise ValueError(f"{label} escapes the managed Android directory: {path}") from error


def _is_link(path):
    return path.is_symlink() or (
        hasattr(path, "is_junction") and path.is_junction()
    )


def _reject_symlink(path, label):
    if _is_link(path):
        raise ValueError(f"{label} must not be a symlink: {path}")


def _sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _contains_android_package(path):
    return path.is_dir() and not _is_link(path) and any(
        item.is_file() and not _is_link(item) and item.suffix.lower() in {".apk", ".aab"}
        for item in path.iterdir()
    )


def highest_saved_build(root: Path, package_id: str, environment: str) -> int:
    """Return the highest saved Android build for this package and environment."""
    label = _label(environment)
    if not PACKAGE_ID.fullmatch(package_id):
        raise ValueError(f"Invalid Android package ID: {package_id}")
    root = Path(root)
    _reject_symlink(root, "Artifact root")
    package_root = root / package_id
    _reject_symlink(package_root, "Package directory")
    highest = 0

    managed_root = package_root / "Android"
    _reject_symlink(managed_root, "Managed Android directory")
    if managed_root.is_dir():
        for path in managed_root.iterdir():
            match = MANAGED_VERSION.fullmatch(path.name)
            if match and match.group(1) == label and _contains_android_package(path):
                highest = max(highest, int(match.group(3)))

    if package_root.is_dir():
        for path in package_root.iterdir():
            match = LEGACY_VERSION.fullmatch(path.name)
            if match and match.group(1) == label and _contains_android_package(path):
                highest = max(highest, int(match.group(3)))
    return highest


def _validate_artifacts(artifacts):
    if not artifacts:
        raise ValueError("At least one Android artifact is required")
    validated = {}
    has_package = False
    for name, source in artifacts.items():
        if not isinstance(name, str) or not name or Path(name).name != name or name in {".", ".."}:
            raise ValueError(f"Invalid Android artifact name: {name!r}")
        suffix = Path(name).suffix.lower()
        if suffix not in {".apk", ".aab", ".txt", ".symbols"}:
            raise ValueError(f"Unsupported Android artifact: {name}")
        if suffix == ".txt" and name != "mapping.txt":
            raise ValueError(f"Unsupported Android text artifact: {name}")
        source = Path(source)
        if _is_link(source) or not source.is_file():
            raise ValueError(f"Android artifact must be a regular file: {source}")
        has_package = has_package or suffix in {".apk", ".aab"}
        validated[name] = source
    if not has_package:
        raise ValueError("Android artifacts must include an APK or AAB")
    return validated


def _managed_versions(managed_root, label):
    versions = []
    for path in managed_root.iterdir():
        match = MANAGED_VERSION.fullmatch(path.name)
        if match and match.group(1) == label and _contains_android_package(path):
            versions.append(path)
    return sorted(
        versions,
        key=lambda path: (path.stat().st_mtime_ns, path.name),
        reverse=True,
    )


def _move_to_recovery(path, managed_root):
    _reject_symlink(path, "Managed Android version")
    _require_within(path, managed_root, "Managed Android version")
    recovery = managed_root / ".Recovery"
    _reject_symlink(recovery, "Android recovery directory")
    recovery.mkdir(exist_ok=True)
    _require_within(recovery, managed_root, "Android recovery directory")
    destination = recovery / f"{path.name}-{uuid.uuid4().hex}"
    _require_within(destination, managed_root, "Android recovery destination")
    if destination.exists() or _is_link(destination):
        raise FileExistsError(f"Android recovery destination exists: {destination}")
    shutil.move(str(path), str(destination))


def save_artifacts(
    root: Path,
    environment: str,
    package_id: str,
    version: str,
    build: int,
    artifacts: dict[str, Path],
    metadata: dict,
) -> Path:
    """Save one complete Android version, then recoverably prune older versions."""
    label = _label(environment)
    _validate_identity(package_id, version, build)
    artifacts = _validate_artifacts(artifacts)
    if not isinstance(metadata, dict):
        raise ValueError("Android build metadata must be an object")

    root = Path(root)
    _reject_symlink(root, "Artifact root")
    root.mkdir(parents=True, exist_ok=True)
    package_root = root / package_id
    _reject_symlink(package_root, "Package directory")
    package_root.mkdir(exist_ok=True)
    managed_root = package_root / "Android"
    _reject_symlink(managed_root, "Managed Android directory")
    managed_root.mkdir(exist_ok=True)
    _require_within(managed_root, package_root, "Managed Android directory")

    destination = managed_root / f"CardAI-{label}-{version}-{build}"
    _require_within(destination, managed_root, "Android version destination")
    if destination.exists() or _is_link(destination):
        raise FileExistsError(f"Refusing to overwrite saved Android version: {destination}")
    previous_build = highest_saved_build(root, package_id, environment)
    if build <= previous_build:
        raise ValueError(
            f"Android build number {build} must exceed saved build {previous_build}",
        )

    with tempfile.TemporaryDirectory(prefix=".pending-", dir=managed_root) as staging:
        staging_path = Path(staging)
        artifact_records = {}
        for name, source in artifacts.items():
            target = staging_path / name
            _require_within(target, staging_path, "Staged Android artifact")
            shutil.copy2(source, target)
            source_hash = _sha256(source)
            copied_hash = _sha256(target)
            if source_hash != copied_hash or source.stat().st_size != target.stat().st_size:
                raise OSError(f"Android artifact copy verification failed: {name}")
            artifact_records[name] = {
                "bytes": target.stat().st_size,
                "sha256": copied_hash,
            }

        package_names = sorted(
            name for name in artifact_records if Path(name).suffix.lower() in {".apk", ".aab"}
        )
        requested_primary = metadata.get("primaryArtifact")
        if requested_primary is not None and requested_primary not in package_names:
            raise ValueError("primaryArtifact must name a saved APK or AAB")
        preferred_suffix = ".apk" if environment == "test" else ".aab"
        primary_artifact = requested_primary or next(
            (name for name in package_names if Path(name).suffix.lower() == preferred_suffix),
            package_names[0],
        )
        primary_record = artifact_records[primary_artifact]
        build_info = dict(metadata)
        build_info.update({
            "platform": "android",
            "environment": environment,
            "applicationId": package_id,
            "version": version,
            "buildNumber": build,
            "primaryArtifact": primary_artifact,
            "bytes": primary_record["bytes"],
            "sha256": primary_record["sha256"],
            "files": artifact_records,
        })
        (staging_path / "build-info.json").write_text(
            json.dumps(build_info, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        checksum_lines = [
            f"{record['sha256']}  {name}"
            for name, record in sorted(artifact_records.items())
        ]
        (staging_path / "SHA256SUMS.txt").write_text(
            "\n".join(checksum_lines) + "\n",
            encoding="utf-8",
        )

        destination.mkdir()
        try:
            for path in staging_path.iterdir():
                path.rename(destination / path.name)
        except BaseException:
            for path in destination.iterdir():
                path.rename(staging_path / path.name)
            destination.rmdir()
            raise

    for path in _managed_versions(managed_root, label)[3 if environment == "test" else 7:]:
        _move_to_recovery(path, managed_root)
    return destination
