import 'acp_agent_catalog.dart';

/// Loaded into every agent's Node process through `NODE_OPTIONS`.
///
/// Agents launch without PRoot's fake hard links (they leave dangling
/// symlinks behind atomic writes), and Android denies real hard links to
/// apps. Agents publish settings, sessions and skills with
/// `fs.promises.link(temporary, final)`; when that is denied, the fully
/// written temporary file is copied instead, which gives the same result
/// for a writer that removes the temporary afterwards. Other errors, and
/// every other call, are untouched. OmniBot ships the same fallback.
class AcpFsCompat {
  static const path = '$acpConfigDir/fs-compat.cjs';

  static const file = AcpConfigFile(path, r'''
'use strict';
const fs = require('node:fs');
const denied = (error) =>
  error && (error.code === 'EACCES' || error.code === 'EPERM');
const link = fs.promises.link.bind(fs.promises);
fs.promises.link = async (existingPath, newPath) => {
  try {
    return await link(existingPath, newPath);
  } catch (error) {
    if (!denied(error)) throw error;
    await fs.promises.copyFile(existingPath, newPath, fs.constants.COPYFILE_EXCL);
  }
};
const linkSync = fs.linkSync;
fs.linkSync = (existingPath, newPath) => {
  try {
    return linkSync(existingPath, newPath);
  } catch (error) {
    if (!denied(error)) throw error;
    fs.copyFileSync(existingPath, newPath, fs.constants.COPYFILE_EXCL);
  }
};
const linkCallback = fs.link;
fs.link = (existingPath, newPath, callback) =>
  linkCallback(existingPath, newPath, (error) => {
    if (!denied(error)) return callback(error);
    fs.copyFile(existingPath, newPath, fs.constants.COPYFILE_EXCL, callback);
  });
''');

  /// `NODE_OPTIONS` that loads the shim ahead of [existing] options.
  static String nodeOptions([String? existing]) {
    final own = '--require=$path';
    if (existing == null || existing.trim().isEmpty) return own;
    if (existing.contains(own)) return existing;
    return '$own $existing';
  }
}
