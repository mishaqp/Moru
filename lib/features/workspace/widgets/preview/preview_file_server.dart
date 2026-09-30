import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:Kelivo/core/services/workspace/workspace_file_access.dart';

/// Per-preview capability server. The original workspace grant and the captured
/// real page directory are intersected for every actual opened descriptor.
class PreviewFileServer {
  PreviewFileServer._(this._server, this._gate, this.uri);

  static const maxResourceBytes = 16 * 1024 * 1024;
  final HttpServer _server;
  final _PreviewSocketGate _gate;
  final Uri uri;
  Future<void>? _closing;

  static Future<PreviewFileServer> start({
    required File sourceFile,
    required String accessRoot,
  }) async {
    final granted = WorkspaceFileAccess(roots: [accessRoot]);
    final source = await granted.openRead(sourceFile.path);
    late final String realSource;
    try {
      // hostPath is the candidate before open; derive this boundary from the fd.
      realSource = await granted.resolve(source.path);
    } finally {
      await source.close();
    }
    final pageDirectory = p.dirname(realSource);
    final page = WorkspaceFileAccess(roots: [pageDirectory]);
    // Freeze both roots before any request or subsequent directory replacement.
    await page.resolve(pageDirectory);
    final random = Random.secure();
    final token = base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final gate = _PreviewSocketGate(socket, token);
    try {
      final server = HttpServer.listenOn(gate);
      final uri = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: socket.port,
        pathSegments: [token, p.basename(realSource)],
      );
      server.listen((request) async {
        // Dart pauses its parser at this first request. Always close, including
        // error paths, so a pipelined request cannot bypass the raw-line gate.
        request.response.persistentConnection = false;
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.headers.set('Referrer-Policy', 'no-referrer');
        request.response.headers.set('X-Content-Type-Options', 'nosniff');
        request.response.headers.set(
          'Content-Security-Policy',
          "default-src 'self' ${uri.origin} http: https: data: blob: 'unsafe-inline' 'unsafe-eval'; base-uri 'none'; object-src 'none'",
        );
        try {
          final parts = _resourceSegments(request.uri.path, token);
          if (parts == null ||
              request.headers.value('host') != '127.0.0.1:${socket.port}') {
            request.response.statusCode = HttpStatus.forbidden;
          } else if (request.method != 'GET' && request.method != 'HEAD') {
            request.response.statusCode = HttpStatus.methodNotAllowed;
          } else {
            final target = p.joinAll([pageDirectory, ...parts]);
            final opened = await page.openRead(target);
            try {
              // The second common guard checks the ACTUAL fd against the
              // original grant, not the pre-open candidate or a union of roots.
              await granted.resolve(opened.path);
              final length = await opened.handle.length();
              if (length > maxResourceBytes) {
                request.response.statusCode = HttpStatus.requestEntityTooLarge;
              } else {
                final bytes = request.method == 'HEAD'
                    ? null
                    : await _readResource(opened.handle);
                if (bytes != null && bytes.length > maxResourceBytes) {
                  request.response.statusCode =
                      HttpStatus.requestEntityTooLarge;
                } else {
                  request.response.headers.contentType = ContentType.parse(
                    _mimeForPath(target),
                  );
                  request.response.contentLength = bytes?.length ?? length;
                  if (bytes != null) request.response.add(bytes);
                }
              }
            } finally {
              await opened.close();
            }
          }
        } on WorkspaceFileAccessException {
          request.response.statusCode = HttpStatus.forbidden;
        } on FileSystemException {
          request.response.statusCode = HttpStatus.notFound;
        } catch (_) {
          request.response.statusCode = HttpStatus.internalServerError;
        } finally {
          try {
            await request.response.close();
          } catch (_) {}
        }
      });
      return PreviewFileServer._(server, gate, uri);
    } catch (_) {
      await gate.close();
      rethrow;
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    // listenOn does not own its supplied socket: close the bound listener too.
    await _gate.close();
    await _server.close(force: true);
    _gate.destroyConnections();
  }
}

