import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:path/path.dart' as p;

import '../../core/services/mini_apps/mini_app_device.dart';
import '../../core/services/mini_apps/mini_app_store.dart';
import '../../l10n/app_localizations.dart';

/// The same declarative package exposed in the authoring specification.
class FocusMiniApp {
  const FocusMiniApp._();

  static const id = 'focus';
  static final Map<MiniAppStore, Future<void>> _installing = {};
  static final Map<String, AppLocalizations> _languages = {
    'en': lookupAppLocalizations(const Locale('en')),
    'ru': lookupAppLocalizations(const Locale('ru')),
    'zh': lookupAppLocalizations(const Locale('zh')),
    'zh_Hans': lookupAppLocalizations(
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    ),
    'zh_Hant': lookupAppLocalizations(
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    ),
  };

  static Map<String, String> _text(String Function(AppLocalizations) read) => {
    for (final language in _languages.entries)
      language.key: read(language.value),
  };

  static Map<String, dynamic> _schema() => {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  };

  static Map<String, dynamic> _todayMatches() => {
    r'$eq': [
      {r'$data': 'sessionDay'},
      {r'$today': true},
    ],
  };

  static Map<String, dynamic> _running() => {
    r'$eq': [
      {r'$data': 'running'},
      true,
    ],
  };

  /// Pure JSON data, also used verbatim by the built-in installer.
  static Map<String, dynamic> manifest(AppLocalizations l10n) {
    final devicePermissions = ['device.screen.write', 'device.audio.write'];
    Map<String, dynamic> action(
      String name,
      String description,
      Map<String, dynamic> executor, {
      List<String> permissions = const [],
      Map<String, dynamic>? schema,
    }) => {
      'name': name,
      'description': description,
      'inputSchema': schema ?? _schema(),
      'permissions': permissions,
      'danger': 'write',
      'executor': executor,
    };
    Map<String, dynamic> start(int minutes, String description) =>
        action('start_$minutes', description, {
          'kind': 'sequence',
          'steps': [
            {
              'action': 'focus_preset',
              'arguments': <String, dynamic>{},
              'onFailure': 'continue',
            },
            {
              'action': 'record_start',
              'arguments': {'durationMs': minutes * 60000},
            },
          ],
        }, permissions: devicePermissions);
    return {
      'id': id,
      'name': l10n.focusPanelTitle,
      'description': l10n.focusPanelDescription,
      'formatVersion': 2,
      'ui': {'engine': 'native', 'entry': 'screen.json'},
      'permissions': ['actions.ai', 'device.screen.read', 'device.audio.read'],
      'actions': [
        action('focus_preset', l10n.focusPanelSettings, {
          'kind': 'preset',
          'steps': [
            {
              'handler': 'device.screen.brightness.set',
              'args': {'value': 77, 'mode': 'manual'},
            },
            {
              'handler': 'device.audio.volume.set',
              'args': {'stream': 'music', 'value': 0},
            },
            {
              'handler': 'device.audio.dnd.set',
              'args': {'mode': 'none'},
            },
          ],
        }, permissions: devicePermissions),
        action(
          'record_start',
          l10n.focusPanelRecordStart,
          {
            'kind': 'state',
            'expressions': true,
            'patch': {
              'startedAt': {r'$now': true},
              'endsAt': {
                r'$add': [
                  {r'$now': true},
                  {r'$arg': 'durationMs'},
                ],
              },
              'running': true,
              'sessionsToday': {
                r'$if': [
                  _todayMatches(),
                  {r'$data': 'sessionsToday'},
                  0,
                ],
              },
              'sessionDay': {r'$today': true},
            },
          },
          schema: {
            'type': 'object',
            'properties': {
              'durationMs': {
                'type': 'integer',
                'enum': [900000, 1500000, 3000000],
              },
            },
            'required': ['durationMs'],
            'additionalProperties': false,
          },
        ),
        action('record_stop', l10n.focusPanelRecordStop, {
          'kind': 'state',
          'expressions': true,
          'patch': {
            'sessionsToday': {
              r'$if': [
                _running(),
                {
                  r'$if': [
                    _todayMatches(),
                    {r'$inc': 1},
                    1,
                  ],
                },
                {
                  r'$if': [
                    _todayMatches(),
                    {r'$data': 'sessionsToday'},
                    0,
                  ],
                },
              ],
            },
            'sessionDay': {r'$today': true},
            'running': false,
            'endsAt': null,
          },
        }),
        action('restore', l10n.phonePanelRestore, {
          'kind': 'restore',
        }, permissions: devicePermissions),
        start(15, l10n.focusPanelStart15),
        start(25, l10n.focusPanelStart25),
        start(50, l10n.focusPanelStart50),
        action('stop', l10n.focusPanelStop, {
          'kind': 'sequence',
          'steps': [
            {'action': 'record_stop', 'arguments': <String, dynamic>{}},
            {'action': 'restore', 'arguments': <String, dynamic>{}},
          ],
        }, permissions: devicePermissions),
        {
          'name': 'settings',
          'description': l10n.phonePanelOpenSettings,
          'inputSchema': MiniAppDeviceService.inputSchemaFor(
            'device.settings.open',
          ),
          'permissions': ['device.settings.open'],
          'danger': 'write',
          'executor': {'kind': 'native', 'handler': 'device.settings.open'},
        },
      ],
    };
  }

