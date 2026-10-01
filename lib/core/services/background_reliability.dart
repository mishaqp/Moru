import '../models/mobile_background_settings.dart';
import 'mobile_background.dart';

enum BackgroundReliabilityRisk {
  disabled,
  restricted,
  standby,
  manufacturer,
  interrupted,
  protectionUnavailable,
}

/// An active task is the only reason to show contextual power advice.
BackgroundReliabilityRisk? backgroundReliabilityRisk({
  required MobileBackgroundSettings settings,
  required MobileBackgroundStatus status,
  required bool hasActiveWork,
}) {
  if (!hasActiveWork || settings.reliabilityHintDismissed) return null;
  if (!settings.androidEnabled && !status.flag('foregroundServiceActive')) {
    return BackgroundReliabilityRisk.disabled;
  }
  if (status.flag('backgroundRestricted')) {
    return BackgroundReliabilityRisk.restricted;
  }
  if (status.flag('lowPowerStandbyEnabled') &&
      !status.flag('lowPowerStandbyExempt')) {
    return BackgroundReliabilityRisk.standby;
  }
  final manufacturer = status.text('manufacturer').trim().toLowerCase();
  if (const {
        'vivo',
        'iqoo',
        'xiaomi',
        'redmi',
        'poco',
      }.contains(manufacturer) &&
      !status.flag('batteryExempt')) {
    return BackgroundReliabilityRisk.manufacturer;
  }
  final error = status.text('lastError');
  if (error == 'previous_process_terminated') {
    return BackgroundReliabilityRisk.interrupted;
  }
  if (error.startsWith('foreground_service_') &&
      !status.flag('foregroundServiceActive')) {
    return BackgroundReliabilityRisk.protectionUnavailable;
  }
  return null;
}
