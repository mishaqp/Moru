import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/home/services/root_phone_control.dart';
import 'package:Kelivo/features/home/services/root_shell_tool.dart';

const _screen = '''<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" class="android.widget.FrameLayout" package="com.example" bounds="[0,0][1080,2400]">
    <node index="0" text="Привет" resource-id="com.example:id/title" class="android.widget.TextView" clickable="false" bounds="[40,100][1040,200]" />
    <node index="1" text="" content-desc="Send" class="android.widget.ImageButton" clickable="true" bounds="[900,2200][1060,2360]" />
    <node index="2" text="" class="android.widget.EditText" clickable="true" bounds="[40,2200][880,2360]" />
    <node index="3" text="" class="android.view.View" clickable="false" bounds="[0,300][1080,2100]" />
    <node index="4" text="list" class="android.widget.ListView" scrollable="true" bounds="[0,0][0,0]" />
  </node>
</hierarchy>''';

void main() {
  late Directory temp;
  late List<String> commands;
  late List<String> clipboard;
  late RootPhoneControl control;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('root-phone-');
    final dump = File('${temp.path}/ui.xml')..writeAsStringSync(_screen);
    commands = [];
    clipboard = [];
    control = RootPhoneControl(
      shell: RootShellTool(
        start: (executable, arguments) {
          final command = arguments.last;
          commands.add(command);
          final script = command.startsWith('uiautomator')
              ? 'echo "UI hierchary dumped to: /data/local/tmp/moru-ui.xml"; cat ${dump.path}'
              : command == 'wm size'
              ? 'echo "Physical size: 1080x2400"'
              : command.startsWith('cmd package query-activities')
              ? r'printf "com.b/.Main\ncom.a/.Main\ncom.b/.Other\n"'
              : command.startsWith('input tap 0 0')
              ? 'echo "input: bad" >&2; exit 1'
              : 'true';
          return Process.start('sh', ['-c', script]);
        },
      ),
      setClipboard: (text) async => clipboard.add(text),
    );
  });
  tearDown(() => temp.delete(recursive: true));

  Future<Map<String, dynamic>> run(Map<String, dynamic> args) async =>
      jsonDecode(await control.execute(args)) as Map<String, dynamic>;

  test('reads the screen as nodes with tap points', () async {
    final screen = await run({'action': 'read_screen'});
    expect(screen['ok'], isTrue);
    expect(screen['mode'], 'root');
    expect(screen['width'], 1080);
    expect(screen['height'], 2400);
    expect(screen['nodes'], [
      {
        'text': 'Привет',
        'id': 'com.example:id/title',
        'class': 'TextView',
        'x': 540,
        'y': 150,
      },
      {
        'description': 'Send',
        'class': 'ImageButton',
        'clickable': true,
        'x': 980,
        'y': 2280,
      },
      {
        'class': 'EditText',
        'clickable': true,
        'editable': true,
        'x': 460,
        'y': 2280,
      },
    ]);
  });

  test('actions become input and statusbar commands', () async {
    expect((await run({'action': 'tap', 'x': 980, 'y': 2280.4}))['ok'], isTrue);
    await run({'action': 'long_press', 'x': 10, 'y': 20});
    await run({
      'action': 'swipe',
      'x': 1,
      'y': 2,
      'end_x': 3,
      'end_y': 4,
      'duration_ms': 500,
    });
    await run({'action': 'scroll', 'direction': 'down'});
    await run({'action': 'back'});
    await run({'action': 'home'});
    await run({'action': 'recents'});
    await run({'action': 'notifications'});
    await run({'action': 'quick_settings'});
    await run({'action': 'open_app', 'package_name': 'org.telegram.messenger'});
    expect(commands, [
      'input tap 980 2280',
      'input swipe 10 20 10 20 700',
      'input swipe 1 2 3 4 500',
      'wm size',
      'input swipe 540 2000 540 400 300',
      'input keyevent 4',
      'input keyevent 3',
      'input keyevent 187',
      'cmd statusbar expand-notifications',
      'cmd statusbar expand-settings',
      'monkey -p org.telegram.messenger -c android.intent.category.LAUNCHER 1',
    ]);
  });

  test('text is pasted over the field, so any language works', () async {
    await run({
      'action': 'set_text',
      'text': 'Привет, мир',
      'x': 460,
      'y': 2280,
    });
    expect(clipboard, ['Привет, мир']);
    expect(commands.single, startsWith('input tap 460 2280; sleep 0.3; '));
    expect(commands.single, endsWith('input keyevent 279'));
  });

  test('apps are listed once, sorted', () async {
    expect((await run({'action': 'list_apps'}))['apps'], ['com.a', 'com.b']);
  });

  test('missing points, bad packages and failures are explained', () async {
    expect(
      (await run({'action': 'tap', 'node_id': 'n1'}))['error'],
      'INVALID_ARGUMENT',
    );
    expect(
      (await run({'action': 'swipe', 'x': 1}))['error'],
      'INVALID_ARGUMENT',
    );
    expect(
      (await run({'action': 'open_app', 'package_name': 'a; reboot'}))['error'],
      'INVALID_ARGUMENT',
    );
    final failed = await run({'action': 'tap', 'x': 0, 'y': 0});
    expect(failed['error'], 'ROOT_FAILED');
    expect(failed['message'], 'input: bad');
    expect(commands, ['input tap 0 0']);
  });

  test('only an unavailable Accessibility service hands over to root', () {
    expect(
      RootPhoneControl.accessibilityUnavailable(
        '{"error":"SERVICE_UNAVAILABLE","message":"Enable it"}',
      ),
      isTrue,
    );
    expect(
      RootPhoneControl.accessibilityUnavailable('{"error":"STALE_SCREEN"}'),
      isFalse,
    );
    expect(RootPhoneControl.accessibilityUnavailable('not json'), isFalse);
  });
}
