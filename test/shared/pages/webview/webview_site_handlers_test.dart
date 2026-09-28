import 'package:Kelivo/shared/pages/webview/webview_site_handlers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  test('accept attributes pick the matching file picker filter', () {
    FileChooserFilter f(List<String> accept) =>
        FileChooserFilter.fromAccept(accept);
    expect(f(const []), const FileChooserFilter(FileType.any));
    expect(f(const ['image/*']), const FileChooserFilter(FileType.image));
    expect(
      f(const ['image/png, image/jpeg']),
      const FileChooserFilter(FileType.image),
    );
    expect(f(const ['video/mp4']), const FileChooserFilter(FileType.video));
    expect(f(const ['audio/*']), const FileChooserFilter(FileType.audio));
    expect(
      f(const ['image/*', 'video/*']),
      const FileChooserFilter(FileType.media),
    );
    expect(
      f(const ['.PDF,.docx']),
      const FileChooserFilter(FileType.custom, ['pdf', 'docx']),
    );
    expect(
      f(const ['.pdf', 'application/pdf']),
      const FileChooserFilter(FileType.any),
    );
    expect(f(const ['*/*']), const FileChooserFilter(FileType.any));
  });

  test('web permission types map to site permission kinds', () {
    expect(
      sitePermissionKinds({
        WebViewPermissionResourceType.camera,
        WebViewPermissionResourceType.microphone,
      }),
      {'camera', 'microphone'},
    );
  });
}
