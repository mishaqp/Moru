"""Turn a tested pre-release into the stable release without rebuilding.

The pre-release APK was verified (signature pin, package, ABI) by the workflow
run that published it. This only rechecks its checksum, binds it to the stable
tag of the same version and records the master commit it is released from.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


def promote(root: Path, source: Path, destination: Path, commit: str) -> dict:
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('An exact commit SHA is required')
    versions = re.findall(r'^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$',
                          (root / 'pubspec.yaml').read_text(), re.M)
    if len(versions) != 1:
        raise ValueError('A stable version+build is required')
    version, version_code = versions[0]
    tested = json.loads((source / 'release-metadata.json').read_text())
    expected_tag = re.fullmatch(rf'v{re.escape(version)}-pre\.[1-9]\d*', tested.get('tag', ''))
    if (not tested.get('prerelease') or expected_tag is None
            or tested.get('version') != version
            or tested.get('version_code') != int(version_code)):
        raise ValueError('The pre-release does not match the pubspec version')
    apk = source / tested['filename']
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    if digest != tested['sha256'] or apk.stat().st_size != tested['size_bytes']:
        raise ValueError('The pre-release APK does not match its metadata')
    tag = f'v{version}'
    filename = f'Moru-{tag}-arm64-v8a-release.apk'
    metadata = dict(tested, tag=tag, prerelease=False, filename=filename,
                    commit=commit, tested_tag=tested['tag'],
                    tested_commit=tested['commit'])
    destination.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(apk, destination / filename)
    (destination / f'{filename}.sha256').write_text(f'{digest}  {filename}\n')
    (destination / 'release-metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prerelease-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    try:
        metadata = promote(Path.cwd(), args.prerelease_dir, args.output, args.commit)
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        parser.exit(1, f'Pre-release promotion failed: {error}\n')
    print(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()
