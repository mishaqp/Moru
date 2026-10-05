import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:path/path.dart' as p;

import '../../core/services/mini_apps/mini_app_device.dart';
import '../../core/services/mini_apps/mini_app_store.dart';
import '../../l10n/app_localizations.dart';

/// A declarative example installed through the same checks as user mini apps.
/// Its controls have no special grants, executor or device-access path.
class PhoneControlMiniApp {
  const PhoneControlMiniApp._();

  static const id = 'phone-control';
  static final Map<MiniAppStore, Future<void>> _installing = {};

  static Future<void> ensureInstalled(MiniAppStore store) =>
      _installing[store] ??= _install(store).whenComplete(() {
        _installing.remove(store);
      });

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
    for (final entry in _languages.entries) entry.key: read(entry.value),
  };

  static Map<String, dynamic> manifest(AppLocalizations l10n) => {
    'id': id,
    'name': l10n.phonePanelTitle,
    'description': l10n.phonePanelDescription,
    'formatVersion': 2,
    'ui': {'engine': 'native', 'entry': 'screen.json'},
    'permissions': ['actions.ai'],
    'actions': _actions(l10n),
  };

  static Future<void> _install(MiniAppStore store) async {
    await store.load();
    if (store.byId(id) != null) return;
    final locale = PlatformDispatcher.instance.locale;
    final l10n = lookupAppLocalizations(
      const ['en', 'ru', 'zh'].contains(locale.languageCode)
          ? locale
          : const Locale('en'),
    );
    final source = await Directory.systemTemp.createTemp('moru-phone-panel-');
    try {
      await File(
        p.join(source.path, MiniAppStore.manifestFile),
      ).writeAsString(jsonEncode(manifest(l10n)));
      await File(
        p.join(source.path, 'screen.json'),
      ).writeAsString(jsonEncode(screen()));
      // Initializers share one future; an existing user-installed copy always
      // wins, including one installed while localization/source IO was pending.
      if (store.byId(id) == null) await store.install(source, ifAbsent: true);
    } finally {
      await source.delete(recursive: true);
    }
  }

  static Map<String, dynamic> _native(
    String name,
    String description,
    String handler,
  ) => {
    'name': name,
    'description': description,
    'inputSchema': MiniAppDeviceService.inputSchemaFor(handler),
    'permissions': MiniAppDeviceService.permissionsFor(handler).toList(),
    'danger': MiniAppDeviceService.requiresConfirmation(handler)
        ? 'root'
        : MiniAppDeviceService.isMutation(handler)
        ? 'write'
        : 'read',
    'executor': {'kind': 'native', 'handler': handler},
  };

  static List<Map<String, dynamic>> _actions(AppLocalizations l10n) {
    Map<String, dynamic> sequence(
      String name,
      String label,
      List<Map<String, dynamic>> steps,
    ) => {
      'name': name,
      'description': label,
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
      'permissions': ['device.screen.write', 'device.audio.write'],
      'danger': 'write',
      'executor': {'kind': 'sequence', 'steps': steps},
    };
    Map<String, dynamic> preset(
      String name,
      String label,
      int brightness,
      int timeout,
      int volume,
      String dnd,
    ) => {
      'name': name,
      'description': label,
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
      'permissions': ['device.screen.write', 'device.audio.write'],
      'danger': 'write',
      'executor': {
        'kind': 'preset',
        'steps': [
          {
            'handler': 'device.screen.brightness.set',
            'args': {'value': brightness, 'mode': 'manual'},
          },
          {
            'handler': 'device.screen.timeout.set',
            'args': {'milliseconds': timeout},
          },
          {
            'handler': 'device.audio.volume.set',
            'args': {'stream': 'music', 'value': volume},
          },
          {
            'handler': 'device.audio.dnd.set',
            'args': {'mode': dnd},
          },
        ],
      },
    };
    return [
      _native(
        'battery_status',
        l10n.miniAppsPermissionBatteryRead,
        'device.battery.get',
      ),
      _native(
        'screen_status',
        l10n.miniAppsPermissionScreenRead,
        'device.screen.get',
      ),
      _native(
        'audio_status',
        l10n.miniAppsPermissionAudioRead,
        'device.audio.get',
      ),
      _native(
        'connection_status',
        l10n.miniAppsPermissionConnectivityRead,
        'device.connectivity.get',
      ),
      _native(
        'flashlight_status',
        l10n.miniAppsPermissionFlashlightRead,
        'device.flashlight.get',
      ),
      _native(
        'system_status',
        l10n.miniAppsPermissionSystemRead,
        'device.system.get',
      ),
      _native(
        'brightness',
        l10n.phonePanelBrightness,
        'device.screen.brightness.set',
      ),
      _native(
        'screen_timeout',
        l10n.phonePanelScreenTimeout,
        'device.screen.timeout.set',
      ),
      _native('volume', l10n.phonePanelSound, 'device.audio.volume.set'),
      _native('dnd', l10n.phonePanelDnd, 'device.audio.dnd.set'),
      _native('flashlight', l10n.phonePanelFlashlight, 'device.flashlight.set'),
      _native('settings', l10n.phonePanelOpenSettings, 'device.settings.open'),
      _native(
        'power_save',
        l10n.miniAppsPermissionRootPowerSave,
        'device.root.power_save.set',
      ),
      _native('wifi', l10n.miniAppsPermissionRootWifi, 'device.root.wifi.set'),
      _native(
        'bluetooth',
        l10n.miniAppsPermissionRootBluetooth,
        'device.root.bluetooth.set',
      ),
      _native(
        'mobile_data',
        l10n.miniAppsPermissionRootData,
        'device.root.data.set',
      ),
      _native(
        'airplane',
        l10n.miniAppsPermissionRootAirplane,
        'device.root.airplane.set',
      ),
      _native('stop_app', l10n.phonePanelStopApp, 'device.root.stop_app'),
      preset('night_preset', l10n.phonePanelNight, 35, 30000, 0, 'priority'),
      preset('road_preset', l10n.phonePanelRoad, 200, 120000, 5, 'all'),
      preset('work_preset', l10n.phonePanelWork, 110, 60000, 2, 'priority'),
      {
        'name': 'restore_settings',
        'description': l10n.phonePanelRestore,
        'inputSchema': {
          'type': 'object',
          'properties': <String, dynamic>{},
          'additionalProperties': false,
        },
        'permissions': ['device.screen.write', 'device.audio.write'],
        'danger': 'write',
        'executor': {'kind': 'restore'},
      },
      {
        'name': 'record_mode',
        'description': l10n.phonePanelSelectedMode,
        'inputSchema': {
          'type': 'object',
          'properties': {
            'mode': {
              'type': 'string',
              'enum': ['night', 'road', 'work'],
            },
          },
          'required': ['mode'],
          'additionalProperties': false,
        },
        'permissions': <String>[],
        'danger': 'write',
        'executor': {
          'kind': 'state',
          'expressions': true,
          'patch': {
            'selectedMode': {r'$arg': 'mode'},
            'appliedAt': {r'$now': true},
          },
        },
      },
      {
        'name': 'clear_mode',
        'description':
            '${l10n.miniAppsErrorsClear}: ${l10n.phonePanelSelectedMode}',
        'inputSchema': {
          'type': 'object',
          'properties': <String, dynamic>{},
          'additionalProperties': false,
        },
        'permissions': <String>[],
        'danger': 'write',
        'executor': {
          'kind': 'state',
          'patch': {'selectedMode': null, 'appliedAt': null},
        },
      },
      for (final mode in [
        ('night', l10n.phonePanelNight),
        ('road', l10n.phonePanelRoad),
        ('work', l10n.phonePanelWork),
      ])
        sequence(mode.$1, mode.$2, [
          {'action': '${mode.$1}_preset', 'arguments': <String, dynamic>{}},
          {
            'action': 'record_mode',
            'arguments': {'mode': mode.$1},
          },
        ]),
      sequence('restore', l10n.phonePanelRestore, [
        {'action': 'restore_settings', 'arguments': <String, dynamic>{}},
        {'action': 'clear_mode', 'arguments': <String, dynamic>{}},
      ]),
    ];
  }

  static Map<String, dynamic> screen() {
    Map<String, dynamic> value(
      String Function(AppLocalizations) label,
      String bind, {
      String? unit,
      String? format,
      Map<String, dynamic>? values,
    }) => {
      'type': 'value',
      'label': _text(label),
      'bind': bind,
      if (unit != null) 'unit': unit,
      if (format != null) 'format': format,
      if (values != null) 'values': values,
    };
    Map<String, dynamic> indicator(
      String Function(AppLocalizations) label,
      String bind,
    ) => {'type': 'indicator', 'label': _text(label), 'bind': bind};
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
    Map<String, dynamic> toggle(
      String Function(AppLocalizations) label,
      String bind,
      String action,
    ) => {
      'type': 'switch',
      'label': _text(label),
      'bind': bind,
      'action': action,
      'args': {
        'enabled': {r'$value': true},
      },
    };
    Map<String, dynamic> card(
      String Function(AppLocalizations) title,
      List<Map<String, dynamic>> children,
    ) => {'type': 'card', 'title': _text(title), 'children': children};
    Map<String, dynamic> settings(
      String Function(AppLocalizations) label,
      String page,
    ) => button(label, 'settings', {'page': page});
    return {
      'version': 1,
      'title': _text((l) => l.phonePanelTitle),
      'components': [
        {'type': 'text', 'text': _text((l) => l.phonePanelIntro)},
        card((l) => l.phonePanelBattery, [
          {
            'type': 'indicator',
            'label': _text((l) => l.phonePanelCharge),
            'bind': 'device.battery.levelPercent',
            'min': 0,
            'max': 100,
            'unit': '%',
          },
          indicator((l) => l.phonePanelCharging, 'device.battery.charging'),
          value(
            (l) => l.phonePanelBatteryStatus,
            'device.battery.status',
            values: {
              'charging': _text((l) => l.phonePanelChargingStatus),
              'discharging': _text((l) => l.phonePanelDischargingStatus),
              'full': _text((l) => l.phonePanelFullStatus),
              'not_charging': _text((l) => l.phonePanelNotChargingStatus),
              'unknown': _text((l) => l.miniAppsNativeUnknown),
            },
          ),
          value(
            (l) => l.phonePanelPowerSource,
            'device.battery.plugged',
            values: {
              'none': _text((l) => l.phonePanelUnplugged),
              'ac': _text((l) => l.phonePanelAc),
              'usb': _text((l) => l.phonePanelUsb),
              'wireless': _text((l) => l.phonePanelWireless),
              'dock': _text((l) => l.phonePanelDock),
            },
          ),
          value(
            (l) => l.phonePanelTemperature,
            'device.battery.temperatureC',
            unit: '°C',
          ),
          value(
            (l) => l.phonePanelVoltage,
            'device.battery.voltageMv',
            unit: 'mV',
          ),
          value(
            (l) => l.phonePanelCurrent,
            'device.battery.currentMicroamps',
            unit: 'µA',
          ),
          value(
            (l) => l.phonePanelAverageCurrent,
            'device.battery.currentAverageMicroamps',
            unit: 'µA',
          ),
          value(
            (l) => l.phonePanelChargeCounter,
            'device.battery.chargeCounterMicroampHours',
            unit: 'µAh',
          ),
          value(
            (l) => l.phonePanelEnergy,
            'device.battery.energyNanowattHours',
            unit: 'nWh',
          ),
          value(
            (l) => l.phonePanelChargeTime,
            'device.battery.chargeTimeRemainingMs',
            format: 'duration',
          ),
          value((l) => l.phonePanelCycles, 'device.battery.cycleCount'),
          indicator((l) => l.phonePanelPowerSave, 'device.battery.powerSave'),
          button((l) => l.phoneControlRefresh, 'battery_status'),
          settings((l) => l.phonePanelBattery, 'battery'),
          settings((l) => l.phonePanelPowerSave, 'power_save'),
        ]),
        card((l) => l.phonePanelPresets, [
          {'type': 'text', 'text': _text((l) => l.phonePanelPresetsHint)},
          value(
            (l) => l.phonePanelSelectedMode,
            'data.selectedMode',
            values: {
              'night': _text((l) => l.phonePanelNight),
              'road': _text((l) => l.phonePanelRoad),
              'work': _text((l) => l.phonePanelWork),
            },
          ),
          value(
            (l) => l.phonePanelAppliedAt,
            'data.appliedAt',
            format: 'datetime',
          ),
          button((l) => l.phonePanelNight, 'night'),
          button((l) => l.phonePanelRoad, 'road'),
          button((l) => l.phonePanelWork, 'work'),
          button((l) => l.phonePanelRestore, 'restore'),
        ]),
        card((l) => l.phonePanelScreen, [
          {
            'type': 'slider',
            'label': _text((l) => l.phonePanelBrightness),
            'bind': 'device.screen.brightness',
            'min': 1,
            'max': 255,
            'step': 1,
            'action': 'brightness',
            'args': {
              'value': {r'$value': true},
              'mode': 'manual',
            },
          },
          value(
            (l) => l.phonePanelBrightnessMode,
            'device.screen.brightnessMode',
            values: {
              'manual': _text((l) => l.phonePanelManual),
              'automatic': _text((l) => l.phonePanelAutomatic),
            },
          ),
          {
            'type': 'list',
            'label': _text((l) => l.phonePanelScreenTimeout),
            'bind': 'device.screen.timeoutMs',
            'action': 'screen_timeout',
            'args': {
              'milliseconds': {r'$value': true},
            },
            'options': [
              {'value': 15000, 'label': _text((l) => l.phonePanel15Seconds)},
              {'value': 30000, 'label': _text((l) => l.phonePanel30Seconds)},
              {'value': 60000, 'label': _text((l) => l.phonePanel1Minute)},
              {'value': 120000, 'label': _text((l) => l.phonePanel2Minutes)},
              {'value': 300000, 'label': _text((l) => l.phonePanel5Minutes)},
              {'value': 600000, 'label': _text((l) => l.phonePanel10Minutes)},
              {'value': 1800000, 'label': _text((l) => l.phonePanel30Minutes)},
            ],
          },
          indicator((l) => l.phonePanelScreenOn, 'device.screen.interactive'),
          value(
            (l) => l.phonePanelRefreshRate,
            'device.screen.refreshRateHz',
            unit: 'Hz',
          ),
          indicator((l) => l.phonePanelCanWrite, 'device.screen.canWrite'),
          button((l) => l.phoneControlRefresh, 'screen_status'),
          settings((l) => l.phonePanelScreen, 'display'),
          settings((l) => l.phonePanelCanWrite, 'write_settings'),
        ]),
        card((l) => l.phonePanelSound, [
          for (final stream in [
            ('music', (AppLocalizations l) => l.phonePanelMusic),
            ('ring', (AppLocalizations l) => l.phonePanelRing),
            ('notification', (AppLocalizations l) => l.phonePanelNotification),
            ('alarm', (AppLocalizations l) => l.phonePanelAlarm),
            ('system', (AppLocalizations l) => l.phonePanelSystemVolume),
            ('voice_call', (AppLocalizations l) => l.phonePanelCallVolume),
          ])
            {
              'type': 'slider',
              'label': _text(stream.$2),
              'bind': 'device.audio.volumes.${stream.$1}.value',
              'minBind': 'device.audio.volumes.${stream.$1}.min',
              'maxBind': 'device.audio.volumes.${stream.$1}.max',
              'step': 1,
              'action': 'volume',
              'args': {
                'stream': stream.$1,
                'value': {r'$value': true},
              },
            },
          value(
            (l) => l.phonePanelRingerMode,
            'device.audio.ringerMode',
            values: {
              'normal': _text((l) => l.phonePanelNormal),
              'vibrate': _text((l) => l.phonePanelVibrate),
              'silent': _text((l) => l.phonePanelSilent),
            },
          ),
          {
            'type': 'list',
            'label': _text((l) => l.phonePanelDnd),
            'bind': 'device.audio.dnd',
            'action': 'dnd',
            'args': {
              'mode': {r'$value': true},
            },
            'options': [
              {'value': 'all', 'label': _text((l) => l.phonePanelDndAll)},
              {
                'value': 'priority',
                'label': _text((l) => l.phonePanelDndPriority),
              },
              {'value': 'none', 'label': _text((l) => l.phonePanelDndNone)},
              {'value': 'alarms', 'label': _text((l) => l.phonePanelDndAlarms)},
            ],
          },
          indicator((l) => l.phonePanelCanDnd, 'device.audio.canChangeDnd'),
          indicator((l) => l.phonePanelDndAccess, 'device.audio.canAccessDnd'),
          {'type': 'text', 'text': _text((l) => l.phonePanelDndAndroid15Hint)},
          button((l) => l.phoneControlRefresh, 'audio_status'),
          settings((l) => l.phonePanelSound, 'sound'),
          settings((l) => l.phonePanelDnd, 'dnd'),
          settings((l) => l.phonePanelDndAccess, 'dnd_access'),
        ]),
        card((l) => l.phonePanelConnections, [
          indicator(
            (l) => l.phonePanelConnected,
            'device.connectivity.connected',
          ),
          indicator(
            (l) => l.phonePanelValidated,
            'device.connectivity.validated',
          ),
          indicator((l) => l.phonePanelMetered, 'device.connectivity.metered'),
          value(
            (l) => l.phonePanelNetworkType,
            'device.connectivity.networkType',
            values: {
              'wifi': _text((l) => l.phonePanelWifi),
              'cellular': _text((l) => l.phonePanelMobileData),
              'other': _text((l) => l.phonePanelOtherNetwork),
              'ethernet': _text((l) => l.phonePanelEthernet),
              'vpn': _text((l) => l.phonePanelVpn),
              'none': _text((l) => l.phonePanelNone),
              'unknown': _text((l) => l.miniAppsNativeUnknown),
            },
          ),
          indicator((l) => l.phonePanelWifi, 'device.connectivity.wifiEnabled'),
          indicator(
            (l) => l.phonePanelBluetooth,
            'device.connectivity.bluetoothEnabled',
          ),
          indicator(
            (l) => l.phonePanelMobileData,
            'device.connectivity.mobileDataEnabled',
          ),
          indicator(
            (l) => l.phonePanelAirplane,
            'device.connectivity.airplaneMode',
          ),
          button((l) => l.phoneControlRefresh, 'connection_status'),
          settings((l) => l.phonePanelWifi, 'wifi'),
          settings((l) => l.phonePanelBluetooth, 'bluetooth'),
          settings((l) => l.phonePanelMobileData, 'mobile_data'),
          settings((l) => l.phonePanelAirplane, 'airplane'),
        ]),
        card((l) => l.phonePanelFlashlight, [
          indicator(
            (l) => l.phonePanelFlashlightAvailable,
            'device.flashlight.available',
          ),
          toggle(
            (l) => l.phonePanelFlashlight,
            'device.flashlight.enabled',
            'flashlight',
          ),
          indicator(
            (l) => l.phonePanelFlashlightControl,
            'device.flashlight.canControl',
          ),
          button((l) => l.phoneControlRefresh, 'flashlight_status'),
          settings((l) => l.miniAppsPermissionsTitle, 'permissions'),
        ]),
        card((l) => l.phonePanelSystem, [
          value((l) => l.phonePanelManufacturer, 'device.system.manufacturer'),
          value((l) => l.phonePanelModel, 'device.system.model'),
          value((l) => l.phonePanelAndroid, 'device.system.androidVersion'),
          value((l) => l.phonePanelAppVersion, 'device.system.appVersion'),
          value(
            (l) => l.phonePanelUptime,
            'device.system.uptimeMs',
            format: 'duration',
          ),
          value(
            (l) => l.phonePanelTotalMemory,
            'device.system.totalRamBytes',
            format: 'bytes',
          ),
          value(
            (l) => l.phonePanelFreeMemory,
            'device.system.availableRamBytes',
            format: 'bytes',
          ),
          value(
            (l) => l.phonePanelTotalStorage,
            'device.system.totalStorageBytes',
            format: 'bytes',
          ),
          value(
            (l) => l.phonePanelFreeStorage,
            'device.system.freeStorageBytes',
            format: 'bytes',
          ),
          button((l) => l.phoneControlRefresh, 'system_status'),
          settings((l) => l.phonePanelOpenSettings, 'app_details'),
          {
            'type': 'list',
            'label': _text((l) => l.phonePanelSelectedAppSettings),
            'bind': 'device.system.stoppableApps',
            'valueKey': 'packageName',
            'labelKey': 'label',
            'action': 'settings',
            'args': {
              'page': 'app_details',
              'packageName': {r'$value': true},
            },
          },
        ]),
        card((l) => l.phonePanelRoot, [
          {'type': 'text', 'text': _text((l) => l.phonePanelRootHint)},
          indicator(
            (l) => l.phonePanelRootAvailable,
            'device.system.rootAvailable',
          ),
          toggle(
            (l) => l.miniAppsPermissionRootPowerSave,
            'device.battery.powerSave',
            'power_save',
          ),
          toggle(
            (l) => l.miniAppsPermissionRootWifi,
            'device.connectivity.wifiEnabled',
            'wifi',
          ),
          toggle(
            (l) => l.miniAppsPermissionRootBluetooth,
            'device.connectivity.bluetoothEnabled',
            'bluetooth',
          ),
          toggle(
            (l) => l.miniAppsPermissionRootData,
            'device.connectivity.mobileDataEnabled',
            'mobile_data',
          ),
          toggle(
            (l) => l.miniAppsPermissionRootAirplane,
            'device.connectivity.airplaneMode',
            'airplane',
          ),
          {
            'type': 'list',
            'label': _text((l) => l.phonePanelStopApp),
            'bind': 'device.system.stoppableApps',
            'valueKey': 'packageName',
            'labelKey': 'label',
            'action': 'stop_app',
            'args': {
              'packageName': {r'$value': true},
            },
          },
        ]),
      ],
    };
  }
}