Future<Uint8List> _readResource(RandomAccessFile file) async {
  final bytes = BytesBuilder(copy: false);
  while (bytes.length <= PreviewFileServer.maxResourceBytes) {
    final remaining = PreviewFileServer.maxResourceBytes + 1 - bytes.length;
    final chunk = await file.read(min(64 * 1024, remaining));
    if (chunk.isEmpty) break;
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

List<String>? _resourceSegments(String rawPath, String token) {
  if (!rawPath.startsWith('/') || rawPath.contains('\\')) return null;
  final raw = rawPath.split('/');
  if (raw.length < 3 || raw[1] != token) return null;
  final parts = <String>[];
  for (final segment in raw.skip(2)) {
    if (segment.isEmpty) return null;
    String decoded;
    try {
      decoded = Uri.decodeComponent(segment);
    } catch (_) {
      return null;
    }
    if (decoded == '.' ||
        decoded == '..' ||
        decoded.contains('/') ||
        decoded.contains('\\') ||
        decoded.contains('\u0000') ||
        RegExp(r'%(?:2e|2f|5c|00)', caseSensitive: false).hasMatch(decoded)) {
      return null;
    }
    parts.add(decoded);
  }
  return parts;
}

String _mimeForPath(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.html':
    case '.htm':
      return 'text/html; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    case '.js':
    case '.mjs':
      return 'text/javascript; charset=utf-8';
    case '.svg':
      return 'image/svg+xml';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.gif':
      return 'image/gif';
    case '.webp':
      return 'image/webp';
    case '.ico':
      return 'image/x-icon';
    case '.json':
      return 'application/json';
    case '.txt':
      return 'text/plain; charset=utf-8';
    case '.woff':
      return 'font/woff';
    case '.woff2':
      return 'font/woff2';
    default:
      return 'application/octet-stream';
  }
}

/// HttpRequest.uri has already normalized dot segments. Validate the original
/// first line before handing the unchanged valid stream to Dart's HTTP parser.
/// Invalid/oversized/slow lines become a token-missing request: ordinary HTTP
/// parsing and response handling still own the socket and return a generic 403.
class _PreviewSocketGate extends Stream<Socket> implements ServerSocket {
  _PreviewSocketGate(this._socket, this.token);
  final ServerSocket _socket;
  final String token;
  final Set<_PreviewSocket> _connections = {};
  @override
  InternetAddress get address => _socket.address;
  @override
  int get port => _socket.port;
  @override
  Future<ServerSocket> close() => _socket.close();
  void destroyConnections() {
    for (final socket in _connections.toList()) {
      socket.destroy();
    }
    _connections.clear();
  }

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _socket.listen(
    (socket) {
      late final _PreviewSocket wrapped;
      wrapped = _PreviewSocket(
        socket,
        token,
        () => _connections.remove(wrapped),
      );
      _connections.add(wrapped);
      onData?.call(wrapped);
    },
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class _PreviewSocket extends Stream<Uint8List> implements Socket {
  _PreviewSocket(this._socket, this._token, this._onClosed) {
    _input = StreamController<Uint8List>(
      sync: true,
      onListen: _listen,
      onPause: () => _subscription?.pause(),
      onResume: () => _subscription?.resume(),
      onCancel: () {
        _timer?.cancel();
        return _subscription?.cancel();
      },
    );
  }
  static const maxFirstLineBytes = 8 * 1024;
  final Socket _socket;
  final String _token;
  final void Function() _onClosed;
  late final StreamController<Uint8List> _input;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _timer;
  final BytesBuilder _pending = BytesBuilder(copy: false);
  bool _accepted = false;
  bool _denied = false;

  void _listen() {
    _timer = Timer(const Duration(seconds: 10), _deny);
    _subscription = _socket.listen(
      _receive,
      onError: (Object error, StackTrace stack) {
        _input.addError(error, stack);
      },
      onDone: () {
        _timer?.cancel();
        _onClosed();
        unawaited(_input.close());
      },
    );
  }

  void _receive(Uint8List bytes) {
    if (_denied) return;
    if (_accepted) {
      _input.add(bytes);
      return;
    }
    final end = bytes.indexOf(10);
    final prefixLength = end < 0 ? bytes.length : end + 1;
    if (_pending.length + prefixLength > maxFirstLineBytes) {
      _deny();
      return;
    }
    if (end < 0) {
      _pending.add(bytes);
      return;
    }
    final previous = _pending.takeBytes();
    final line = latin1.decode([...previous, ...bytes.take(end + 1)]);
    final match = RegExp(
      r'^([A-Z]+) ([^ ]+) HTTP/1\.[01]\r\n$',
    ).firstMatch(line);
    final target = match?.group(2);
    final path = target?.split('?').first;
    if (path == null || _resourceSegments(path, _token) == null) {
      _deny();
      return;
    }
    _accepted = true;
    _timer?.cancel();
    _input.add(
      previous.isEmpty ? bytes : Uint8List.fromList([...previous, ...bytes]),
    );
  }

  void _deny() {
    if (_accepted || _denied) return;
    _denied = true;
    _timer?.cancel();
    _pending.clear();
    _input.add(
      Uint8List.fromList(
        ascii.encode(
          'GET / HTTP/1.1\r\nHost: 127.0.0.1:${_socket.port}\r\nConnection: close\r\n\r\n',
        ),
      ),
    );
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _input.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  void destroy() {
    _timer?.cancel();
    _onClosed();
    _socket.destroy();
  }

  @override
  Encoding get encoding => _socket.encoding;
  @override
  set encoding(Encoding value) => _socket.encoding = value;
  @override
  InternetAddress get address => _socket.address;
  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;
  @override
  int get port => _socket.port;
  @override
  int get remotePort => _socket.remotePort;
  @override
  Future<dynamic> get done => _socket.done;
  @override
  Future<dynamic> close() => _socket.close();
  @override
  void add(List<int> data) => _socket.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);
  @override
  Future<void> flush() => _socket.flush();
  @override
  void write(Object? object) => _socket.write(object);
  @override
  void writeln([Object? object = '']) => _socket.writeln(object);
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);
  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);
  // Socket has SDK-private detach methods; previews never upgrade/detach HTTP.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Socket operation unavailable');
}
