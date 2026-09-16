"""Package a verified single-ABI APK without rebuilding or re-signing it.

Run only after apksigner and verify_apk_arm64.py have succeeded. The checksum
binds the downloaded APK to the reports produced by that same workflow run.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


def _one(directory: Path, pattern: str) -> Path:
    paths = [path for path in directory.rglob(pattern) if path.is_file()]
    if len(paths) != 1:
        raise ValueError(f'Expected exactly one {pattern} in {directory}')
    return paths[0]


def prepare_release(root: Path, apk_dir: Path, reports_dir: Path,
                    destination: Path, commit: str) -> dict:
    versions = re.findall(r'^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$',
                          (root / 'pubspec.yaml').read_text(), re.M)
    if len(versions) != 1 or not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('A stable version+build and exact commit SHA are required')
    version, version_code = versions[0]
    pin = (root / '.github/moru-signing-cert-sha256.txt').read_text().strip().lower()
    if not re.fullmatch(r'[0-9a-f]{64}', pin):
        raise ValueError('Invalid signing certificate pin')
    apk = _one(apk_dir, '*.apk')
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    checksum = _one(reports_dir, 'apk.sha256').read_text().split()
    if len(checksum) != 2 or checksum[0] != digest or Path(checksum[1]).name != apk.name:
        raise ValueError('APK checksum does not match the verified build')
    signature = _one(reports_dir, 'signature.txt').read_text()
    certificates = re.findall(r'^Signer #\d+ certificate SHA-256 digest:\s*(\S+)\s*$',
                              signature, re.M)
    if [value.replace(':', '').lower() for value in certificates] != [pin]:
        raise ValueError('Signing certificate does not match the permanent pin')
    badging = _one(reports_dir, 'badging.txt').read_text()
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'",
                        badging, re.M)
    if package is None or package.groups() != ('com.mishaqp.moru', version_code, version):
        raise ValueError('APK package/version does not match Moru pubspec')
    native = re.search(r'^native-code:(.*)$', badging, re.M)
    if native is None or re.findall(r"'([^']+)'", native[1]) != ['arm64-v8a']:
        raise ValueError('APK must contain only arm64-v8a')
    if "application-label:'Moru'" not in badging or 'application-debuggable' in badging:
        raise ValueError('APK must be a non-debuggable Moru release')
    filename = f'Moru-v{version}-arm64-v8a-release.apk'
    metadata = {
        'tag': f'v{version}', 'version': version, 'version_code': int(version_code),
        'package': 'com.mishaqp.moru', 'abi': 'arm64-v8a', 'commit': commit,
        'filename': filename, 'sha256': digest, 'size_bytes': apk.stat().st_size,
        'certificate_sha256': pin,
    }
    destination.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(apk, destination / filename)
    (destination / f'{filename}.sha256').write_text(f'{digest}  {filename}\n')
    (destination / 'release-metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk-dir', type=Path, required=True)
    parser.add_argument('--reports-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    try:
        metadata = prepare_release(Path.cwd(), args.apk_dir, args.reports_dir,
                                   args.output, args.commit)
    except (ValueError, OSError) as error:
        parser.exit(1, f'Release validation failed: {error}\n')
    print(json.dumps(metadata, indent=2))


if __name__ == '__main__':
    main()
