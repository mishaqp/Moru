# Moru: только Android arm64-v8a

Moru — личный Android-форк Kelivo. Выпускается один APK для **arm64-v8a**.
iOS, macOS, Windows, настольный Linux и Web не являются целями приложения.
Nightly и сборки по расписанию не добавляются. Linux в CI — машина для проверок.
Версия остаётся **0.1.47+48**.

## Что удалено

- ПК-ветки интерфейса, старые диалоги ассистента, экспорта и ASR, вызовы
  системного терминала и файлового менеджера, перетаскивание файлов с ПК.
  `isDesktop` в Dart-коде отсутствует.
- Apple-настройки уведомлений, недостижимые Apple-ветки синхронизации файлов,
  поля iSH и обработчик выхода из ПК-приложения. Резервные копии и миграция
  используют прежние Android-сохранения, OAuth — прежний Android-браузер
  с сохранённым loopback для Claude и ChatGPT.
- `window_manager`, `desktop_drop` и четыре прямых override Sherpa для
  iOS/Linux/macOS/Windows. `sherpa_onnx` и `sherpa_onnx_android` сохранены.
- Пять нативных тестов ПК/iOS и тесты удалённого кода. Одиннадцать неиспользуемых
  ключей убраны из всех пяти ARB; Dart-локализации пересозданы.

Платформенные проекты `ios/`, `macos/`, `windows/`, `linux/`, `web/` и
`lib/desktop/` не возвращаются в git. `flutter pub get` может создавать
регистраторы сторонних плагинов в игнорируемых папках. Федеративные Flutter-
плагины, включая Sherpa, объявляют другие платформы транзитивно; это метаданные
зависимостей, а не дополнительные цели Moru. В APK проверяются реальные библиотеки.

## Что сохранено

PRoot/Linux, рабочая папка, навыки, терминал/PTY и STDIO MCP работают внутри
Android. Сохранены `HomeDesktopScaffold`, `AppBreakpoints.tablet`, широкие панели
и прежние пороги ширины для планшетов, складных устройств и альбомной ориентации.
`ResponsiveHelper.isWide` описывает размер Android-экрана.

Настройки, чаты, Documents, applicationId и подпись не мигрируются. Старые
ПК-ключи остаются в хранилище; `desktop_send_shortcut_v1` продолжает обслуживать
внешнюю Android-клавиатуру. Старые пути вложений ПК/iOS, идентификаторы инструментов
и карточки их результатов нужны для импортированных чатов и резервных копий.
Виджеты с названием `Ios` описывают стиль интерфейса Android. Режим «версия для ПК»
и соответствующие User-Agent нужны Android-браузеру и поиску.

## Допустимые Linux-проверки в тестах

В `lib/` нет проверок платформ ПК/iOS. В тестах остаются восемь `Platform.isLinux`
в шести файлах: они запускают POSIX-процессы на CI для проверки Android-команд,
их отмены и STDIO MCP, без создания Linux-приложения:

- `test/core/services/acp/acp_agent_manager_test.dart`;
- `test/core/services/workspace/workspace_tools_service_test.dart`;
- `test/core/services/workspace/generation_cancellation_test.dart`;
- `test/core/services/mcp/workspace_stdio_transport_test.dart`;
- `test/support/fake_workspace_runtime.dart`;
- `test/support/fake_workspace_runtime_test.dart`.

`tool/test_android_only_policy.py` запрещает возвращать платформенные папки,
ПК/iOS-ветки Dart, удалённые пакеты, Apple API, старые виджеты и нативные тесты.
Исключение `Platform.isLinux` ограничено перечисленными файлами.

## Сборка и проверка

Flutter **3.44.9**, существующие версии инструментов и зависимостей:

```bash
flutter build apk --debug --target-platform=android-arm64
python3 tool/verify_apk_arm64.py build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release --target-platform=android-arm64
```

Без универсального APK и `split-per-ABI`. Gradle, CMake и загрузка PRoot выбирают
arm64-v8a. Четыре библиотеки PRoot закреплены SHA-256 в `tool/proot_checksums.txt`.
Версия Termux PRoot и два её хеша (`libproot_exec.so`, `libproot_loader.so`)
обновляются вместе, когда прежняя сборка исчезает из пула; текущая версия
**5.1.107.96** закреплена в v0.1.47. Проверяются пути ZIP и архитектура ELF.

Перед PR выполняется полный чеклист из `AGENTS.md`: форматирование изменённых
файлов, анализатор, все Flutter-тесты и три Python-набора. Android CI дополнительно
проверяет JVM-тесты, сборку APK, подпись и R8 keep rules. Widget-тесты проверяют
телефон и широкие экраны, выбор даты и ASR; тесты хранения — старые настройки и чаты.
Эти проверки не заменяют ручной запуск на телефоне и планшете.

Очистка проверена на всех трёх этапах: форматтер, анализатор, затронутые тесты
и arm64 debug-APK. Итоговый полный Flutter-набор: **7 541 тест**; Python:
**14 + 6 + 3**. В итоговом APK только arm64-v8a и 19 нативных библиотек.

## Идентичность релиза

Пакет остаётся **`com.mishaqp.moru`**, сертификат — из
`.github/moru-signing-cert-sha256.txt`, русская локаль сохранена.
Стабильный релиз публикуется вручную из master с существующими секретами keystore;
при отсутствии прежнего ключа сборка завершается ошибкой. Debug-APK предназначен
для проверки. Workflow сохраняет один APK и отдельный архив диагностики.
