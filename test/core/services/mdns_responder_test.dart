import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/mdns_responder.dart';

/// A query for [name] with [type] (1 = A, 28 = AAAA, 255 = ANY).
Uint8List _query(String name, {int type = 1, int id = 0}) {
  final builder = BytesBuilder()
    ..add(
      (ByteData(12)
            ..setUint16(0, id)
            ..setUint16(4, 1))
          .buffer
          .asUint8List(),
    );
  for (final label in name.split('.')) {
    builder
      ..addByte(label.length)
      ..add(label.codeUnits);
  }
  builder
    ..addByte(0)
    ..add(
      (ByteData(4)
            ..setUint16(0, type)
            ..setUint16(2, 1))
          .buffer
          .asUint8List(),
    );
  return builder.toBytes();
}

void main() {
  final address = InternetAddress('192.168.1.23');

  test('a question for the name gets its address', () {
    final reply = MdnsResponder.answer(
      _query('MORU.local', id: 5),
      'moru.local',
      address,
    )!;
    final data = ByteData.sublistView(reply);
    expect(data.getUint16(0), 5);
    expect(data.getUint16(2), 0x8400);
    expect(data.getUint16(6), 1);
    expect(MdnsResponder.readName(reply, 12)!.name, 'moru.local');
    // The address closes the record.
    expect(reply.sublist(reply.length - 4), [192, 168, 1, 23]);
    expect(
      MdnsResponder.answer(
        _query('moru.local', type: 255),
        'moru.local',
        address,
      ),
      isNotNull,
    );
  });

  test('other names, types, responses and junk are ignored', () {
    expect(
      MdnsResponder.answer(_query('other.local'), 'moru.local', address),
      isNull,
    );
    expect(
      MdnsResponder.answer(
        _query('moru.local', type: 28),
        'moru.local',
        address,
      ),
      isNull,
    );
    final response = MdnsResponder.record('moru.local', address);
    expect(MdnsResponder.answer(response, 'moru.local', address), isNull);
    expect(MdnsResponder.answer(Uint8List(5), 'moru.local', address), isNull);
    final cut = _query('moru.local');
    expect(
      MdnsResponder.answer(
        cut.sublist(0, cut.length - 3),
        'moru.local',
        address,
      ),
      isNull,
    );
  });

  test('compressed names are followed, loops are not', () {
    // "local" at 12, then "moru" + pointer to 12.
    final bytes = Uint8List.fromList([
      ...List.filled(12, 0),
      5,
      ...'local'.codeUnits,
      0,
      4,
      ...'moru'.codeUnits,
      0xc0,
      12,
    ]);
    final name = MdnsResponder.readName(bytes, 19)!;
    expect(name.name, 'moru.local');
    expect(name.next, bytes.length);
    final loop = Uint8List.fromList([...List.filled(12, 0), 0xc0, 12]);
    expect(MdnsResponder.readName(loop, 12), isNull);
  });
}
