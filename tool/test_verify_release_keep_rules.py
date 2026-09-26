import os
import struct
import tempfile
import unittest
import zipfile

from verify_release_keep_rules import check

PLUGIN = 'Lcom/dexterous/flutterlocalnotifications/'
TOKEN = 'Lcom/google/gson/reflect/a;'


def _uleb(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def build_dex(classes):
    """A minimal dex with [classes] as (name, superclass, signature parts)."""
    strings = sorted(
        {'Ldalvik/annotation/Signature;', 'value'}
        | {name for name, _, _ in classes}
        | {sup for _, sup, _ in classes}
        | {part for _, _, parts in classes for part in parts or []}
    )
    types = sorted(
        {'Ldalvik/annotation/Signature;'}
        | {name for name, _, _ in classes}
        | {sup for _, sup, _ in classes}
    )
    s_index = {s: i for i, s in enumerate(strings)}
    t_index = {t: i for i, t in enumerate(types)}

    string_ids_off = 0x70
    type_ids_off = string_ids_off + 4 * len(strings)
    class_defs_off = type_ids_off + 4 * len(types)
    data = bytearray()
    data_off = class_defs_off + 32 * len(classes)

    def here():
        return data_off + len(data)

    def align():
        while here() % 4:
            data.append(0)

    string_offs = []
    for s in strings:
        string_offs.append(here())
        data.extend(_uleb(len(s)) + s.encode() + b'\0')

    directory_offs = []
    for _, _, parts in classes:
        if parts is None:
            directory_offs.append(0)
            continue
        item_off = here()
        data.append(0x02)
        data.extend(_uleb(t_index['Ldalvik/annotation/Signature;']))
        data.extend(_uleb(1) + _uleb(s_index['value']))
        data.append(0x1C)
        data.extend(_uleb(len(parts)))
        for part in parts:
            data.append(0x17 | (3 << 5))
            data.extend(struct.pack('<I', s_index[part]))
        align()
        set_off = here()
        data.extend(struct.pack('<II', 1, item_off))
        directory_offs.append(here())
        data.extend(struct.pack('<IIII', set_off, 0, 0, 0))

    header = bytearray(0x70)
    header[0:8] = b'dex\n035\0'
    struct.pack_into('<IIII', header, 0x38, len(strings), string_ids_off,
                     len(types), type_ids_off)
    struct.pack_into('<II', header, 0x60, len(classes), class_defs_off)
    body = bytearray()
    for off in string_offs:
        body.extend(struct.pack('<I', off))
    for t in types:
        body.extend(struct.pack('<I', s_index[t]))
    for (name, sup, _), directory in zip(classes, directory_offs):
        body.extend(struct.pack('<IIIIIIII', t_index[name], 1, t_index[sup],
                                0, 0xFFFFFFFF, directory, 0, 0))
    return bytes(header + body + data)


class VerifyReleaseKeepRulesTest(unittest.TestCase):
    def apk(self, classes):
        handle, path = tempfile.mkstemp(suffix='.apk')
        os.close(handle)
        self.addCleanup(os.remove, path)
        with zipfile.ZipFile(path, 'w') as apk:
            apk.writestr('classes.dex', build_dex(classes))
            apk.writestr('classes2.dex', build_dex([
                ('Lj$/time/Instant;', 'Ljava/lang/Object;', None),
            ]))
        return path

    def test_kept_signatures_pass(self):
        self.assertEqual(check(self.apk([
            (PLUGIN + 'FlutterLocalNotificationsPlugin$1;', TOKEN,
             [TOKEN[:-1] + '<', 'Ljava/util/ArrayList<',
              PLUGIN + 'models/NotificationDetails;', '>;>;']),
            (PLUGIN + 'ScheduledNotificationReceiver$1;', TOKEN,
             [TOKEN[:-1] + '<', PLUGIN + 'models/NotificationDetails;', '>;']),
            (PLUGIN + 'models/NotificationDetails;', 'Ljava/lang/Object;', None),
        ])), [])

    def test_stripped_signatures_fail(self):
        # What R8 produced for 0.1.35: obfuscated names and no signatures.
        problems = check(self.apk([
            (PLUGIN + 'b;', 'Ld3/a;', None),
            (PLUGIN + 'models/NotificationDetails;', 'Ljava/lang/Object;', None),
        ]))
        self.assertEqual(len(problems), 1)
        self.assertIn('Missing type parameter', problems[0])

    def test_one_lost_signature_is_named(self):
        problems = check(self.apk([
            (PLUGIN + 'FlutterLocalNotificationsPlugin$1;', TOKEN,
             [TOKEN[:-1] + '<', PLUGIN + 'models/NotificationDetails;', '>;']),
            (PLUGIN + 'ScheduledNotificationReceiver$1;', TOKEN, None),
        ]))
        self.assertEqual(problems, [
            PLUGIN + 'ScheduledNotificationReceiver$1; extends a TypeToken '
            'but lost its generic signature.',
        ])


if __name__ == '__main__':
    unittest.main()
