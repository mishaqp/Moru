import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/mdns_responder.dart';

/// A query for [name] with [type] (1 A, 12 PTR, 16 TXT, 28 AAAA, 33 SRV,
/// 255 ANY).
Uint8List _query(String name, {int type = 1, int id = 0}) {
  final builder = BytesBuilder()
    ..add(
      (ByteData(12)
            ..setUint16(0, id)
            ..setUint16(4, 1))
          .buffer
          .asUint8List(),
    )
    ..add(MdnsResponder.encodeName(name))
    ..add(
      (ByteData(4)
            ..setUint16(0, type)
            ..setUint16(2, 1))
          .buffer
          .asUint8List(),
    );
  return builder.toBytes();
}

/// Name and type of every record in [reply].
List<(String, int)> _records(Uint8List reply) {
  final data = ByteData.sublistView(reply);
  final count = data.getUint16(6) + data.getUint16(10);
  final records = <(String, int)>[];
  var offset = 12;
  for (var i = 0; i < count; i++) {
    final name = MdnsResponder.readName(reply, offset)!;
    final type = data.getUint16(name.next);
    final length = data.getUint16(name.next + 8);
    records.add((name.name, type));
    offset = name.next + 10 + length;
  }
  expect(offset, reply.length);
  return records;
}

void main() {
  final zone = MdnsZone(
    hostName: 'moru',
    address: InternetAddress('192.168.1.23'),
    httpPort: 8080,
  );

  test('a question for the host gets its address', () {
    final reply = MdnsResponder.answer(_query('MORU.local', id: 5), zone)!;
    final data = ByteData.sublistView(reply);
    expect(data.getUint16(0), 5);
    expect(data.getUint16(2), 0x8400);
    expect(_records(reply), [('moru.local', MdnsResponder.typeA)]);
    expect(reply.sublist(reply.length - 4), [192, 168, 1, 23]);
    expect(
      MdnsResponder.answer(_query('moru.local', type: 255), zone),
      isNotNull,
    );
  });

  test('service browsers find the web server with its port', () {
    final browse = MdnsResponder.answer(
      _query(MdnsZone.httpService, type: MdnsResponder.typePtr),
      zone,
    )!;
    expect(_records(browse), [
      (MdnsZone.httpService, MdnsResponder.typePtr),
      ('Moru._http._tcp.local', MdnsResponder.typeSrv),
      ('Moru._http._tcp.local', MdnsResponder.typeTxt),
      ('moru.local', MdnsResponder.typeA),
    ]);
    // The SRV record carries the port.
    final srv = Uint8List.fromList([
      ...(ByteData(6)..setUint16(4, 8080)).buffer.asUint8List(),
      ...MdnsResponder.encodeName('moru.local'),
    ]);
    expect(_contains(browse, srv), isTrue);

    final types = MdnsResponder.answer(
      _query(MdnsZone.servicesQuery, type: MdnsResponder.typePtr),
      zone,
    )!;
    expect(_records(types), [(MdnsZone.servicesQuery, MdnsResponder.typePtr)]);
    final instance = MdnsResponder.answer(
      _query('Moru._http._tcp.local', type: 255),
      zone,
    )!;
    expect(_records(instance), [
      ('Moru._http._tcp.local', MdnsResponder.typeSrv),
      ('Moru._http._tcp.local', MdnsResponder.typeTxt),
      ('moru.local', MdnsResponder.typeA),
    ]);
  });

  test('without a port only the host name is announced', () {
    final hostOnly = MdnsZone(hostName: 'moru', address: zone.address);
    expect(
      MdnsResponder.answer(
        _query(MdnsZone.httpService, type: MdnsResponder.typePtr),
        hostOnly,
      ),
      isNull,
    );
    expect(_records(MdnsResponder.announcement(hostOnly)), [
      ('moru.local', MdnsResponder.typeA),
    ]);
    expect(_records(MdnsResponder.announcement(zone)), hasLength(4));
  });

  test('other names, types, responses and junk are ignored', () {
    expect(MdnsResponder.answer(_query('other.local'), zone), isNull);
    expect(MdnsResponder.answer(_query('moru.local', type: 28), zone), isNull);
    expect(
      MdnsResponder.answer(MdnsResponder.announcement(zone), zone),
      isNull,
    );
    expect(MdnsResponder.answer(Uint8List(5), zone), isNull);
    final cut = _query('moru.local');
    expect(MdnsResponder.answer(cut.sublist(0, cut.length - 3), zone), isNull);
  });

  test('compressed names are followed, loops are not', () {
    // "local" at 12, then "moru" + pointer to 12.
    final bytes = Uint8List.fromList([
      ...List.filled(12, 0),
      5, ...'local'.codeUnits, 0, //
      4, ...'moru'.codeUnits, 0xc0, 12,
    ]);
    final name = MdnsResponder.readName(bytes, 19)!;
    expect(name.name, 'moru.local');
    expect(name.next, bytes.length);
    final loop = Uint8List.fromList([...List.filled(12, 0), 0xc0, 12]);
    expect(MdnsResponder.readName(loop, 12), isNull);
  });
}

bool _contains(Uint8List haystack, Uint8List needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length && match; j++) {
      match = haystack[i + j] == needle[j];
    }
    if (match) return true;
  }
  return false;
}
