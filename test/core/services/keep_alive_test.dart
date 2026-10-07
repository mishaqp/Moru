import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/keep_alive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.process.keep_alive');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ProcessKeepAlive keepAlive;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    keepAlive = ProcessKeepAlive(channel: channel);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('a rejected foreground hold is observable to its caller', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);

    await expectLater(
      keepAlive.hold('job', 'Running command'),
      throwsException,
    );
  });

  test(
    'a platform failure never exposes native details to the caller',
    () async {
      const privateDetail = 'token=private-native-value';
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'fgs_start_failed',
          message: privateDetail,
          details: privateDetail,
        );
      });

      Object? failure;
      try {
        await keepAlive.hold('job', 'Running command');
      } catch (error) {
        failure = error;
      }
      expect(failure, isNotNull);
      expect('$failure', isNot(contains(privateDetail)));
    },
  );

  test('a hold completes only after the native acknowledgement', () async {
    final promoted = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (_) => promoted.future);
    var accepted = false;
    final holding = keepAlive.hold('job', 'Running command').then((_) {
      accepted = true;
    });
    await pumpEventQueue();
    expect(accepted, isFalse);
    promoted.complete(true);
    await holding;
    expect(accepted, isTrue);
  });
}
