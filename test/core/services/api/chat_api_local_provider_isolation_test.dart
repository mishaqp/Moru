import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a saved LiteRT provider cannot start a generation after retirement',
      () async {
    final config = ProviderConfig(
      id: 'litert-local',
      enabled: true,
      name: 'Local',
      apiKey: '',
      baseUrl: '',
      providerType: ProviderKind.local,
      models: const ['old-model'],
    );

    await expectLater(
      ChatApiService.sendMessageStream(
        config: config,
        modelId: 'old-model',
        messages: const [],
      ),
      emitsError(isA<StateError>()),
    );
  });
}
