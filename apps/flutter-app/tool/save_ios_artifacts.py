"""Save iOS deliverables by Bundle ID: keep three test or seven production versions."""

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile


VERSION_FOLDER = re.compile(r"CardAI-(Test|Prod)-\d+\.\d+\.\d+-\d+")


def check_zip(path):
    with zipfile.ZipFile(path) as archive:
        if not archive.namelist() or archive.testzip() is not None:
            raise ValueError(f"Invalid or empty ZIP: {path}")


def prune_versions(root, trash, label, keep):
    versions = [
        path for path in root.iterdir()
        if VERSION_FOLDER.fullmatch(path.name) and path.name.startswith(f"CardAI-{label}-")
        and not path.is_symlink() and path.is_dir()
        and (path / "dSYMs.zip").is_file()
        and any(path.glob("*.ipa"))
    ]
    versions.sort(key=lambda path: (path.stat().st_mtime_ns, path.name), reverse=True)
    for path in versions[keep:]:
        trash.mkdir(parents=True, exist_ok=True)
        destination = trash / f"{path.name}-{uuid.uuid4().hex}"
        shutil.move(str(path), str(destination))
        print(f"[release-ios] Moved older artifacts to Trash: {destination}", file=sys.stderr)


def save_artifacts(root, trash, environment, bundle_id, version, build, ipa, dsyms):
    label = {"test": "Test", "production": "Prod"}[environment]
    name = f"CardAI-{label}-{version}-{build}"
    if not VERSION_FOLDER.fullmatch(name):
        raise ValueError(f"Invalid version folder: {name}")
    if root.is_symlink():
        raise ValueError(f"Artifact root must not be a symlink: {root}")
    if not re.fullmatch(r"[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*", bundle_id):
        raise ValueError(f"Invalid Bundle ID: {bundle_id}")
    root = root / bundle_id
    if root.is_symlink():
        raise ValueError(f"Package directory must not be a symlink: {root}")
    root.mkdir(parents=True, exist_ok=True)
    destination = root / name
    if destination.exists() or destination.is_symlink():
        raise FileExistsError(f"Refusing to overwrite saved version: {destination}")
    if not dsyms.is_dir() or not any(dsyms.glob("*.dSYM/Contents/Resources/DWARF/*")):
        raise ValueError(f"No dSYM binaries found: {dsyms}")
    check_zip(ipa)
    # Only publish a complete version. Failed copies never evict older versions.
    with tempfile.TemporaryDirectory(prefix=".pending-", dir=root) as staging:
        staging_path = Path(staging)
        shutil.copy2(ipa, staging_path / ipa.name)
        subprocess.run(
            ["ditto", "-c", "-k", "--keepParent", str(dsyms),
             str(staging_path / "dSYMs.zip")], check=True,
        )
        check_zip(staging_path / ipa.name)
        check_zip(staging_path / "dSYMs.zip")
        # mkdir is exclusive: a concurrent save cannot overwrite this version.
        destination.mkdir()
        try:
            for path in staging_path.iterdir():
                path.rename(destination / path.name)
        except BaseException:
            # Return partial files to staging before removing the empty folder.
            for path in destination.iterdir():
                path.rename(staging_path / path.name)
            destination.rmdir()
            raise
    prune_versions(root, trash, label, 3 if environment == "test" else 7)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", choices=["test", "production"], required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", type=int, required=True)
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--dsyms", type=Path, required=True)
    args = parser.parse_args()
    print(save_artifacts(
        Path.home() / "Downloads" / "CardAI-Packages", Path.home() / ".Trash",
        args.env, args.bundle_id, args.version, args.build_number, args.ipa, args.dsyms,
    ))


if __name__ == "__main__":
    main()
