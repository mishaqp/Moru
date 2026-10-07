import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/environment_state.dart';
import 'package:Kelivo/core/providers/environment_provider.dart';
import 'package:Kelivo/core/services/sandbox/environment_dependencies.dart';
import 'package:Kelivo/features/workspace/widgets/environment/environment_dependencies_section.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_checkbox.dart';

import '../../../core/services/sandbox/dependency_test_runtime.dart';
import '../../../support/business_test_harness.dart';
import 'environment_test_fakes.dart';

void main() {
  late EnvironmentProvider env;
  late DependencyTestRuntime runtime;
  late EnvironmentDependencies service;

  Future<void> pump(WidgetTester tester, {required bool alpine}) async {
    await tester.runAsync(() async {
      env = EnvironmentProvider(preferences: createBusinessTestPreferences());
      await env.loaded;
      await env.setState(
        EnvironmentState(
          phase: EnvironmentPhase.ready,
          distro: alpine ? 'alpine' : 'ubuntu',
          arch: 'arm64',
        ),
      );
      runtime = DependencyTestRuntime()
        ..installed.addAll({
          EnvironmentDependency.node,
          EnvironmentDependency.python,
        })
        ..versions[EnvironmentDependency.node] = 'v24.1.0';
      service = EnvironmentDependencies(
        runtime: runtime,
        env: env,
        alpine: alpine,
        mirrors: FakeMirrorService(env),
      );
      await service.refresh();
    });
    addTearDown(service.dispose);
    addTearDown(env.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: env,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [
                EnvironmentDependenciesSection(service: service, enabled: true),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20 && service.busy; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder row(EnvironmentDependency dependency) =>
      find.byKey(ValueKey('environment-dependency-${dependency.name}'));

  testWidgets('packages are grouped, show versions, and the glibc layer is '
      'offered on Alpine only', (tester) async {
    await pump(tester, alpine: false);
    expect(find.text('Development'), findsOneWidget);
    expect(find.text('SSH'), findsOneWidget);
    expect(find.text('v24.1.0'), findsOneWidget);
    expect(row(EnvironmentDependency.ripgrep), findsOneWidget);
    expect(row(EnvironmentDependency.compat), findsNothing);
    // Without the agents provider the agent group is not shown.
    expect(find.text('AI agents'), findsNothing);

    await pump(tester, alpine: true);
    expect(row(EnvironmentDependency.compat), findsOneWidget);
  });

  testWidgets('ticked packages install together in one transaction', (
    tester,
  ) async {
    await pump(tester, alpine: true);
    expect(
      find.byKey(EnvironmentDependenciesSection.installSelectedKey),
      findsNothing,
    );
    for (final dependency in [
      EnvironmentDependency.ripgrep,
      EnvironmentDependency.bash,
    ]) {
      await tapVisible(
        tester,
        find.byKey(ValueKey('environment-pick-${dependency.name}')),
      );
    }
    expect(find.text('Install selected (2)'), findsOneWidget);
    // Installed packages stay ticked and cannot be ticked off.
    final node = tester.widget<IosCheckbox>(
      find.byKey(const ValueKey('environment-pick-node')),
    );
    expect(node.value, isTrue);
    expect(node.onChanged, isNull);

    runtime.requests.clear();
    await tester.ensureVisible(
      find.byKey(EnvironmentDependenciesSection.installSelectedKey),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(EnvironmentDependenciesSection.installSelectedKey),
    );
    await settle(tester);
    final installs = runtime.requests
        .where((r) => r.command.contains('apk --wait 60 add'))
        .toList();
    expect(installs, hasLength(1));
    expect(installs.single.command, contains('bash'));
    expect(installs.single.command, contains('ripgrep'));
    expect(
      service.status(EnvironmentDependency.ripgrep),
      DependencyStatus.installed,
    );
    expect(
      service.status(EnvironmentDependency.bash),
      DependencyStatus.installed,
    );
    expect(
      find.byKey(EnvironmentDependenciesSection.installSelectedKey),
      findsNothing,
    );
  });
}
