import 'dart:ui';

import '../../core/services/mini_apps/mini_app_device.dart';
import '../../core/services/mini_apps/mini_app_manifest.dart';
import '../../l10n/app_localizations.dart';
import 'focus_mini_app.dart';
import 'phone_control_mini_app.dart';

/// Public authoring contract, available without loading apps or device state.
/// Handler schemas and the complete Focus files share their production source.
class MiniAppSpecification {
  const MiniAppSpecification._();

  static Map<String, dynamic> get document => {
    'formatVersion': 2,
    'workflow': [
      'Get this specification with mini_apps {action:spec} or publish_mini_app {action:spec}.',
      'Write the example JSON objects to moru-app.json and screen.json in a workspace folder; change id/name/actions for your app.',
      'Publish with publish_mini_app {path:folder}. Installation never grants capabilities. Ask the user to grant them on the app screen.',
      'mini_apps {action:list} discovers installed app IDs and ma_ tools; state reads a snapshot. Buttons, chat and ACP execute the same declared actions.',
    ],
    'manifest': {
      'nativePanelExampleFields': [
        'id',
        'name',
        'formatVersion',
        'ui',
        'actions',
      ],
      'id':
          '1–40 lowercase letters, digits or dashes, starting with a letter or digit; stable across updates.',
      'name':
          '1–40 character display string; description and data documentation are optional.',
      'formatVersion': 2,
      'ui': {'engine': 'native', 'entry': 'screen.json'},
      'actions': '[{name,description,inputSchema,permissions,danger,executor}]',
      'actionName':
          r'Unique identifier matching ^[a-zA-Z][a-zA-Z0-9_]{0,63}$, such as start_25; description is a nonempty string up to 2000 characters.',
      'inputSchema':
          'Object JSON Schema, including properties, required, additionalProperties:false. Preserve the schema; the host validates before execution.',
      'schemaKeywords':
          r'$schema,$id,$ref,$defs,definitions,title,description,default,examples,deprecated,readOnly,writeOnly,format,type,properties,required,additionalProperties,items,prefixItems,enum,const,anyOf,oneOf,allOf,not,minimum,maximum,exclusiveMinimum,exclusiveMaximum,multipleOf,minLength,maxLength,pattern,minItems,maxItems,uniqueItems,minProperties,maxProperties. Only bounded local refs; pattern normally forbids groups, alternatives and backreferences; the exact packageName pattern in the production handler catalog is also accepted. Unsupported assertions are rejected.',
      'permissions':
          'Known capabilities, including the handler/child action requirements. App permissions may additionally declare capabilities used for reading state.',
      'danger':
          'read | write | root; cannot weaken executor or child requirements.',
      'compatibility':
          'Version 1 HTML manifests remain valid. Version 2 supports web UI too, but cannot declare server.command or arbitrary executable code.',
    },
    'executors': {
      'native': {'kind': 'native', 'handler': 'device.screen.brightness.set'},
      'state': {
        'kind': 'state',
        'expressions': true,
        'patch': {
          'count': {r'$inc': 1},
        },
      },
      'preset': {
        'kind': 'preset',
        'steps': [
          {
            'handler': 'device.screen.brightness.set',
            'args': {'value': 77},
          },
          {
            'handler': 'device.audio.volume.set',
            'args': {'stream': 'music', 'value': 0},
          },
        ],
      },
      'presetRules':
          '1–8 reversible fixed device steps. Host saves previous values; only unchanged owned values can be restored.',
      'restore': {'kind': 'restore'},
      'sequence': {
        'kind': 'sequence',
        'steps': [
          {'action': 'focus_preset', 'arguments': {}, 'onFailure': 'continue'},
          {
            'action': 'record_start',
            'arguments': {'durationMs': 1500000},
          },
        ],
      },
      'sequenceRules':
          'References declared actions in this same manifest, in order. arguments defaults to {}. onFailure defaults to stop; continue allows ordinary failed/unsupported executor results only, never denied rights, consent, cancellation or changed app ownership. Cycles are forbidden. Child policies and confirmations apply separately. A failure stays a failure even when later steps run; result contains completedSteps, failedStep, failedSteps and partial effects. No automatic rollback; restore must be a declared step.',
      'templates':
          r'Native executors receive the original arguments. Preset/sequence templates may use {"$arg":"name"} for argument substitution. UI args use {"$value":true} for the selected control value.',
    },
    'expressions': {
      'scope':
          r'Only state.patch with expressions:true evaluates expressions. With the flag omitted/false, patches retain legacy literal JSON and $arg substitution, including literal keys that match new operators. Each patch atomically merges object fields recursively; arrays/scalars replace, null stores null. All expressions read the same pre-patch data. No JavaScript, shell or arbitrary code. Plain JSON and unknown $-prefixed keys remain literal; recognized expression operators must have valid operands.',
      r'$arg': {
        'example': {r'$arg': 'minutes'},
        'meaning': 'Argument value by exact argument key (not a dot path).',
      },
      r'$data': {
        'example': {r'$data': 'sessionsToday'},
        'meaning':
            'App data dot path (relative to data, not data.key). Missing value is null.',
      },
      r'$inc': {
        'example': {r'$inc': 1},
        'meaning':
            'Add numeric operand to previous number at the target patch field. Missing target starts at 0.',
      },
      r'$dec': {
        'example': {r'$dec': 1},
        'meaning': 'Subtract numeric operand from previous target number.',
      },
      r'$now': {
        'example': {r'$now': true},
        'meaning': 'Current epoch milliseconds; one captured time per patch.',
      },
      r'$today': {
        'example': {r'$today': true},
        'meaning':
            'Local calendar date YYYY-MM-DD, from the same captured time.',
      },
      r'$add': {
        'example': {
          r'$add': [
            {r'$now': true},
            1500000,
          ],
        },
        'meaning':
            'Sum a bounded list of numeric expressions (25-minute deadline example).',
      },
      r'$eq': {
        'example': {
          r'$eq': [
            {r'$data': 'sessionDay'},
            {r'$today': true},
          ],
        },
        'meaning': 'Compare two JSON values.',
      },
      r'$if': {
        'example': {
          r'$if': [
            {
              r'$eq': [
                {r'$data': 'sessionDay'},
                {r'$today': true},
              ],
            },
            {r'$inc': 1},
            1,
          ],
        },
        'meaning':
            '[boolean condition, then, else]; only the chosen branch evaluates. Example resets daily counter on date change.',
      },
    },
    'components': {
      'screen': {'version': 1, 'components': []},
      'textFields':
          'title,label,text,description,unit,emptyText accept strings or locale maps {en,ru,zh,zh_Hans,zh_Hant}.',
      'card': {'type': 'card', 'title': 'Session', 'children': []},
      'text': {'type': 'text', 'text': 'Ready'},
      'value': {
        'type': 'value',
        'label': 'Started',
        'bind': 'data.startedAt',
        'format': 'datetime',
      },
      'button': {
        'type': 'button',
        'label': 'Start',
        'action': 'start_25',
        'args': {},
      },
      'switch': {
        'type': 'switch',
        'label': 'Torch',
        'bind': 'device.flashlight.enabled',
        'action': 'torch',
        'args': {
          'enabled': {r'$value': true},
        },
      },
      'slider': {
        'type': 'slider',
        'label': 'Brightness',
        'bind': 'device.screen.brightness',
        'min': 0,
        'max': 255,
        'step': 1,
        'action': 'brightness',
        'args': {
          'value': {r'$value': true},
        },
      },
      'list': {
        'type': 'list',
        'label': 'Choices',
        'bind': 'data.selected',
        'options': [
          {'label': 'Work', 'value': 'work'},
        ],
        'action': 'choose',
        'args': {
          'value': {r'$value': true},
        },
      },
      'listFields':
          'Without options, bind supplies a list. labelKey/valueKey select item fields (default label/value); emptyText is shown for an empty list.',
      'indicator': {
        'type': 'indicator',
        'label': 'Battery',
        'bind': 'device.battery.levelPercent',
        'min': 0,
        'max': 100,
        'unit': '%',
      },
      'timer': {
        'type': 'timer',
        'label': 'Remaining',
        'bind': 'data.endsAt',
        'mode': 'countdown',
      },
      'timerRules':
          'bind is an epoch-ms deadline (countdown, default) or start (elapsed). H:mm:ss display clamps at zero. No automatic action at expiry. One UI tick only while the panel is visible/resumed; no background timer or process.',
      'progress': {
        'type': 'progress',
        'label': 'Session',
        'bind': 'data.endsAt',
        'startBind': 'data.startedAt',
      },
      'progressRules':
          'Elapsed fraction (now-start)/(end-start), clamped 0–1. Missing or invalid time is unavailable, never invented.',
      'formats':
          'value/indicator support bytes, duration (milliseconds), date, time, datetime (epoch ms or ISO date/time string), in current locale.',
      'controls':
          'action must name an existing manifest action. enabled:false or disabled:true disables it. Sliders can use minBind/maxBind instead of numeric bounds. values maps raw values to display text.',
    },
    'bindings': {
      'roots':
          'data.<dot.path>, device.<group>.<field>, revision. Missing data/sensors are null with an unavailable reason; do not treat null as zero.',
      'battery': [
        'levelPercent',
        'temperatureC',
        'charging',
        'status',
        'plugged',
        'voltageMv',
        'currentMicroamps',
        'currentAverageMicroamps',
        'chargeCounterMicroampHours',
        'energyNanowattHours',
        'chargeTimeRemainingMs',
        'cycleCount',
        'powerSave',
      ],
      'screen': [
        'brightness',
        'brightnessMode',
        'timeoutMs',
        'interactive',
        'canWrite',
        'refreshRateHz',
      ],
      'audio': [
        'volumes.<stream>.value',
        'volumes.<stream>.min',
        'volumes.<stream>.max',
        'ringerMode',
        'dnd',
        'canAccessDnd',
        'canChangeDnd',
      ],
      'connectivity': [
        'connected',
        'validated',
        'metered',
        'networkType',
        'wifiEnabled',
        'bluetoothEnabled',
        'mobileDataEnabled',
        'airplaneMode',
      ],
      'flashlight': ['available', 'enabled', 'canControl'],
      'system': [
        'sdkInt',
        'uptimeMs',
        'androidVersion',
        'manufacturer',
        'model',
        'appVersion',
        'totalRamBytes',
        'availableRamBytes',
        'totalStorageBytes',
        'freeStorageBytes',
        'rootAvailable',
        'rootReason',
        'stoppableApps',
      ],
      'units':
          'brightness 0–255; temperature Celsius; time ms; storage/memory bytes; battery percent. Audio readback uses platform stream indices (value/min/max); the setter validates 0–100 and Android may clamp to stream maximum.',
    },
    'deviceHandlers': {
      for (final handler in MiniAppDeviceService.handlers)
        handler: {
          'inputSchema': MiniAppDeviceService.inputSchemaFor(handler),
          'permissions': MiniAppDeviceService.permissionsFor(handler).toList(),
          'danger': MiniAppDeviceService.requiresConfirmation(handler)
              ? 'root'
              : MiniAppDeviceService.isMutation(handler)
              ? 'write'
              : 'read',
        },
    },
    'permissions': {
      'capabilities': MiniAppManifest.knownCapabilities.toList()..sort(),
      'rules':
          'Explicit per-app user grants checked on every entry and every sequence step. AI additionally requires actions.ai. Write steps use normal tool approval; root needs its own capability and confirmation. Full trust skips consent only, never app grants or Android permissions. Revoke/cancel halts later steps. No inherited shell/root/Wi-Fi access. Device mutations from Wi-Fi or background jobs are forbidden.',
      'android':
          'WRITE_SETTINGS is separately needed for brightness/timeout. DND needs Android policy access and global DND cannot be changed by Moru on Android 15+. Use device.settings.open page:dnd. Root handlers are fixed operations only with confirmation and result verification.',
      'results':
          'Never call opened_settings, permission_required, denied, unsupported, failed or unknown_after_timeout a successful setting change. Inspect each sequence/preset step and partial result.',
    },
    'examples': {
      'phone-control': {
        'moru-app.json': PhoneControlMiniApp.manifest(
          lookupAppLocalizations(const Locale('en')),
        ),
        'screen.json': PhoneControlMiniApp.screen(),
      },
      'focus': {
        'moru-app.json': FocusMiniApp.manifest(
          lookupAppLocalizations(const Locale('en')),
        ),
        'screen.json': FocusMiniApp.screen(),
      },
    },
    'limits': {
      'actions': 64,
      'screenBytes': 256 * 1024,
      'components': 256,
      'componentDepth': 12,
      'presetSteps': 8,
      'sequenceDepth': 8,
      'expandedSequenceSteps': 32,
      'templateBytes': 64 * 1024,
      'expressionDepth': 20,
      'expressionOperatorNodes': 1024,
      'expressionEvaluationVisits': 65536,
      'arrayItems': 256,
    },
  };
}
