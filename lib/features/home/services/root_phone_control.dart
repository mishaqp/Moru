import 'dart:convert';

import 'package:xml/xml.dart';

import 'root_shell_tool.dart';

/// `phone_control` over root when its Accessibility service is off: the
/// screen comes from `uiautomator dump`, actions from `input`. Nodes carry
/// their centre as x,y; node_id and snapshot_id are not used.
class RootPhoneControl {
  const RootPhoneControl({
    this.shell = const RootShellTool(),
    required this.setClipboard,
  });

  final RootShellTool shell;

  /// Text is pasted, so any language works (`input text` is ASCII only).
  final Future<void> Function(String text) setClipboard;

  static const int maxNodes = 300;
  static const String _dump = '/data/local/tmp/moru-ui.xml';
  static final RegExp _package = RegExp(r'^[A-Za-z][\w.]{0,200}$');

  /// Whether a phone_control result says its Accessibility service is off.
  static bool accessibilityUnavailable(String result) {
    try {
      final decoded = jsonDecode(result);
      return decoded is Map && decoded['error'] == 'SERVICE_UNAVAILABLE';
    } on FormatException {
      return false;
    }
  }

  Future<String> execute(Map<String, dynamic> args) async {
    final action = '${args['action'] ?? ''}';
    int? number(String key) {
      final value = args[key];
      return value is num && value >= 0 ? value.round() : null;
    }

    final x = number('x');
    final y = number('y');
    switch (action) {
      case 'read_screen':
        return _readScreen();
      case 'tap':
        if (x == null || y == null) return _needsPoint(action);
        return _run('input tap $x $y');
      case 'long_press':
        if (x == null || y == null) return _needsPoint(action);
        return _run('input swipe $x $y $x $y ${number('duration_ms') ?? 700}');
      case 'swipe':
        final endX = number('end_x');
        final endY = number('end_y');
        if (x == null || y == null || endX == null || endY == null) {
          return _error(
            'INVALID_ARGUMENT',
            'swipe needs x, y, end_x and end_y from read_screen.',
          );
        }
        return _run(
          'input swipe $x $y $endX $endY ${number('duration_ms') ?? 300}',
        );
      case 'scroll':
        return _scroll('${args['direction'] ?? 'down'}');
      case 'set_text':
        final text = args['text'];
        if (text is! String) {
          return _error('INVALID_ARGUMENT', 'set_text needs text.');
        }
        await setClipboard(text);
        // Focus the field if given, select what is there, paste over it.
        final focus = x != null && y != null
            ? 'input tap $x $y; sleep 0.3; '
            : '';
        return _run('${focus}input keycombination 113 29; input keyevent 279');
      case 'back':
        return _run('input keyevent 4');
      case 'home':
        return _run('input keyevent 3');
      case 'recents':
        return _run('input keyevent 187');
      case 'notifications':
        return _run('cmd statusbar expand-notifications');
      case 'quick_settings':
        return _run('cmd statusbar expand-settings');
      case 'list_apps':
        return _listApps();
      case 'open_app':
        final package = '${args['package_name'] ?? ''}';
        if (!_package.hasMatch(package)) {
          return _error('INVALID_ARGUMENT', 'open_app needs package_name.');
        }
        return _run('monkey -p $package -c android.intent.category.LAUNCHER 1');
      default:
        return _error('INVALID_ARGUMENT', 'Unknown action "$action".');
    }
  }

  Future<String> _readScreen() async {
    final result = await shell.run(
      'uiautomator dump $_dump >/dev/null 2>&1; cat $_dump; rm -f $_dump',
    );
    if (result == null) return _noRoot();
    final start = result.stdout.indexOf('<?xml');
    if (start < 0) {
      return _error(
        'ROOT_FAILED',
        'Could not read the screen: ${result.stderr.trim()}',
      );
    }
    return jsonEncode({
      'ok': true,
      'mode': 'root',
      'note':
          'Accessibility is off, so root is used: act with the x,y of a '
          'node; node_id and snapshot_id are not used.',
      ...parseScreen(result.stdout.substring(start)),
    });
  }

