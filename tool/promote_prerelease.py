"""Turn a tested pre-release into the stable release without rebuilding.

The pre-release APK was verified (signature pin, package, ABI) by the workflow
run that published it, and the pre-release holds only that APK. Its tag names
the version and its target the commit it was built from. This binds the same
APK to the stable tag of that version and records the master commit it is
released from.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


def promote(root: Path, apk: Path, tested_tag: str, tested_commit: str,
            destination: Path, commit: str) -> dict:
    if not all(re.fullmatch(r'[0-9a-f]{40}', sha) for sha in (commit, tested_commit)):
        raise ValueError('Exact commit SHAs are required')
    versions = re.findall(r'^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$',
                          (root / 'pubspec.yaml').read_text(), re.M)
    if len(versions) != 1:
        raise ValueError('A stable version+build is required')
    version, version_code = versions[0]
    if re.fullmatch(rf'v{re.escape(version)}-pre\.[1-9]\d*', tested_tag) is None:
        raise ValueError('The pre-release does not match the pubspec version')
    if apk.name != f'Moru-{tested_tag}-arm64-v8a-release.apk':
        raise ValueError('The APK is not the one of this pre-release')
    pin = (root / '.github/moru-signing-cert-sha256.txt').read_text().strip().lower()
    if not re.fullmatch(r'[0-9a-f]{64}', pin):
        raise ValueError('Invalid signing certificate pin')
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    tag = f'v{version}'
    filename = f'Moru-{tag}-arm64-v8a-release.apk'
    metadata = {
        'tag': tag, 'prerelease': False,
        'version': version, 'version_code': int(version_code),
        'package': 'com.mishaqp.moru', 'abi': 'arm64-v8a', 'commit': commit,
        'filename': filename, 'sha256': digest, 'size_bytes': apk.stat().st_size,
        'certificate_sha256': pin,
        'tested_tag': tested_tag, 'tested_commit': tested_commit,
    }
    destination.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(apk, destination / filename)
    (destination / f'{filename}.sha256').write_text(f'{digest}  {filename}\n')
    (destination / 'release-metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--tag', required=True, help='Tag of the pre-release')
    parser.add_argument('--tested-commit', required=True,
                        help='Commit the pre-release was built from')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    try:
        metadata = promote(Path.cwd(), args.apk, args.tag, args.tested_commit,
                           args.output, args.commit)
    except (ValueError, OSError) as error:
        parser.exit(1, f'Pre-release promotion failed: {error}\n')
    print(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()
