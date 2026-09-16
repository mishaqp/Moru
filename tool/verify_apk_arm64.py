"""Check actual APK native contents; a filename containing v8a is not evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

REQUIRED = {
    'libflutter.so', 'libtermux_pty.so', 'libproot_exec.so',
    'libproot_loader.so', 'libtalloc.so', 'libandroid-shmem.so',
}


def inspect_apk(path: Path) -> dict:
    with zipfile.ZipFile(path) as apk:
        entries = apk.infolist()
        names = [entry.filename for entry in entries]
        if len(names) != len(set(names)):
            raise ValueError('Duplicate APK entries are not accepted')
        native = [entry for entry in entries
                  if entry.filename.startswith('lib/') and not entry.is_dir()]
        abis = {entry.filename.split('/')[1] for entry in native}
        if abis != {'arm64-v8a'}:
            raise ValueError(f'Expected only arm64-v8a native code, found {sorted(abis)}')
        libraries = set()
        for entry in native:
            parts = entry.filename.split('/')
            if len(parts) != 3 or not parts[2].endswith('.so'):
                raise ValueError(f'Unexpected native entry: {entry.filename}')
            with apk.open(entry) as library:
                header = library.read(20)
            if len(header) < 20 or header[:4] != b'\x7fELF' or header[4] != 2 or header[5] != 1:
                raise ValueError(f'Not a 64-bit little-endian ELF: {entry.filename}')
            if struct.unpack_from('<H', header, 18)[0] != 183:
                raise ValueError(f'Not an AArch64 ELF: {entry.filename}')
            libraries.add(parts[2])
        missing = REQUIRED - libraries
        if missing:
            raise ValueError(f'Missing Android runtime libraries: {sorted(missing)}')
        if 'AndroidManifest.xml' not in names:
            raise ValueError('AndroidManifest.xml is missing')
    with path.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    return {'file': path.name, 'abis': sorted(abis), 'native_libraries': sorted(libraries),
            'sha256': digest, 'bytes': path.stat().st_size}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(inspect_apk(args.apk), indent=2))
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f'APK verification failed: {error}\n')


if __name__ == '__main__':
    main()
