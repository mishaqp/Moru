#!/usr/bin/env python3
"""Check that R8 kept what reflection in a release APK needs.

flutter_local_notifications stores scheduled notifications as Gson JSON and
reads them back through anonymous TypeToken subclasses such as
`new TypeToken<ArrayList<NotificationDetails>>() {}`. Gson takes the type
from the subclass's generic signature; when R8 drops it, scheduling,
cancelling and rescheduling after reboot fail with "Missing type parameter"
(Moru 0.1.35). Debug builds are not shrunk, so only a release APK shows it.

Usage: verify_release_keep_rules.py APK
"""

from __future__ import annotations

import struct
import sys
import zipfile

SIGNATURE = 'Ldalvik/annotation/Signature;'
PLUGIN = 'Lcom/dexterous/flutterlocalnotifications/'
DETAILS = 'NotificationDetails'


def _uleb(data: bytes, pos: int) -> tuple[int, int]:
    result = shift = 0
    while True:
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if byte < 0x80:
            return result, pos
        shift += 7


class Dex:
    """Just enough of the dex format to read classes and their signatures."""

    def __init__(self, data: bytes):
        if not data.startswith(b'dex\n'):
            raise ValueError('not a dex file')
        self.data = data
        (
            self._string_count,
            self._string_off,
            self._type_count,
            self._type_off,
        ) = struct.unpack_from('<IIII', data, 0x38)
        self._class_count, self._class_off = struct.unpack_from('<II', data, 0x60)

    def string(self, index: int) -> str:
        (offset,) = struct.unpack_from('<I', self.data, self._string_off + 4 * index)
        _, pos = _uleb(self.data, offset)
        end = self.data.index(b'\0', pos)
        return self.data[pos:end].decode('utf-8', errors='replace')

    def type_name(self, index: int) -> str:
        (string_index,) = struct.unpack_from('<I', self.data, self._type_off + 4 * index)
        return self.string(string_index)

    def classes(self):
        """Yields (name, superclass or None, signature or None)."""
        for i in range(self._class_count):
            base = self._class_off + 32 * i
            class_idx, _, super_idx, _, _, annotations_off = struct.unpack_from(
                '<IIIIII', self.data, base
            )
            superclass = None if super_idx == 0xFFFFFFFF else self.type_name(super_idx)
            yield self.type_name(class_idx), superclass, self._signature(annotations_off)

    def _signature(self, directory_off: int) -> str | None:
        if directory_off == 0:
            return None
        (set_off,) = struct.unpack_from('<I', self.data, directory_off)
        if set_off == 0:
            return None
        (size,) = struct.unpack_from('<I', self.data, set_off)
        for k in range(size):
            (item_off,) = struct.unpack_from('<I', self.data, set_off + 4 + 4 * k)
            pos = item_off + 1  # visibility
            type_idx, pos = _uleb(self.data, pos)
            if self.type_name(type_idx) != SIGNATURE:
                continue
            count, pos = _uleb(self.data, pos)
            for _ in range(count):
                _, pos = _uleb(self.data, pos)  # element name ("value")
                return ''.join(self._string_array(pos))
        return None

    def _string_array(self, pos: int) -> list[str]:
        header = self.data[pos]
        if header & 0x1F != 0x1C:  # VALUE_ARRAY
            raise ValueError('Signature value is not an array')
        size, pos = _uleb(self.data, pos + 1)
        parts = []
        for _ in range(size):
            header = self.data[pos]
            if header & 0x1F != 0x17:  # VALUE_STRING
                raise ValueError('Signature part is not a string')
            width = (header >> 5) + 1
            index = int.from_bytes(self.data[pos + 1:pos + 1 + width], 'little')
            parts.append(self.string(index))
            pos += 1 + width
        return parts


def check(apk_path: str) -> list[str]:
    """Problems found in the APK; empty when it is fine."""
    classes = []
    with zipfile.ZipFile(apk_path) as apk:
        for name in sorted(apk.namelist()):
            if name.startswith('classes') and name.endswith('.dex'):
                classes.extend(Dex(apk.read(name)).classes())

    # The TypeToken class, whatever R8 renamed it to: the superclass of the
    # plugin classes whose signature names NotificationDetails.
    tokens = {
        superclass
        for name, superclass, signature in classes
        if name.startswith(PLUGIN) and signature and DETAILS in signature
    }
    if not tokens:
        return [
            'No flutter_local_notifications class keeps a generic signature '
            'with NotificationDetails; Gson would fail with "Missing type '
            'parameter". Check the Gson rules in android/app/proguard-rules.pro.'
        ]
    return [
        f'{name} extends a TypeToken but lost its generic signature.'
        for name, superclass, signature in classes
        if name.startswith(PLUGIN) and superclass in tokens and not signature
    ]


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    problems = check(argv[1])
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        return 1
    print('Release keep rules: Gson TypeToken signatures are present.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
