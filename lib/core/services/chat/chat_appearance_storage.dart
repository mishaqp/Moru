import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../utils/app_directories.dart';
import '../../../utils/kelivo_file_uri.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../database/business_preferences.dart';
import '../../models/assistant.dart';
import '../../models/chat_appearance.dart';

/// Owns the original wallpaper media under the existing backed-up images root.
final class ChatAppearanceStorage {
  ChatAppearanceStorage._();

  static const preferenceKey = 'display_chat_appearance_v1';
  static const _folderName = 'chat_backgrounds';
  static const _filePrefix = 'chat_background_';
  static const _transferTimeout = Duration(seconds: 30);

  static Future<({String path, String reference})> copyMedia(
    String sourcePath,
    ChatBackgroundType type,
  ) async {
    if (type != ChatBackgroundType.image &&
        type != ChatBackgroundType.gif &&
        type != ChatBackgroundType.video) {
      throw ArgumentError.value(type, 'type');
    }
    final appData = await AppDirectories.getAppDataDirectory();
    final folder = Directory(p.join(appData.path, 'images', _folderName));
    await folder.create(recursive: true);
    final uri = Uri.tryParse(sourcePath);
    var extension = p.extension(uri?.path ?? sourcePath).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) {
      extension = switch (type) {
        ChatBackgroundType.gif => '.gif',
        ChatBackgroundType.video => '.mp4',
        _ => '.png',
      };
    }
    final target = File(
      p.join(folder.path, '$_filePrefix${const Uuid().v4()}$extension'),
    );
    try {
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        final client = HttpClient()..connectionTimeout = _transferTimeout;
        try {
          final request = await client.getUrl(uri).timeout(_transferTimeout);
          final response = await request.close().timeout(_transferTimeout);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw HttpException('chat_background_download', uri: uri);
          }
          await response.pipe(target.openWrite()).timeout(_transferTimeout);
        } finally {
          client.close(force: true);
        }
      } else if (uri != null && uri.scheme == 'data') {
        final data = uri.data;
        if (data == null) throw const FormatException('chat_background_data');
        await target.writeAsBytes(data.contentAsBytes(), flush: true);
      } else {
        final source = File(SandboxPathResolver.fix(sourcePath));
        await source.copy(target.path);
      }
      if (await target.length() == 0) {
        throw const FormatException('chat_background_empty');
      }
      final reference = KelivoFileUri.encodeFromAbsolute(
        target.path,
        root: appData.path,
      );
      if (reference == null) {
        throw const FormatException('chat_background_path');
      }
      return (path: target.path, reference: reference);
    } catch (_) {
      try {
        if (await target.exists()) await target.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// A missing key triggers exactly one migration of the saved current choice.
  /// A failed media copy leaves it missing so a later launch can retry.
  static Future<ChatAppearanceSettings?> migrateLegacy({
    required BusinessPreferences preferences,
    required double legacyMaskStrength,
  }) async {
    if (preferences.containsKey(preferenceKey)) return null;
    final assistants = _decodeAssistants(
      preferences.getString('assistants_v1'),
    );
    final currentId = preferences.get('current_assistant_id_v1');
    Assistant? current;
    for (final assistant in assistants) {
      if (assistant.id == currentId) {
        current = assistant;
        break;
      }
    }
    if (current == null && assistants.isNotEmpty) current = assistants.first;

    var background = ChatBackgroundSettings(maskStrength: legacyMaskStrength);
    if (current?.useGradientBackground ?? false) {
      background = background.copyWith(
        type: ChatBackgroundType.gradient,
        gradientAnimated: current!.gradientBackgroundAnimated,
        gradientPhase: current.gradientBackgroundPhase,
        gradientOffsetX: current.gradientBackgroundOffsetX,
        gradientOffsetY: current.gradientBackgroundOffsetY,
      );
    } else {
      final source = current?.background?.trim() ?? '';
      if (source.isNotEmpty) {
        final type =
            p.extension(Uri.tryParse(source)?.path ?? source).toLowerCase() ==
                '.gif'
            ? ChatBackgroundType.gif
            : ChatBackgroundType.image;
        try {
          final copied = await copyMedia(source, type);
          background = background.copyWith(type: type, path: copied.reference);
        } catch (_) {
          return null;
        }
      }
    }
    final result = ChatAppearanceSettings(light: background, dark: background);
    try {
      await preferences.setString(preferenceKey, jsonEncode(result.toJson()));
    } catch (_) {
      await removeIfOwned(background.path);
      rethrow;
    }
    return result;
  }

  static List<Assistant> _decodeAssistants(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return [
        for (final value in decoded)
          if (value is Map)
            Assistant.fromJson(Map<String, dynamic>.from(value)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Only deletes files created by this service, never the source/assistant asset.
  static Future<void> removeIfOwned(String? reference) async {
    if (reference == null) return;
    try {
      final segments = KelivoFileUri.decodeToSegments(reference);
      if (segments == null ||
          segments.length != 3 ||
          segments[0] != 'images' ||
          segments[1] != _folderName ||
          !segments[2].startsWith(_filePrefix)) {
        return;
      }
      final root = await AppDirectories.getAppDataDirectory();
      final folder = Directory(p.join(root.path, 'images', _folderName));
      final path = KelivoFileUri.resolveToAbsolute(reference, root: root.path)!;
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        return;
      }
      final realFolder = await folder.resolveSymbolicLinks();
      final file = File(path);
      if (!p.isWithin(realFolder, await file.resolveSymbolicLinks())) return;
      await file.delete();
    } catch (_) {}
  }
}