  /// Locale maps keep installed packages usable after changing Moru's language.
  static Map<String, dynamic> screen() {
    Map<String, dynamic> button(
      String Function(AppLocalizations) label,
      String action, [
      Map<String, dynamic> args = const {},
    ]) => {
      'type': 'button',
      'label': _text(label),
      'action': action,
      'args': args,
    };
    Map<String, dynamic> value(
      String Function(AppLocalizations) label,
      String bind, {
      String? format,
      Map<String, dynamic>? values,
    }) => {
      'type': 'value',
      'label': _text(label),
      'bind': bind,
      if (format != null) 'format': format,
      if (values != null) 'values': values,
    };
    return {
      'version': 1,
      'title': _text((l) => l.focusPanelTitle),
      'components': [
        {
          'type': 'card',
          'title': _text((l) => l.focusPanelSession),
          'children': [
            {
              'type': 'timer',
              'label': _text((l) => l.focusPanelRemaining),
              'bind': 'data.endsAt',
              'mode': 'countdown',
            },
            {
              'type': 'progress',
              'label': _text((l) => l.focusPanelProgress),
              'bind': 'data.endsAt',
              'startBind': 'data.startedAt',
            },
            {
              'type': 'indicator',
              'label': _text((l) => l.focusPanelRunning),
              'bind': 'data.running',
            },
            button((l) => l.focusPanelStart15, 'start_15'),
            button((l) => l.focusPanelStart25, 'start_25'),
            button((l) => l.focusPanelStart50, 'start_50'),
            button((l) => l.focusPanelStop, 'stop'),
            {'type': 'text', 'text': _text((l) => l.focusPanelManualStopHint)},
          ],
        },
        {
          'type': 'card',
          'title': _text((l) => l.focusPanelToday),
          'children': [
            value((l) => l.focusPanelSessionsToday, 'data.sessionsToday'),
            value((l) => l.focusPanelDay, 'data.sessionDay', format: 'date'),
            value(
              (l) => l.focusPanelStartedAt,
              'data.startedAt',
              format: 'datetime',
            ),
          ],
        },
        {
          'type': 'card',
          'title': _text((l) => l.focusPanelSettings),
          'children': [
            {'type': 'text', 'text': _text((l) => l.focusPanelSettingsHint)},
            value((l) => l.phonePanelBrightness, 'device.screen.brightness'),
            value((l) => l.phonePanelMusic, 'device.audio.volumes.music.value'),
            value(
              (l) => l.phonePanelDnd,
              'device.audio.dnd',
              values: {
                'all': _text((l) => l.phonePanelDndAll),
                'priority': _text((l) => l.phonePanelDndPriority),
                'none': _text((l) => l.phonePanelDndNone),
                'alarms': _text((l) => l.phonePanelDndAlarms),
              },
            ),
            {
              'type': 'text',
              'text': _text((l) => l.phonePanelDndAndroid15Hint),
            },
            button((l) => l.phonePanelDnd, 'settings', {'page': 'dnd'}),
            button((l) => l.phonePanelDndAccess, 'settings', {
              'page': 'dnd_access',
            }),
            button((l) => l.phonePanelBrightness, 'settings', {
              'page': 'write_settings',
            }),
          ],
        },
      ],
    };
  }

  static Future<void> ensureInstalled(MiniAppStore store) =>
      _installing[store] ??= _install(store).whenComplete(() {
        _installing.remove(store);
      });

  static Future<void> _install(MiniAppStore store) async {
    await store.load();
    if (store.byId(id) != null) return;
    final locale = PlatformDispatcher.instance.locale;
    final l10n = lookupAppLocalizations(
      const ['en', 'ru', 'zh'].contains(locale.languageCode)
          ? locale
          : const Locale('en'),
    );
    final source = await Directory.systemTemp.createTemp('moru-focus-panel-');
    try {
      await File(
        p.join(source.path, MiniAppStore.manifestFile),
      ).writeAsString(jsonEncode(manifest(l10n)));
      await File(
        p.join(source.path, 'screen.json'),
      ).writeAsString(jsonEncode(screen()));
      await store.install(source, ifAbsent: true);
    } finally {
      await source.delete(recursive: true);
    }
  }
}
