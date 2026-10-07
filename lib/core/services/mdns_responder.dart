import 'dart:io';
import 'dart:typed_data';

/// What [MdnsResponder] announces: a host name (`<host>.local` -> the Wi-Fi
/// address) and, with an [httpPort], a DNS-SD web service, so the phone is
/// listed among the network's services and reached as `http://<host>.local`.
class MdnsZone {
  MdnsZone({
    required this.hostName,
    required this.address,
    this.httpPort,
    this.instanceName = 'Moru',
  });

  /// Without `.local`, e.g. `moru`.
  final String hostName;
  final InternetAddress address;
  final int? httpPort;

  /// Shown in service browsers.
  final String instanceName;

  static const String httpService = '_http._tcp.local';
  static const String servicesQuery = '_services._dns-sd._udp.local';

  String get host => '$hostName.local';
  String get instance => '$instanceName.$httpService';
}

/// Answers multicast DNS for a [MdnsZone]. Android needs a Wi-Fi multicast
/// lock while it runs.
class MdnsResponder {
  MdnsResponder(this.zone);

  static final InternetAddress group = InternetAddress('224.0.0.251');
  static const int port = 5353;
  static const int ttlSeconds = 120;

  static const int typeA = 1;
  static const int typePtr = 12;
  static const int typeTxt = 16;
  static const int typeSrv = 33;
  static const int typeAny = 255;

