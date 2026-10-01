import 'package:Kelivo/core/models/mobile_background_settings.dart';
import 'package:Kelivo/core/services/background_reliability.dart';
import 'package:Kelivo/core/services/mobile_background.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const enabled = MobileBackgroundSettings(androidEnabled: true);

  BackgroundReliabilityRisk? risk(
    Map<String, dynamic> status, {
    bool active = true,
    MobileBackgroundSettings settings = enabled,
  }) => backgroundReliabilityRisk(
    settings: settings,
    status: MobileBackgroundStatus(status),
    hasActiveWork: active,
  );

  test('normal Pixel foreground work does not demand a battery exemption', () {
    expect(risk({'manufacturer': 'Google', 'batteryExempt': false}), isNull);
  });

  test('idle or dismissed advice remains hidden despite restrictions', () {
    expect(risk({'backgroundRestricted': true}, active: false), isNull);
    final dismissed = MobileBackgroundSettings.fromJson({
      ...enabled.toJson(),
      'reliabilityHintDismissed': true,
    });
    expect(risk({'backgroundRestricted': true}, settings: dismissed), isNull);
  });

  test(
    'disabled execution explains the existing setting without enabling it',
    () {
      const savedOff = MobileBackgroundSettings();
      expect(risk({}, settings: savedOff), BackgroundReliabilityRisk.disabled);
      expect(savedOff.androidEnabled, isFalse);
      expect(savedOff.notificationsEnabled, isFalse);
      expect(
        risk({'foregroundServiceActive': true}, settings: savedOff),
        isNull,
        reason: 'An explicit server holder already protects its running task.',
      );
    },
  );

  test('Android background restriction is a concrete risk for a live task', () {
    expect(
      risk({'backgroundRestricted': true}),
      BackgroundReliabilityRisk.restricted,
    );
  });

  test(
    'Low Power Standby exemption is independent of battery allowlisting',
    () {
      expect(
        risk({
          'lowPowerStandbyEnabled': true,
          'lowPowerStandbyExempt': false,
          'batteryExempt': true,
        }),
        BackgroundReliabilityRisk.standby,
      );
      expect(
        risk({'lowPowerStandbyEnabled': true, 'lowPowerStandbyExempt': true}),
        isNull,
      );
    },
  );

  test('Vivo and Xiaomi advice needs active work and missing allowlisting', () {
    for (final manufacturer in ['vivo', 'iQOO', 'XIAOMI', 'Redmi', 'POCO']) {
      expect(
        risk({'manufacturer': manufacturer, 'batteryExempt': false}),
        BackgroundReliabilityRisk.manufacturer,
      );
      expect(
        risk({'manufacturer': manufacturer, 'batteryExempt': true}),
        isNull,
      );
    }
  });

  test(
    'previous process termination is advice for the next active task only',
    () {
      expect(
        risk({'lastError': 'previous_process_terminated'}),
        BackgroundReliabilityRisk.interrupted,
      );
      expect(
        risk({'lastError': 'previous_process_terminated'}, active: false),
        isNull,
      );
    },
  );

  test(
    'saved settings round trip without changing existing explicit choices',
    () {
      final original = {
        'androidEnabled': false,
        'notificationsEnabled': true,
        'privacyMode': true,
        'overlayEnabled': false,
        'reliabilityHintDismissed': true,
      };
      final restored = MobileBackgroundSettings.fromJson(original);
      expect(restored.toJson()['reliabilityHintDismissed'], isTrue);
      expect(restored.androidEnabled, isFalse);
      expect(restored.notificationsEnabled, isTrue);
      expect(restored.privacyMode, isTrue);
      expect(restored.overlayEnabled, isFalse);
      expect(
        restored
            .copyWith(liveUpdatesEnabled: true)
            .toJson()['reliabilityHintDismissed'],
        isTrue,
      );
      expect(
        MobileBackgroundSettings.fromJson(
          {},
        ).toJson()['reliabilityHintDismissed'],
        isFalse,
      );
    },
  );
}
