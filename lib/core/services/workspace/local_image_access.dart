import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/workspace_binding.dart';
import '../../providers/external_mounts_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../../utils/app_directories.dart';
import '../../../utils/sandbox_path_resolver.dart';
import 'workspace_file_access.dart';
import 'file_link_resolver.dart';

/// Model-written local image sources share the file tool's real-path/fd guard.
/// Only explicit artifact and workspace zones are roots; app data as a whole is
/// never exposed, since it also contains private settings and agent configs.
Future<Uint8List?> readLocalImageBytes(
  String source, {
  String? conversationId,
  WorkspaceBinding binding = const WorkspaceBinding(),
  WorkspaceProvider? workspaces,
  ExternalMountsProvider? externalMounts,
}) async {
  try {
    final workspacePath = KelivoLink.workspacePathSource(source);
    if (workspacePath.isWorkspacePath && workspacePath.link == null) {
      return null;
    }
    final roots = <_ImageRoot>[
      _ImageRoot(Directory.systemTemp.path, guest: '/tmp'),
    ];
    String? appRoot;
    try {
      appRoot = (await AppDirectories.getAppDataDirectory()).path;
    } catch (_) {
      // A missing app-directory plugin cannot widen the allowed roots.
    }
    if (appRoot != null) {
      roots.addAll([
        _ImageRoot(p.join(appRoot, 'upload')),
        _ImageRoot(p.join(appRoot, 'images')),
        _ImageRoot(p.join(appRoot, 'skills'), guest: '/skills'),
      ]);
    }
    if (appRoot != null &&
        conversationId != null &&
        conversationId.isNotEmpty &&
        p.basename(conversationId) == conversationId &&
        conversationId != '.' &&
        conversationId != '..') {
      roots.add(
        _ImageRoot(p.join(appRoot, 'sessions', conversationId), guest: '/chat'),
      );
    }
    if (binding.isBound && workspaces != null) {
      await workspaces.loaded;
      final workspace = workspaces.byId(binding.workspaceId!);
      if (workspace != null) {
        roots.add(
          _ImageRoot(
            await workspaces.hostRootFor(workspace),
            guest: '/workspace',
          ),
        );
      }
    }
    if (externalMounts != null) {
      for (final mount in await externalMounts.resolveMounts()) {
        roots.add(_ImageRoot(mount.host, guest: mount.guest));
      }
    }

    // Preserve explicit host grants and ACP workspace paths before the legacy
    // artifact remapper can replace them with an unrelated same-name image.
    var hostPath = source;
    if (source.toLowerCase().startsWith('file:')) {
      final decoded = SandboxPathResolver.tryDecodeLocalFileUri(source);
      if (decoded == null) return null;
      hostPath = decoded;
    }
    var matched = p.isAbsolute(hostPath)
        ? roots.where((root) => _inside(root.host, hostPath)).toList()
        : <_ImageRoot>[];
    if (matched.isEmpty && workspacePath.isWorkspacePath) {
      final workspaceRoot = roots
          .where((root) => root.guest == '/workspace')
          .firstOrNull;
      if (workspaceRoot == null || workspacePath.link == null) return null;
      hostPath = p.join(
        workspaceRoot.host,
        KelivoLink.tryParse(workspacePath.link!)!.relativePath,
      );
    } else if (matched.isEmpty) {
      hostPath = SandboxPathResolver.fix(source);
    }
    if (!p.isAbsolute(hostPath)) return null;
    hostPath = p.normalize(hostPath);
    matched = roots.where((root) => _inside(root.host, hostPath)).toList();
    final guestRoot =
        roots
            .where(
              (root) => root.guest != null && _inside(root.guest!, hostPath),
            )
            .toList()
          ..sort((a, b) => b.guest!.length.compareTo(a.guest!.length));
    if (matched.isEmpty && guestRoot.isNotEmpty) {
      final root = guestRoot.first;
      hostPath = p.join(root.host, p.relative(hostPath, from: root.guest!));
    }
    matched = roots.where((root) => _inside(root.host, hostPath)).toList()
      ..sort((a, b) => b.host.length.compareTo(a.host.length));
    if (matched.isEmpty) return null;
    // Keep the selected zone as the boundary. A workspace link cannot escape
    // into another allowed zone, and a broad tmp ancestor cannot widen a more
    // specific artifact/workspace root.
    return await WorkspaceFileAccess(
      roots: [matched.first.host],
    ).readBytes(hostPath);
  } catch (_) {
    return null;
  }
}

bool _inside(String root, String candidate) =>
    p.equals(root, candidate) || p.isWithin(root, candidate);

class _ImageRoot {
  _ImageRoot(String host, {this.guest}) : host = p.canonicalize(host);
  final String host;
  final String? guest;
}
