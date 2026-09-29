import '../mcp/workspace_stdio_transport.dart';
import 'acp_connection.dart';

/// An agent process in the Linux environment, spoken to over its raw pipes
/// (the same newline-delimited JSON transport STDIO MCP servers use).
class AcpStdioChannel extends AcpChannel {
  AcpStdioChannel(this._transport);

  final WorkspaceStdioTransport _transport;

  @override
  Stream<dynamic> get messages => _transport.onMessage;

  @override
  Future<void> get closed => _transport.onClose;

  @override
  Future<void> send(Map<String, Object?> message) =>
      _transport.send(message).done;

  @override
  void close() => _transport.close();

  @override
  String describeError(Object error) => _transport.describeError(error);
}