  final MdnsZone zone;
  RawDatagramSocket? _socket;

  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
      reusePort: true,
    );
    socket
      ..multicastLoopback = false
      ..joinMulticast(group);
    _socket = socket;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final reply = answer(datagram.data, zone);
      if (reply != null) socket.send(reply, group, port);
    });
    // Announce once, so caches learn the name right away.
    socket.send(announcement(zone), group, port);
  }

  /// Says goodbye (TTL 0) so browsers drop the service at once.
  void stop() {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    try {
      socket.send(announcement(zone, ttl: 0), group, port);
    } catch (_) {
      // The network may be gone already.
    }
    socket.close();
  }

  /// Everything the zone has, e.g. to announce it.
  static Uint8List announcement(MdnsZone zone, {int ttl = ttlSeconds}) =>
      _response(0, [
        if (zone.httpPort != null) ...[
          _ptr(MdnsZone.httpService, zone.instance, ttl),
          _srv(zone, ttl),
          _txt(zone, ttl),
        ],
        _a(zone, ttl),
      ], const []);

  /// The response to [query], or null when it asks for nothing the zone
  /// has.
  static Uint8List? answer(Uint8List query, MdnsZone zone) {
    if (query.length < 12) return null;
    final data = ByteData.sublistView(query);
    // Responses are not questions.
    if (data.getUint16(2) & 0x8000 != 0) return null;
    final count = data.getUint16(4);
    final answers = <_Record>[];
    final additional = <_Record>[];
    void add(List<_Record> list, _Record record) {
      if (!answers.any((r) => r.same(record)) &&
          !additional.any((r) => r.same(record))) {
        list.add(record);
      }
    }

    var offset = 12;
    for (var i = 0; i < count; i++) {
      final parsed = readName(query, offset);
      if (parsed == null || parsed.next + 4 > query.length) return null;
      offset = parsed.next;
      final type = data.getUint16(offset);
      offset += 4;
      final name = parsed.name.toLowerCase();
      bool asks(int wanted) => type == wanted || type == typeAny;
      if (name == zone.host.toLowerCase() && asks(typeA)) {
        add(answers, _a(zone, ttlSeconds));
      }
      if (zone.httpPort == null) continue;
      if (name == MdnsZone.servicesQuery && asks(typePtr)) {
        add(
          answers,
          _ptr(MdnsZone.servicesQuery, MdnsZone.httpService, ttlSeconds),
        );
      }
      if (name == MdnsZone.httpService && asks(typePtr)) {
        add(answers, _ptr(MdnsZone.httpService, zone.instance, ttlSeconds));
        add(additional, _srv(zone, ttlSeconds));
        add(additional, _txt(zone, ttlSeconds));
        add(additional, _a(zone, ttlSeconds));
      }
      if (name == zone.instance.toLowerCase()) {
        if (asks(typeSrv)) add(answers, _srv(zone, ttlSeconds));
        if (asks(typeTxt)) add(answers, _txt(zone, ttlSeconds));
        add(additional, _a(zone, ttlSeconds));
      }
    }
    if (answers.isEmpty) return null;
    // Anything answered directly is not repeated as additional.
    additional.removeWhere((r) => answers.any((a) => a.same(r)));
    return _response(data.getUint16(0), answers, additional);
  }

  /// A name at [offset], following compression pointers; null if damaged.
  static ({String name, int next})? readName(Uint8List bytes, int offset) {
    final labels = <String>[];
    var position = offset;
    int? next;
    for (var jumps = 0; jumps < 16; jumps++) {
      if (position >= bytes.length) return null;
      final length = bytes[position];
      if (length == 0) {
        return (name: labels.join('.'), next: next ?? position + 1);
      }
      if (length & 0xc0 == 0xc0) {
        if (position + 1 >= bytes.length) return null;
        next ??= position + 2;
        position = ((length & 0x3f) << 8) | bytes[position + 1];
        continue;
      }
      if (position + 1 + length > bytes.length) return null;
      labels.add(
        String.fromCharCodes(bytes, position + 1, position + 1 + length),
      );
      position += 1 + length;
      jumps = 0;
    }
    return null;
  }

  static Uint8List encodeName(String name) {
    final builder = BytesBuilder();
    for (final label in name.split('.')) {
      final bytes = label.codeUnits;
      builder
        ..addByte(bytes.length)
        ..add(bytes);
    }
    builder.addByte(0);
    return builder.toBytes();
  }

  static _Record _a(MdnsZone zone, int ttl) =>
      _Record(zone.host, typeA, true, ttl, zone.address.rawAddress);

  static _Record _ptr(String name, String target, int ttl) =>
      _Record(name, typePtr, false, ttl, encodeName(target));

  static _Record _srv(MdnsZone zone, int ttl) => _Record(
    zone.instance,
    typeSrv,
    true,
    ttl,
    Uint8List.fromList([
      ...(ByteData(6)..setUint16(4, zone.httpPort!)).buffer.asUint8List(),
      ...encodeName(zone.host),
    ]),
  );

  static _Record _txt(MdnsZone zone, int ttl) {
    const entry = 'path=/';
    return _Record(
      zone.instance,
      typeTxt,
      true,
      ttl,
      Uint8List.fromList([entry.length, ...entry.codeUnits]),
    );
  }

  static Uint8List _response(
    int id,
    List<_Record> answers,
    List<_Record> additional,
  ) {
    final builder = BytesBuilder()
      ..add(
        (ByteData(12)
              ..setUint16(0, id)
              ..setUint16(2, 0x8400)
              ..setUint16(6, answers.length)
              ..setUint16(10, additional.length))
            .buffer
            .asUint8List(),
      );
    for (final record in [...answers, ...additional]) {
      builder.add(record.encode());
    }
    return builder.toBytes();
  }
}

class _Record {
  _Record(this.name, this.type, this.unique, this.ttl, this.data);

  final String name;
  final int type;

  /// Unique records set the cache-flush bit; shared ones (PTR) do not.
  final bool unique;
  final int ttl;
  final Uint8List data;

  bool same(_Record other) =>
      other.type == type && other.name.toLowerCase() == name.toLowerCase();

  Uint8List encode() => Uint8List.fromList([
    ...MdnsResponder.encodeName(name),
    ...(ByteData(10)
          ..setUint16(0, type)
          ..setUint16(2, unique ? 0x8001 : 0x0001)
          ..setUint32(4, ttl)
          ..setUint16(8, data.length))
        .buffer
        .asUint8List(),
    ...data,
  ]);
}
