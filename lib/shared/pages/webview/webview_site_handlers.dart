import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../core/services/browser/browser_site_permissions.dart';

/// What a page's `<input type="file" accept=...>` lets the user pick.
@immutable
class FileChooserFilter {
  const FileChooserFilter(this.type, [this.extensions = const <String>[]]);

  final FileType type;

  /// Without the dot; only for [FileType.custom].
  final List<String> extensions;

  static FileChooserFilter fromAccept(List<String> acceptTypes) {
    final accept = <String>[
      for (final entry in acceptTypes)
        for (final part in entry.split(','))
          if (part.trim().isNotEmpty) part.trim().toLowerCase(),
    ];
    if (accept.isEmpty || accept.contains('*/*')) {
      return const FileChooserFilter(FileType.any);
    }
    bool all(String prefix) => accept.every((a) => a.startsWith(prefix));
    if (all('image/')) return const FileChooserFilter(FileType.image);
    if (all('video/')) return const FileChooserFilter(FileType.video);
    if (all('audio/')) return const FileChooserFilter(FileType.audio);
    if (accept.every((a) => a.startsWith('image/') || a.startsWith('video/'))) {
      return const FileChooserFilter(FileType.media);
    }
    if (accept.every((a) => a.startsWith('.') && a.length > 1)) {
      return FileChooserFilter(FileType.custom, [
        for (final a in accept) a.substring(1),
      ]);
    }
    return const FileChooserFilter(FileType.any);
  }

  @override
  bool operator ==(Object other) =>
      other is FileChooserFilter &&
      other.type == type &&
      listEquals(other.extensions, extensions);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(extensions));
}

/// Picks files for a page's file input: the camera when the page asks for a
/// photo capture, otherwise the system picker filtered by `accept`. Returns
/// `file://` URIs; empty when cancelled or when [visible] is false (the
/// model clicked a file input while nobody looks at the browser).
Future<List<String>> pickFilesForPage(
  FileSelectorParams params, {
  required bool visible,
}) async {
  if (!visible) return const <String>[];
  final filter = FileChooserFilter.fromAccept(params.acceptTypes);
  if (params.isCaptureEnabled && filter.type == FileType.image) {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera);
    return photo == null ? const <String>[] : [Uri.file(photo.path).toString()];
  }
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: params.mode == FileSelectorMode.openMultiple,
    type: filter.type,
    allowedExtensions: filter.type == FileType.custom
        ? filter.extensions
        : null,
  );
  return [
    for (final file in result?.files ?? const <PlatformFile>[])
      if (file.path != null) Uri.file(file.path!).toString(),
  ];
}

/// The kinds a web permission request asks for, as
/// [BrowserSitePermissions] names them. Unknown kinds make it empty, so
/// the request is denied.
Set<SitePermissionKind> sitePermissionKinds(
  Set<WebViewPermissionResourceType> types,
) {
  final kinds = <SitePermissionKind>{};
  for (final type in types) {
    switch (type.name) {
      case 'camera':
        kinds.add('camera');
      case 'microphone':
        kinds.add('microphone');
      case 'protectedMediaId':
        kinds.add('protected_media');
      default:
        return const <SitePermissionKind>{};
    }
  }
  return kinds;
}

/// A controller whose pages can ask for the camera, microphone and
/// location and open file inputs. [visible] says whether a browser page is
/// on screen now; it is read at every request, so a controller that moves
/// to the mini window stops granting anything.
WebViewController createSiteAwareController({
  required bool Function() visible,
}) {
  late final WebViewController controller;
  controller = WebViewController(
    onPermissionRequest: (request) async {
      final kinds = sitePermissionKinds(request.types);
      final allowed =
          visible() &&
          kinds.isNotEmpty &&
          await BrowserSitePermissions.instance.decide(
            await controller.currentUrl(),
            kinds,
          );
      await (allowed ? request.grant() : request.deny());
    },
  );
  final platform = controller.platform;
  if (platform is AndroidWebViewController) {
    platform
      ..setOnShowFileSelector(
        (params) => pickFilesForPage(params, visible: visible()),
      )
      ..setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async => GeolocationPermissionsResponse(
          allow:
              visible() &&
              await BrowserSitePermissions.instance.decide(request.origin, {
                'location',
              }),
          retain: false,
        ),
      );
  }
  return controller;
}
