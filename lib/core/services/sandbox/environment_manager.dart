import 'dart:async';

import 'package:Kelivo/core/models/environment_state.dart';
import 'package:Kelivo/core/providers/environment_provider.dart';

abstract class EnvironmentManager {
  EnvironmentProvider get env;
  Set<MirrorCategory> get mirrorCategories;
  Future<void> install({void Function(EnvironmentState)? onProgress});
  Future<void> cancel();
  Future<void> repair();
  Future<void> reset();
  Future<bool> checkForUpdate();
  Future<void> ensureInstalled();
}
