import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/services/sandbox/mobile_workspace_bootstrap.dart';

import '../../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EnvironmentProvider env;

  setUp(() async {
    env = EnvironmentProvider(preferences: createBusinessTestPreferences());
    await env.loaded;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('returns null on desktop', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(await createMobileWorkspaceStack(env: env), isNull);
  });
}
