import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/notification_service.dart';
import 'package:Kelivo/features/settings/pages/display_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/theme/palettes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('notification presentation switches RU to EN without changing payload IDs', () async {
    final ru = await AppLocalizations.delegate.load(const Locale('ru'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    const conversation = 'unchanged-conversation-id';
    final originalId = NotificationService.notificationIdForConversation(conversation);
    await NotificationService.configureLocalizations(ru);
    expect(NotificationService.completionText.title, 'Генерация завершена');
    expect(NotificationService.completionText.body, ru.notificationChatCompletedBody);
    expect(NotificationService.completionText.channelName, 'Фоновая работа чата');
    await NotificationService.configureLocalizations(en);
    expect(NotificationService.completionText.title, 'Generation complete');
    expect(NotificationService.completionText.channelName, 'Chat Background');
    expect(NotificationService.notificationIdForConversation(conversation), originalId);
    expect(NotificationService.conversationIdFromPayload('chat-complete:$conversation'), conversation);
    await NotificationService.configureLocalizations(ru);
  });

  test('all built-in palettes have RU names while IDs and English stay intact', () async {
    final ru = await AppLocalizations.delegate.load(const Locale('ru'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));
    for (final id in [
      'default', 'blue', 'green', 'purple', 'yellow',
      'smoky_rose', 'terracotta', 'monochrome', 'doc_theme',
    ]) {
      final palette = ThemePalettes.byId(id);
      expect(palette.id, id);
      expect(palette.localizedName(ru), matches(RegExp('[А-Яа-яЁё]')));
      expect(palette.localizedName(en), palette.displayNameEn);
      expect(palette.localizedName(zh), palette.displayNameZh);
    }
  });

  testWidgets('Android display settings offer Russian and retain a chosen English locale', (tester) async {
    await tester.view.reset();
    await tester.binding.setSurfaceSize(const Size(440, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = await createBusinessTestHarness(initial: const {'app_locale_v1': 'ru'});
    final settings = SettingsProvider(harness.preferences);
    await settings.loaded;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settings,
      child: Consumer<SettingsProvider>(builder: (context, value, _) => MaterialApp(
        locale: value.appLocaleForMaterialApp,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const DisplaySettingsPage(),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Язык приложения'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    await tester.tap(find.text('Язык приложения'));
    await tester.pumpAndSettle();
    expect(find.text('Русский'), findsWidgets);
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.text(en.displaySettingsPageLanguageEnglishLabel).last);
    await tester.pumpAndSettle();
    expect(settings.appLocaleForMaterialApp, const Locale('en', 'US'));
    expect(harness.preferences.get('app_locale_v1'), 'en_US');
    expect(find.text('App Language'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