  /// Visible, useful nodes of a `uiautomator dump`.
  static Map<String, Object?> parseScreen(String xml) {
    final nodes = <Map<String, Object?>>[];
    var width = 0;
    var height = 0;
    final bounds = RegExp(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$');
    for (final node in XmlDocument.parse(xml).findAllElements('node')) {
      if (node.ancestors.whereType<XmlElement>().any(
        (ancestor) => ancestor.getAttribute('password') == 'true',
      )) {
        continue;
      }
      final match = bounds.firstMatch(node.getAttribute('bounds') ?? '');
      if (match == null) continue;
      final [left, top, right, bottom] = [
        for (var i = 1; i <= 4; i++) int.parse(match[i]!),
      ];
      if (right > width) width = right;
      if (bottom > height) height = bottom;
      if (right <= left || bottom <= top) continue;
      String? attribute(String name) {
        final value = node.getAttribute(name)?.trim();
        return value == null || value.isEmpty ? null : value;
      }

      bool flag(String name) => node.getAttribute(name) == 'true';
      final password = flag('password');
      final text = password ? null : attribute('text');
      final description = password ? null : attribute('content-desc');
      final clickable = flag('clickable') || flag('long-clickable');
      final scrollable = flag('scrollable');
      final editable = attribute('class')?.contains('EditText') ?? false;
      if (text == null &&
          description == null &&
          !clickable &&
          !scrollable &&
          !password) {
        continue;
      }
      if (nodes.length >= maxNodes) break;
      nodes.add({
        'text': ?text,
        'description': ?description,
        'id': ?attribute('resource-id'),
        'class': ?attribute('class')?.split('.').last,
        if (password) 'password': true,
        if (clickable) 'clickable': true,
        if (scrollable) 'scrollable': true,
        if (editable) 'editable': true,
        'x': (left + right) ~/ 2,
        'y': (top + bottom) ~/ 2,
      });
    }
    return {'width': width, 'height': height, 'nodes': nodes};
  }

  Future<String> _scroll(String direction) async {
    final size = await shell.run('wm size');
    if (size == null) return _noRoot();
    final match = RegExp(r'(\d+)x(\d+)\s*$').firstMatch(size.stdout.trim());
    final width = int.tryParse(match?[1] ?? '') ?? 1080;
    final height = int.tryParse(match?[2] ?? '') ?? 2400;
    final cx = width ~/ 2;
    final cy = height ~/ 2;
    final dx = width ~/ 3;
    final dy = height ~/ 3;
    // Content moves opposite to the finger.
    final (from, to) = switch (direction) {
      'up' || 'backward' => ((cx, cy - dy), (cx, cy + dy)),
      'left' => ((cx - dx, cy), (cx + dx, cy)),
      'right' => ((cx + dx, cy), (cx - dx, cy)),
      _ => ((cx, cy + dy), (cx, cy - dy)),
    };
    return _run('input swipe ${from.$1} ${from.$2} ${to.$1} ${to.$2} 300');
  }

  Future<String> _listApps() async {
    final result = await shell.run(
      'cmd package query-activities --brief '
      '-a android.intent.action.MAIN -c android.intent.category.LAUNCHER',
    );
    if (result == null) return _noRoot();
    if (result.exitCode != 0 || result.timedOut) {
      return _error(
        'ROOT_FAILED',
        (result.stderr.isEmpty ? result.stdout : result.stderr).trim(),
      );
    }
    final packages = <String>{
      for (final line in const LineSplitter().convert(result.stdout))
        if (line.trim().contains('/')) line.trim().split('/').first,
    }.toList()..sort();
    return jsonEncode({'ok': true, 'mode': 'root', 'apps': packages});
  }

  Future<String> _run(String command) async {
    final result = await shell.run(command);
    if (result == null) return _noRoot();
    if (result.exitCode != 0 || result.timedOut) {
      return _error(
        'ROOT_FAILED',
        (result.stderr.isEmpty ? result.stdout : result.stderr).trim(),
      );
    }
    return jsonEncode({'ok': true, 'mode': 'root'});
  }

  static String _needsPoint(String action) => _error(
    'INVALID_ARGUMENT',
    'In root mode $action needs x and y of a node from read_screen.',
  );

  static String _noRoot() => _error(
    'SERVICE_UNAVAILABLE',
    'Neither Accessibility nor root is available.',
  );

  static String _error(String code, String message) =>
      jsonEncode({'error': code, 'message': message});
}
