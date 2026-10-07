import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Opens the system save dialog and writes [bytes] to the chosen location.
///
/// Android requires [FilePicker.saveFile] `bytes` so the system SAF picker
/// can export without going through the share sheet.
Future<String?> saveBytesWithPicker({
  required String fileName,
  required List<int> bytes,
  String? dialogTitle,
}) async {
  final ext = p.extension(fileName).replaceFirst('.', '');
  final custom = ext.isNotEmpty;
  final payload = Uint8List.fromList(bytes);
  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: custom ? FileType.custom : FileType.any,
    allowedExtensions: custom ? <String>[ext] : null,
    bytes: payload,
  );
  if (savePath == null) return null;
  return savePath;
}

/// Reads [file] and saves a copy through [saveBytesWithPicker].
Future<String?> saveHostFileWithPicker({
  required File file,
  String? fileName,
  String? dialogTitle,
}) async {
  return saveBytesWithPicker(
    fileName: fileName ?? p.basename(file.path),
    bytes: await file.readAsBytes(),
    dialogTitle: dialogTitle,
  );
}
