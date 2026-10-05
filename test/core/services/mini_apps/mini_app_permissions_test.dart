import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/mini_apps/mini_app_permissions.dart';
import 'package:Kelivo/core/services/mini_apps/mini_app_store.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late Directory root;
  late MiniAppStore store;
  late MiniAppPermissions permissions;
  var version = 0;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mini-app-grants-');
    root = Directory(p.join(temp.path, 'apps'));
    store = MiniAppStore(
      root: () async => root,
      now: () => DateTime(2026, 1, 1, 0, 0, version++),
    );
    permissions = MiniAppPermissions(store);
  });
  tearDown(() async {
    permissions.dispose();
    await temp.delete(recursive: true);
  });
  Future<MiniApp> install(List<String> requested) async {
    final source = await temp.createTemp('source-');
    await File(p.join(source.path, MiniAppStore.manifestFile)).writeAsString(
      jsonEncode({
        'id': 'panel',
        'name': 'Panel',
        'formatVersion': 2,
        'permissions': requested,
      }),
    );
    await File(p.join(source.path, 'index.html')).writeAsString('panel');
    return (await store.install(source)).app;
  }

  test(
    'declarations never grant capabilities; storage and exports cannot forge grants',
    () async {
      await install(['actions.ai', 'device.battery.read']);
      expect(await permissions.granted('panel'), isEmpty);
      await store.storageSet('panel', 'grants.json', {
        'granted': ['actions.ai'],
      });
      expect(await permissions.granted('panel'), isEmpty);
      await permissions.setGranted('panel', 'actions.ai', true);
      expect(await permissions.granted('panel'), {'actions.ai'});
      final archive = await store.exportArchive(
        'panel',
        withData: true,
        into: temp,
      );
      final names = ZipDecoder()
          .decodeBytes(await archive.readAsBytes())
          .map((e) => e.name);
      expect(
        names.any(
          (n) => n.contains('.host') || n == 'grants.json' || n == 'undo.json',
        ),
        isFalse,
      );
      final reopened = MiniAppPermissions(MiniAppStore(root: () async => root));
      expect(await reopened.granted('panel'), {'actions.ai'});
      reopened.dispose();
    },
  );

  test(
    'update and rollback intersect live declarations without resurrecting grants',
    () async {
      final original = await install(['actions.ai', 'device.battery.read']);
      await permissions.setGranted('panel', 'actions.ai', true);
      await install(['device.battery.read']);
      expect(await permissions.granted('panel'), isEmpty);
      await store.rollback('panel', MiniAppStore.versionOf(original));
      expect(await permissions.granted('panel'), isEmpty);
      await expectLater(
        permissions.setGranted('panel', 'device.root.wifi', true),
        throwsA(isA<MiniAppException>()),
      );
    },
  );

  test('deleting and reinstalling an app removes host grants', () async {
    await install(['actions.ai']);
    await permissions.setGranted('panel', 'actions.ai', true);
    await store.delete('panel');
    await install(['actions.ai']);
    expect(await permissions.granted('panel'), isEmpty);
  });

  test(
    'store updates prune grants even while no permission runtime is alive',
    () async {
      final original = await install(['actions.ai', 'device.battery.read']);
      await permissions.setGranted('panel', 'actions.ai', true);
      permissions.dispose();
      await install(['device.battery.read']);
      await store.rollback('panel', MiniAppStore.versionOf(original));
      permissions = MiniAppPermissions(store);
      expect(await permissions.granted('panel'), isEmpty);
    },
  );

  test(
    'concurrent explicit grants preserve independent toggles on disk',
    () async {
      await install(['actions.ai', 'device.battery.read']);
      await permissions.granted('panel');
      await Future.wait([
        permissions.setGranted('panel', 'actions.ai', true),
        permissions.setGranted('panel', 'device.battery.read', true),
      ]);
      expect(await permissions.granted('panel'), {
        'actions.ai',
        'device.battery.read',
      });
      final reopened = MiniAppPermissions(MiniAppStore(root: () async => root));
      expect(await reopened.granted('panel'), {
        'actions.ai',
        'device.battery.read',
      });
      reopened.dispose();
    },
  );

  test(
    'grant revocation is live across permission instances sharing the store',
    () async {
      await install(['actions.ai']);
      await permissions.setGranted('panel', 'actions.ai', true);
      final other = MiniAppPermissions(store);
      expect(await other.granted('panel'), {'actions.ai'});
      final before = other.versionFor('panel');
      await permissions.setGranted('panel', 'actions.ai', false);
      expect(other.versionFor('panel'), greaterThan(before));
      expect(await other.granted('panel'), isEmpty);
      other.dispose();
    },
  );
}
