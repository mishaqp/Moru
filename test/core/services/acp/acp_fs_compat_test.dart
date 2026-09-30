import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/acp/acp_fs_compat.dart';

void main() {
  test('NODE_OPTIONS loads the shim first and only once', () {
    final own = '--require=${AcpFsCompat.path}';
    expect(AcpFsCompat.nodeOptions(), own);
    expect(AcpFsCompat.nodeOptions('  '), own);
    expect(
      AcpFsCompat.nodeOptions('--max-old-space-size=512'),
      '$own --max-old-space-size=512',
    );
    expect(AcpFsCompat.nodeOptions(own), own);
  });

  test(
    'a denied hard link becomes a copy; other link errors stay errors',
    () async {
      final node = Process.runSync('sh', ['-c', 'command -v node']);
      if (node.exitCode != 0) {
        fail('node is needed on PATH to run the agent shim');
      }
      final dir = await Directory.systemTemp.createTemp('moru-fs-compat');
      addTearDown(() => dir.delete(recursive: true));
      final shim = File('${dir.path}/fs-compat.cjs')
        ..writeAsStringSync(AcpFsCompat.file.content);
      // Android denies link(2) to apps; model that before the shim loads.
      final deny = File('${dir.path}/deny.cjs')
        ..writeAsStringSync(r'''
const fs = require('node:fs');
const eacces = () => Object.assign(new Error('denied'), {code: 'EACCES'});
fs.promises.link = async () => { throw eacces(); };
fs.linkSync = () => { throw eacces(); };
fs.link = (a, b, callback) => process.nextTick(callback, eacces());
''');
      final script = File('${dir.path}/publish.cjs')
        ..writeAsStringSync(r'''
const fs = require('node:fs');
const dir = process.argv[2];
(async () => {
  // An agent's atomic publish: write a temporary, link it in, remove it.
  fs.writeFileSync(`${dir}/settings.tmp`, 'saved');
  await fs.promises.link(`${dir}/settings.tmp`, `${dir}/settings.json`);
  fs.unlinkSync(`${dir}/settings.tmp`);
  fs.writeFileSync(`${dir}/a.tmp`, 'sync');
  fs.linkSync(`${dir}/a.tmp`, `${dir}/a.json`);
  fs.writeFileSync(`${dir}/b.tmp`, 'callback');
  await new Promise((resolve, reject) =>
    fs.link(`${dir}/b.tmp`, `${dir}/b.json`, (e) => (e ? reject(e) : resolve())));
  // An existing target is still an error, as with a real link.
  try {
    await fs.promises.link(`${dir}/a.tmp`, `${dir}/a.json`);
    console.log('overwrote');
  } catch (error) {
    console.log(error.code);
  }
  console.log(fs.readFileSync(`${dir}/settings.json`, 'utf8'));
  console.log(fs.lstatSync(`${dir}/settings.json`).isSymbolicLink());
})();
''');
      final result = await Process.run('node', [
        '--require=${deny.path}',
        '--require=${shim.path}',
        script.path,
        dir.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect((result.stdout as String).trim().split('\n'), [
        'EEXIST',
        'saved',
        'false',
      ]);
      expect(File('${dir.path}/a.json').readAsStringSync(), 'sync');
      expect(File('${dir.path}/b.json').readAsStringSync(), 'callback');
    },
    testOn: 'linux || mac-os',
  );
}
