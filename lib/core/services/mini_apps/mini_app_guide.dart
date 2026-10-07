import 'dart:convert';

import 'package:flutter/services.dart';

import 'mini_app_assets.dart';
import 'mini_app_store.dart';

/// A bounded, offline reference and complete starter projects for `mini_apps`.
class MiniAppGuide {
  const MiniAppGuide._();

  static const topics = [
    'api',
    'storage',
    'libraries',
    'manifest',
    'workflow',
    'theme',
    'jobs',
    'network',
    'games',
    'errors',
  ];

  static const examples = [
    {
      'id': 'tracker',
      'description': 'Water tracker; persistent JSON and chat-driven redraw.',
    },
    {
      'id': 'chart',
      'description': 'Chart.js bar graph; persistent editable values.',
    },
    {
      'id': 'phaser',
      'description':
          'Phaser coin game; touch, collisions, pause and best score.',
    },
    {
      'id': 'galacean',
      'description':
          'Galacean scene with sprites, 2D collisions and a touch joystick.',
    },
    {
      'id': 'sqlite',
      'description': 'sql.js notes; local WASM and persisted database bytes.',
    },
  ];

  static const _files = ['moru-app.json', 'index.html', 'main.js', 'style.css'];

  static String? _option(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value == null) return null;
    if (value is! String) {
      throw MiniAppException('invalid_$key', '"$key" must be a string.');
    }
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
  }

  /// Reads only named packaged projects; caller-provided paths are never used.
  static Future<Map<String, dynamic>> read(Map<String, dynamic> args) async {
    final topic = _option(args, 'topic');
    final example = _option(args, 'example');
    if (topic != null && !topics.contains(topic)) {
      throw MiniAppException(
        'invalid_topic',
        'Unknown guide topic "$topic". Use: ${topics.join(', ')}.',
      );
    }
    if (example != null) {
      if (!examples.any((item) => item['id'] == example)) {
        throw MiniAppException(
          'invalid_example',
          'Unknown example "$example". Use: '
              '${examples.map((item) => item['id']).join(', ')}.',
        );
      }
      final files = <String, String>{};
      for (final filename in _files) {
        files[filename] = await rootBundle.loadString(
          'assets/mini_apps/examples/$example/$filename',
        );
      }
      return {
        'example': example,
        'manifest': jsonDecode(files[MiniAppStore.manifestFile]!),
        'files': files,
        'next':
            'Write each files entry to one workspace folder with write_file, '
            'then publish_mini_app {path: "that-folder"}. moru.js and shared '
            'runtime libraries are supplied by Moru.',
      };
    }

    final overview = <String, dynamic>{
      'platform': 'Android WebView; HTML, CSS, JS, ES modules and local WASM.',
      'topics': topics,
      'quick_start': _workflow,
      'manifest': _manifest,
      'api': _api,
      'storage': _storage,
      'libraries': _libraries,
      'library_usage': _libraryUsage,
      'theme': _theme,
      'jobs': _jobs,
      'network': _network,
      'games': _games,
      'errors': _errors,
      'examples': examples,
    };
    if (topic == null) return {'guide': overview};
    return {
      'guide': {
        'topic': topic,
        if (topic == 'api') 'api': _api,
        if (topic == 'storage') ...{
          'api': _api
              .where((method) => method['name']!.startsWith('moru.storage.'))
              .toList(),
          'notes': _storage,
        },
        if (topic == 'libraries') ...{
          'libraries': _libraries,
          'usage': _libraryUsage,
        },
        if (topic == 'manifest') 'manifest': _manifest,
        if (topic == 'workflow') 'steps': _workflow,
        if (topic == 'theme') 'notes': _theme,
        if (topic == 'jobs') ...{
          'api': _api
              .where((method) => method['name']!.startsWith('moru.jobs.'))
              .toList(),
          'notes': _jobs,
        },
        if (topic == 'network') 'notes': _network,
        if (topic == 'games') 'notes': _games,
        if (topic == 'errors') 'notes': _errors,
        'examples': examples,
      },
    };
  }

  static List<Map<String, Object>> get _libraries => [
    for (final entry in MiniAppAssets.catalog.entries)
      {
        'name': entry.key,
        ...entry.value,
        if (_globals.containsKey(entry.key)) 'global': _globals[entry.key]!,
      },
  ];

  static const _globals = {
    'galacean': 'Galacean',
    'galacean-ui': 'Galacean.UI',
    'phaser': 'Phaser',
    'chartjs': 'Chart',
    'sqljs': 'initSqlJs',
  };

  static const _workflow = [
    'mini_apps {action: "guide", example: "tracker"} returns a manifest '
        'and complete files. Write files to a workspace folder and call '
        'publish_mini_app {path: "project"}. Do not write moru.js.',
    'A plain project needs moru-app.json and an entry HTML. Moru inserts '
        'moru.js before page scripts. Use <script src="main.js" defer></script> '
        'or <script type="module" src="./main.js"></script>.',
    'For Vite, use base: \'./\', build with your normal workspace tools, then '
        'publish_mini_app {path: "project/dist", manifest: {id: "my-app", '
        'name: "My app", entry: "index.html"}}. The build folder needs no '
        'manual copying or manifest when manifest is supplied.',
    'Patch an installed app with publish_mini_app {path: "patch-folder", '
        'app_id: "my-app", files: ["main.js", "style.css"]}. Each listed '
        'path is relative to that source folder. Optional manifest merges '
        'non-null metadata (null keeps the old value); id cannot change. '
        'Remaining files, data and versions stay.',
    'Publish the folder directly, including binary assets. Do not move a '
        'build through token-limited read_file results. Final project limit: '
        '500 files / 20 MiB. Unsafe paths and symlinks are rejected.',
    'Publish runs the real MiniAppChecker in an Android WebView. Inspect '
        'its check result, then mini_apps errors after interaction. '
        'Republish fixes; versions and rollback preserve stored data.',
  ];

  static const _manifest = {
    'required': {
      'id': '1–40 lowercase letters/digits/dashes',
      'name': 'Display name',
    },
    'optional': {
      'description': 'What the app does.',
      'entry': 'Relative HTML path; default index.html. Nested paths work.',
      'icon': 'Relative SVG path.',
      'data': 'Describe every storage key and JSON shape so chat can edit it.',
      'network':
          'Allowed HTTP(S) hosts, e.g. ["api.example.com"]. Empty = offline.',
      'permissions':
          'Supported: ["calendar"]. Device permission is still needed.',
      'fullscreen': 'boolean, default false; hides app bar and system bars.',
      'orientation': 'any (default), portrait or landscape.',
      'keepAwake': 'boolean, default false; while the app is open.',
      'server':
          '{command: "python3 server.py"}; optional Android Linux server.',
    },
  };

  static const _storage = [
    'All bridge methods return promises except moru.assets.url. Await reads '
        'and writes; catch errors and show a visible status. Store JSON values '
        'under string keys (1–200 characters); app storage limit is 5 MiB.',
    'moru.storage is private to one app and survives publishing, rollback '
        'and backups. Use it for durable data; do not rely on localStorage.',
    'Listen on window for moru:storage and re-read when event.detail.key '
        'matches. Chat mini_apps write/remove triggers it. Your own storage '
        'writes do not echo; redraw explicitly after awaiting the write.',
    'Example: window.addEventListener("moru:storage", e => { '
        'if (e.detail.key === "log") redraw().catch(showError); });',
  ];

  static const _libraryUsage = [
    'await moru.assets.load("ui") loads responsive CSS; '
        'await moru.assets.load("chartjs") exposes Chart. Load resolves after '
        'CSS/JS is ready, deduplicates calls and orders dependencies.',
    'await moru.assets.load("galacean-ui") loads Galacean first and then '
        'Galacean.UI. Versions are compatible. galacean needs WebGL.',
    'await moru.assets.load("phaser"); new Phaser.Game(config). '
        'Chart.js: await moru.assets.load("chartjs"); new Chart(canvas, config).',
    'sql.js: await moru.assets.load("sqljs"); const SQL = await initSqlJs({'
        'locateFile: () => moru.assets.url("sqljs-wasm")}); '
        'const db = new SQL.Database(); db.run("CREATE TABLE notes(text TEXT)"); '
        'Persist Array.from(db.export()) with moru.storage; restore using Uint8Array.',
    'moru.assets.url(name) returns a same-origin local URL synchronously '
        '(also for CSS/WASM). Use registry names, never CDN links, runtime '
        'downloads or runtime copies in app folders. Unknown names reject/throw.',
  ];

  static const _theme = [
    'await moru.assets.load("ui"); use .moru-app, .moru-card, .moru-stack, '
        '.moru-row, .moru-grid, .moru-button, .moru-button--secondary, '
        '.moru-field, .moru-muted, .moru-list, .moru-list-item, '
        '.moru-tabs and .moru-tab. Use real labels and buttons; targets ≥44 px.',
    'Moru sets document.documentElement.dataset.moruTheme to light/dark and '
        'provides --moru-bg, --moru-surface, --moru-text, --moru-muted, '
        '--moru-accent, --moru-on-accent, --moru-border. Use those variables '
        'in custom CSS; the UI kit includes safe-area padding.',
    'moru.theme is the current {dark, colors, insets} snapshot; read it '
        'after moru.js loads. Moru updates it with the theme event. Insets '
        'are in CSS pixels and also available as --moru-safe-top/right/bottom/left.',
    'Listen on window for moru:theme and re-read computed CSS variables '
        'to repaint canvases/charts. Also handle resize and visibilitychange '
        '(pause games while hidden). No polling is needed.',
  ];

  static const _jobs = [
    'reminders schedule notifications: {time: "HH:mm", days?: [1..7], '
        'title?: string, body?: string}. 1 = Monday; omit days for daily. '
        'reminders.list returns an object keyed by id; maximum 20 reminders.',
    'jobs run a global function: {time: "HH:mm", days?: [1..7], '
        'run: "functionName"}. Maximum 10 jobs; ids 1–40 letters/digits/_/-. '
        'jobs.list returns an array with id/time/run/days/nextRunAt/lastRun.',
    'Define window.check = async function () { ... }; await moru.jobs.set('
        '"daily", {time: "09:00", run: "check"});. Jobs open the same HTML '
        'out of sight, wait for the function promise (30 s maximum), then close. '
        'Use (await moru.app.info()).background to avoid starting a game there.',
    'Test with mini_apps {action: "run_job", app_id: "my-app", job: "daily"}, '
        'then read jobs/errors about 30 s later. Data and schedules survive updates.',
  ];

  static const _network = [
    'moru.fetch requires manifest network hosts (supports *.example.com). '
        'Redirects must stay allowed. Options: method GET/HEAD/POST/PUT/PATCH/DELETE, '
        'headers object, body string (JSON.stringify for JSON). Request ≤1 MiB, '
        'response ≤2 MiB, per-request timeout 20 s.',
    'The returned object has ok/status/url/headers/body and synchronous '
        '.json()/.text() helpers; it is not a browser Response. Check ok '
        'before parsing. Example: const r = await moru.fetch(url); '
        'if (!r.ok) throw Error(String(r.status)); const data = r.json();',
    'moru.server.fetch("/api/items", options) has the same result/options '
        'and only calls this app\'s declared server. moru.server.url("/stream") '
        'returns a token-bearing local URL for fetch/img/WebSocket. The server '
        'runs in the Android Linux environment while an app/job uses it; '
        'persist its files in /data. Shared offline libraries need no server command.',
  ];

  static const _games = [
    'Use phaser for 2D arcade physics or galacean for WebGL scenes. The '
        'Galacean example uses real SpriteRenderer components and explicit '
        'circle collisions; no physics plugin is bundled.',
    'Include start/pause/game-over/restart, a persistent best score, '
        'pointer/touch input, resize and visibility handling. On-screen '
        'controls need touch-action: none and pointercancel handling.',
    'Galacean.create does not exist: use await Galacean.WebGLEngine.create('
        '{canvas}), sceneManager.activeScene, Camera, Sprite, SpriteRenderer '
        'and Script.onUpdate(deltaTime) in seconds. Engine UI is Galacean.UI; '
        'normal DOM controls can overlay the engine canvas.',
  ];

  static const _errors = [
    'Use try/catch around awaited bridge/library calls and show a status '
        'message. Unhandled promises, JS/resource errors and failed moru.* '
        'calls go to the app\'s journal. Do not hide a startup error in console only.',
    'mini_apps {action: "errors", app_id: "my-app"} reads the journal; '
        'clear: true clears it after reading. Publish checks a sandbox copy '
        'and never changes real storage or sends device notifications.',
    'mini_apps versions lists the last 5 code versions. rollback with '
        'a version id restores code while keeping data. Validate games by '
        'playing too: a startup check cannot prove every interaction.',
  ];

  static const _api = <Map<String, String>>[
    {
      'name': 'moru.storage.get',
      'signature': 'get(key)',
      'returns': 'Promise<JSON|null>',
      'notes': 'Missing key returns null.',
    },
    {
      'name': 'moru.storage.set',
      'signature': 'set(key, value)',
      'returns': 'Promise<void>',
      'notes': 'JSON value; redraw explicitly after your own write.',
    },
    {
      'name': 'moru.storage.remove',
      'signature': 'remove(key)',
      'returns': 'Promise<void>',
    },
    {
      'name': 'moru.storage.keys',
      'signature': 'keys()',
      'returns': 'Promise<string[]>',
    },
    {
      'name': 'moru.ai.ask',
      'signature': 'ask(prompt, {system?})',
      'returns': 'Promise<string>',
      'notes':
          'Default model; one call at a time; prompt/system ≤32000 chars. Requires configured model/network.',
    },
    {
      'name': 'moru.notify',
      'signature': 'notify(title, body?)',
      'returns': 'Promise<void>',
      'notes':
          'Notification opens app; title ≤80/body ≤300 chars; needs Android notification permission.',
    },
    {
      'name': 'moru.reminders.set',
      'signature': 'set(id, {time, days?, title?, body?})',
      'returns': 'Promise<void>',
    },
    {
      'name': 'moru.reminders.remove',
      'signature': 'remove(id)',
      'returns': 'Promise<void>',
    },
    {
      'name': 'moru.reminders.list',
      'signature': 'list()',
      'returns': 'Promise<object keyed by id>',
    },
    {
      'name': 'moru.jobs.set',
      'signature': 'set(id, {time, days?, run})',
      'returns': 'Promise<void>',
    },
    {
      'name': 'moru.jobs.remove',
      'signature': 'remove(id)',
      'returns': 'Promise<void>',
    },
    {
      'name': 'moru.jobs.list',
      'signature': 'list()',
      'returns': 'Promise<job[]>',
    },
    {
      'name': 'moru.fetch',
      'signature': 'fetch(url, {method?, headers?, body?})',
      'returns': 'Promise<{ok,status,url,headers,body,json(),text()}>',
      'notes': 'Allowlist in manifest network. json()/text() are synchronous.',
    },
    {
      'name': 'moru.server.fetch',
      'signature': 'fetch(path, {method?, headers?, body?})',
      'returns': 'Promise<{ok,status,url,headers,body,json(),text()}>',
      'notes': 'Path starts with /; only app\'s own server.',
    },
    {
      'name': 'moru.server.url',
      'signature': 'url(path = "/")',
      'returns': 'Promise<string>',
      'notes': 'Token-bearing URL of app\'s own local server.',
    },
    {
      'name': 'moru.calendar.list',
      'signature':
          'list({begin?, end?, range?, query?, limit?, calendar_id?, include_calendars?})',
      'returns': 'Promise<{events, calendars?}>',
      'notes':
          'range: today/week/month; dates ISO-8601 or epoch milliseconds; manifest permissions:["calendar"] + Android grant.',
    },
    {
      'name': 'moru.calendar.add',
      'signature':
          'add({title, start, end?, description?, location?, all_day?, reminders?, calendar_id?})',
      'returns': 'Promise<object>',
      'notes':
          'Date formats as list; reminders: minutes before start. Requires declared and granted calendar permission; user confirmation.',
    },
    {
      'name': 'moru.vibrate',
      'signature': 'vibrate(milliseconds | [on, off, on, ...])',
      'returns': 'Promise<void>',
      'notes': 'Nonnegative values; ≤20 segments and ≤5000 ms total.',
    },
    {
      'name': 'moru.haptic',
      'signature': 'haptic(kind = "light")',
      'returns': 'Promise<void>',
      'notes': 'light, medium, heavy or selection.',
    },
    {
      'name': 'moru.app.info',
      'signature': 'info()',
      'returns':
          'Promise<{id,name,platform,fullscreen,orientation,background}>',
    },
    {
      'name': 'moru.app.close',
      'signature': 'close()',
      'returns': 'Promise<void>',
    },
    {
      'name': 'moru.assets.url',
      'signature': 'url(name)',
      'returns': 'string (synchronous)',
      'notes':
          'Local shared asset URL; exact catalog key, including sqljs-wasm.',
    },
    {
      'name': 'moru.assets.load',
      'signature': 'load(name)',
      'returns': 'Promise<void>',
      'notes':
          'Loads CSS/JS and dependencies once; WASM uses url() with the consuming library.',
    },
  ];
}
