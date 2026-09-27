import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Answers multicast DNS questions for one host name, e.g. `moru.local`, with
/// this device's Wi-Fi address, so other devices in the network can open
/// `http://moru.local:<port>` without knowing the IP. Android needs a Wi-Fi
/// multicast lock while it runs.
class MdnsResponder {
  MdnsResponder({required this.hostName, required this.address});

  static final InternetAddress group = InternetAddress('224.0.0.251');
  static const int port = 5353;
  static const int ttlSeconds = 120;

  /// Without the `.local` suffix, e.g. `moru`.
  final String hostName;
  final InternetAddress address;
  RawDatagramSocket? _socket;

  String get fqdn => '$hostName.local';

  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
      reusePort: !Platform.isWindows,
    );
    socket
      ..multicastLoopback = false
      ..joinMulticast(group);
    _socket = socket;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final reply = answer(datagram.data, fqdn, address);
      if (reply != null) socket.send(reply, group, port);
    });
    // Announce once, so caches learn the name right away.
    socket.send(record(fqdn, address, id: 0), group, port);
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }

  /// The response to [query], or null when it does not ask for [name]'s
  /// IPv4 address.
  static Uint8List? answer(
    Uint8List query,
    String name,
    InternetAddress address,
  ) {
    if (query.length < 12) return null;
    final data = ByteData.sublistView(query);
    // Responses are not questions.
    if (data.getUint16(2) & 0x8000 != 0) return null;
    final count = data.getUint16(4);
    var offset = 12;
    for (var i = 0; i < count; i++) {
      final parsed = readName(query, offset);
      if (parsed == null || parsed.next + 4 > query.length) return null;
      offset = parsed.next;
      final type = data.getUint16(offset);
      offset += 4;
      // A or ANY.
      if ((type == 1 || type == 255) &&
          parsed.name.toLowerCase() == name.toLowerCase()) {
        return record(name, address, id: data.getUint16(0));
      }
    }
    return null;
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

  /// An authoritative answer with the A record of [name].
  static Uint8List record(String name, InternetAddress address, {int id = 0}) {
    final builder = BytesBuilder();
    final header = ByteData(12)
      ..setUint16(0, id)
      ..setUint16(2, 0x8400)
      ..setUint16(6, 1);
    builder.add(header.buffer.asUint8List());
    for (final label in name.split('.')) {
      final bytes = label.codeUnits;
      builder
        ..addByte(bytes.length)
        ..add(bytes);
    }
    builder.addByte(0);
    final tail = ByteData(10)
      ..setUint16(0, 1) // A
      ..setUint16(2, 0x8001) // IN, cache flush
      ..setUint32(4, ttlSeconds)
      ..setUint16(8, 4);
    builder
      ..add(tail.buffer.asUint8List())
      ..add(address.rawAddress);
    return builder.toBytes();
  }
}
