// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get settingsSearchHint => 'Поиск настроек';

  @override
  String get settingsSearchCancel => 'Отмена';

  @override
  String get settingsSearchClear => 'Очистить поиск';

  @override
  String get settingsSearchSuggestions => 'Быстрый доступ';

  @override
  String get settingsSearchNoResults => 'Настройки не найдены';

  @override
  String get settingsSearchNoResultsHint =>
      'Попробуйте другое название или более короткое слово.';

  @override
  String settingsSearchResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count результата',
      many: '$count результатов',
      few: '$count результата',
      one: '$count результат',
    );
    return '$_temp0';
  }

  @override
  String get helloWorld => 'Привет, мир!';

  @override
  String get settingsPageBackButton => 'Назад';

  @override
  String get settingsPageTitle => 'Настройки';

  @override
  String get settingsPageDarkMode => 'Тёмная';

  @override
  String get settingsPageLightMode => 'Светлая';

  @override
  String get settingsPageSystemMode => 'Системная';

  @override
  String get settingsPageWarningMessage =>
      'Некоторые сервисы не настроены; часть функций может быть недоступна.';

  @override
  String get settingsPageGeneralSection => 'Основные';

  @override
  String get settingsPageColorMode => 'Цветовой режим';

  @override
  String get settingsPageDisplay => 'Внешний вид и поведение';

  @override
  String get settingsPageDisplaySubtitle =>
      'Настройки оформления, поведения и взаимодействия';

  @override
  String get settingsPageAssistant => 'Ассистент';

  @override
  String get settingsPageAssistantSubtitle => 'Ассистент и стиль по умолчанию';

  @override
  String get settingsPageModelsServicesSection => 'Модели и сервисы';

  @override
  String get settingsPageDefaultModel => 'Модель по умолчанию';

  @override
  String get settingsPageProviders => 'Провайдеры';

  @override
  String get settingsPageHotkeys => 'Горячие клавиши';

  @override
  String get settingsPageSearch => 'Поиск';

  @override
  String get settingsPageTts => 'Синтез речи';

  @override
  String get settingsPageMcp => 'MCP';

  @override
  String get settingsPageQuickPhrase => 'Быстрая фраза';

  @override
  String get settingsPageInstructionInjection => 'Добавление инструкций';

  @override
  String get settingsPageDataSection => 'Данные';

  @override
  String get settingsPageBackup => 'Резервное копирование';

  @override
  String get settingsPageChatStorage => 'Хранилище чатов';

  @override
  String get settingsPageCalculating => 'Подсчёт…';

  @override
  String get storageSpacePageTitle => 'Занятое место';

  @override
  String get storageSpaceRefreshTooltip => 'Обновить';

  @override
  String get storageSpaceLoadFailed => 'Не удалось узнать объём занятого места';

  @override
  String get storageSpaceTotalLabel => 'Занято';

  @override
  String storageSpaceClearableLabel(String size) {
    return 'Можно очистить: $size';
  }

  @override
  String storageSpaceClearableHint(String size) {
    return 'Можно безопасно очистить: $size';
  }

  @override
  String get storageSpaceCategoryImages => 'Изображения';

  @override
  String get storageSpaceCategoryFiles => 'Файлы';

  @override
  String get storageSpaceCategoryFonts => 'Шрифты';

  @override
  String get storageSpaceCategoryLocalModels => 'Локальные модели';

  @override
  String get storageSpaceOtherHint =>
      'Шрифты, загруженные локальные модели и другие файлы приложения.';

  @override
  String get storageSpaceSubOtherApp => 'Файлы приложения';

  @override
  String get storageSpaceCategoryChatData => 'История чатов';

  @override
  String get storageSpaceCategoryLegacyChatData => 'История чатов (старая)';

  @override
  String get storageSpaceCategoryRestoreTraces => 'Остатки восстановления';

  @override
  String get storageSpaceCategoryDisplacedDatabases =>
      'Сохранённые старые базы';

  @override
  String get storageSpaceSubDisplacedDatabases =>
      'Сохранены перед автоматическим пересозданием';

  @override
  String get storageSpaceClearDisplacedDatabasesConfirmMessage =>
      'Удалить эти сохранённые базы данных? Приложение сохранило их при пересоздании базы. В них могут находиться единственные уцелевшие копии чатов и настроек. Отменить удаление нельзя.';

  @override
  String get storageSpaceRestoreTracesHint =>
      'Предыдущие снимки данных, оставшиеся после завершённых восстановлений. Их очистка не затрагивает текущие данные приложения.';

  @override
  String get storageSpaceClearRestoreTracesButton =>
      'Очистить остатки восстановления';

  @override
  String get storageSpaceClearDisplacedDatabasesButton => 'Удалить старые базы';

  @override
  String get storageSpaceClearRestoreTracesConfirmMessage =>
      'Удалить снимки завершённых восстановлений? Текущая база данных, настройки и файлы не будут затронуты.';

  @override
  String get storageSpaceSubCompletedRestoreRuns =>
      'Снимки завершённых восстановлений';

  @override
  String get storageSpaceCategoryAssistantData => 'Ассистенты';

  @override
  String get storageSpaceCategoryCache => 'Кэш';

  @override
  String get storageSpaceCategoryLogs => 'Журналы';

  @override
  String get storageSpaceCategoryOther => 'Другое';

  @override
  String get storageSpaceSafeToClearHint =>
      'Можно безопасно очистить. История чатов не пострадает.';

  @override
  String get storageSpaceLegacyChatDataHint =>
      'Это сохранённые файлы Hive, оставшиеся до перехода на SQLite. Их очистка не удаляет текущую историю чатов.';

  @override
  String get storageSpaceNotSafeToClearHint =>
      'Может затронуть историю чатов. Удаляйте осторожно.';

  @override
  String get storageSpaceBreakdownTitle => 'Подробности';

  @override
  String get storageSpaceSubChatMessages => 'Сообщения';

  @override
  String get storageSpaceSubChatConversations => 'Диалоги';

  @override
  String get storageSpaceSubChatToolEvents => 'События инструментов';

  @override
  String get storageSpaceSubChatDatabase => 'База данных чатов';

  @override
  String get storageSpaceSubChatWriteAheadLog => 'Журнал упреждающей записи';

  @override
  String get storageSpaceSubChatSharedMemory => 'Индекс общей памяти';

  @override
  String get storageSpaceSubAssistantAvatars => 'Аватары';

  @override
  String get storageSpaceSubAssistantImages => 'Изображения';

  @override
  String get storageSpaceSubCacheAvatars => 'Кэш аватаров';

  @override
  String get storageSpaceSubCacheOther => 'Другой кэш';

  @override
  String get storageSpaceSubCacheSystem => 'Системный кэш';

  @override
  String get storageSpaceSubLogsContext => 'Журналы контекста';

  @override
  String get storageSpaceSubLogsFlutter => 'Журналы Flutter';

  @override
  String get storageSpaceSubLogsRequests => 'Сетевые журналы';

  @override
  String get storageSpaceSubLogsOther => 'Другие журналы';

  @override
  String get storageSpaceClearConfirmTitle => 'Подтверждение очистки';

  @override
  String storageSpaceClearConfirmMessage(String targetName) {
    return 'Очистить «$targetName»?';
  }

  @override
  String get storageSpaceClearButton => 'Очистить';

  @override
  String storageSpaceClearDone(String targetName) {
    return 'Очищено: $targetName';
  }

  @override
  String storageSpaceClearFailed(String error) {
    return 'Не удалось очистить: $error';
  }

  @override
  String get storageSpaceClearAvatarCacheButton => 'Очистить кэш аватаров';

  @override
  String get storageSpaceClearCacheButton => 'Очистить кэш';

  @override
  String get storageSpaceClearLogsButton => 'Очистить журналы';

  @override
  String get storageSpaceClearLegacyChatDataButton =>
      'Очистить старую историю чатов';

  @override
  String get storageSpaceExportLegacyChatFileButton => 'Экспорт';

  @override
  String storageSpaceExportDone(Object fileName) {
    return 'Экспортировано: $fileName';
  }

  @override
  String storageSpaceExportFailed(Object error) {
    return 'Не удалось экспортировать: $error';
  }

  @override
  String get storageSpaceClearLegacyChatDataConfirmMessage =>
      'Удалить сохранённые файлы старых чатов? Текущая история чатов в SQLite останется доступной.';

  @override
  String get storageSpaceViewLogsButton => 'Просмотреть журналы';

  @override
  String get storageSpaceDeleteConfirmTitle => 'Подтверждение удаления';

  @override
  String storageSpaceDeleteUploadsConfirmMessage(int count) {
    return 'Удалить объекты ($count) и связанные с ними копии вложений в диалогах? Эти вложения больше не будут доступны в истории чатов.';
  }

  @override
  String storageSpaceDeletedUploadsDone(int count) {
    return 'Удалено объектов: $count';
  }

  @override
  String get storageSpaceNoUploads => 'Нет объектов';

  @override
  String get storageSpaceSelectAll => 'Выбрать всё';

  @override
  String get storageSpaceClearSelection => 'Снять выделение';

  @override
  String storageSpaceSelectedCount(int count) {
    return 'Выбрано: $count';
  }

  @override
  String storageSpaceUploadsCount(int count) {
    return 'Объектов: $count';
  }

  @override
  String get storageSpaceSourceLabel => 'Источник';

  @override
  String get storageSpaceSourceAll => 'Все';

  @override
  String get storageSpaceSourceUserUpload => 'Загрузки пользователя';

  @override
  String get storageSpaceSourceAssistant => 'Ассистент';

  @override
  String get storageSpaceSortLabel => 'Сортировка';

  @override
  String get storageSpaceSortNewest => 'Сначала новые';

  @override
  String get storageSpaceSortOldest => 'Сначала старые';

  @override
  String get storageSpaceSortLargest => 'Сначала большие';

  @override
  String get storageSpaceSortSmallest => 'Сначала маленькие';

  @override
  String get settingsPageAboutSection => 'О приложении';

  @override
  String get settingsPageAbout => 'О приложении';

  @override
  String get settingsPageStatistics => 'Статистика';

  @override
  String get settingsPageDocs => 'Документация';

  @override
  String get settingsPageLogs => 'Журналы';

  @override
  String get settingsPageSponsor => 'Поддержать';

  @override
  String get settingsPageShare => 'Поделиться';

  @override
  String get statsPageTitle => 'Статистика';

  @override
  String get statsPageRangeAllTime => 'За всё время';

  @override
  String get statsPageRangeLast30Days => 'За последние 30 дней';

  @override
  String get statsPageRangePreviousMonth => 'За прошлый месяц';

  @override
  String get statsPageRangePreviousQuarter => 'За прошлый квартал';

  @override
  String get statsPageRangeCustom => 'Свой вариант';

  @override
  String get statsPageHeatmapTitle => 'Карта активности чатов';

  @override
  String get statsPageHeatmapLess => 'Меньше';

  @override
  String get statsPageHeatmapMore => 'Больше';

  @override
  String get statsPageSummaryTitle => 'Обзор';

  @override
  String get statsPageTotalConversations => 'Всего диалогов';

  @override
  String get statsPageTotalMessages => 'Всего сообщений';

  @override
  String get statsPageInputTokens => 'Входные токены';

  @override
  String get statsPageOutputTokens => 'Выходные токены';

  @override
  String get statsPageCachedTokens => 'Кэшированные токены';

  @override
  String get statsPageLaunchCount => 'Запуски приложения';

  @override
  String get statsPageUsageTrendTitle => 'Динамика использования';

  @override
  String get statsPageModelUsageTitle => 'Использование моделей';

  @override
  String get statsPageAssistantUsageTitle => 'Использование ассистентов';

  @override
  String get statsPageTopicVolumeTitle => 'Объём тем';

  @override
  String get statsPageModelColumn => 'Модель';

  @override
  String get statsPageAssistantColumn => 'Ассистент';

  @override
  String get statsPageTopicColumn => 'Тема';

  @override
  String get statsPageMessagesColumn => 'Сообщения';

  @override
  String get statsPageTopicsColumn => 'Темы';

  @override
  String get statsPageEmptyTitle => 'Статистики пока нет';

  @override
  String get statsPageShowAllTooltip => 'Показать всё';

  @override
  String get statsPageClose => 'Закрыть';

  @override
  String get statsPageUnknownProvider => 'Неизвестный провайдер';

  @override
  String get statsPageUnknownAssistant => 'Ассистент по умолчанию';

  @override
  String get statsPageUnknownModel => 'Неизвестная модель';

  @override
  String get statsPageUnknownTopic => 'Тема без названия';

  @override
  String get statsPageCustomRangeTitle => 'Свой период';

  @override
  String get statsPageCustomRangeStart => 'Начало';

  @override
  String get statsPageCustomRangeEnd => 'Конец';

  @override
  String get statsPageCustomRangeCancel => 'Отмена';

  @override
  String get statsPageCustomRangeApply => 'Применить';

  @override
  String get sponsorPageMethodsSectionTitle => 'Способы поддержки';

  @override
  String get sponsorPageSponsorsSectionTitle => 'Спонсоры';

  @override
  String get sponsorPageEmpty => 'Спонсоров пока нет';

  @override
  String get sponsorPageAfdianTitle => 'Afdian';

  @override
  String get sponsorPageAfdianSubtitle => 'afdian.com/a/kelivo';

  @override
  String get sponsorPageWeChatTitle => 'Поддержать через WeChat';

  @override
  String get sponsorPageWeChatSubtitle => 'Код поддержки WeChat';

  @override
  String get sponsorPageScanQrHint => 'Отсканируйте QR-код для поддержки';

  @override
  String get languageDisplaySimplifiedChinese => 'Китайский (упрощённый)';

  @override
  String get languageDisplayEnglish => 'Английский';

  @override
  String get languageDisplayTraditionalChinese => 'Китайский (традиционный)';

  @override
  String get languageDisplayJapanese => 'Японский';

  @override
  String get languageDisplayKorean => 'Корейский';

  @override
  String get languageDisplayFrench => 'Французский';

  @override
  String get languageDisplayGerman => 'Немецкий';

  @override
  String get languageDisplayItalian => 'Итальянский';

  @override
  String get languageDisplaySpanish => 'Испанский';

  @override
  String get languageSelectSheetTitle => 'Язык перевода';

  @override
  String get languageSelectSheetClearButton => 'Убрать перевод';

  @override
  String get homePageClearContext => 'Очистить контекст';

  @override
  String contextMessageCount(int count) {
    return 'Сообщений: $count';
  }

  @override
  String contextMessageCountLimited(int actual, int configured) {
    return 'Сообщений: $actual/$configured';
  }

  @override
  String get homePageDefaultAssistant => 'Ассистент по умолчанию';

  @override
  String get mermaidExportPng => 'Экспорт в PNG';

  @override
  String get mermaidExportFailed => 'Не удалось экспортировать';

  @override
  String get mermaidImageTab => 'Изображение';

  @override
  String get mermaidCodeTab => 'Код';

  @override
  String get mermaidFullScreen => 'На весь экран';

  @override
  String get mermaidGeneratingImage => 'Создание изображения';

  @override
  String get mermaidGenerationFailedHint =>
      'Не удалось создать изображение. Попробуйте изменить запрос.';

  @override
  String get mermaidPreviewOpen => 'Открыть предпросмотр';

  @override
  String get mermaidPreviewOpenFailed => 'Не удалось открыть предпросмотр';

  @override
  String get assistantProviderDefaultAssistantName => 'Ассистент по умолчанию';

  @override
  String get assistantProviderSampleAssistantName => 'Пример ассистента';

  @override
  String get assistantProviderNewAssistantName => 'Новый ассистент';

  @override
  String assistantProviderSampleAssistantSystemPrompt(String model_name) {
    return 'Ты — $model_name, полезный ИИ-ассистент. Отвечай точно и кратко; сообщай, когда не уверен. Используй понятную структуру — короткие абзацы или списки, когда это уместно. По умолчанию отвечай на языке пользователя.';
  }

  @override
  String get displaySettingsPageLanguageTitle => 'Язык приложения';

  @override
  String get displaySettingsPageLanguageSubtitle => 'Выберите язык интерфейса';

  @override
  String get assistantTagsManageTitle => 'Управление тегами';

  @override
  String get assistantTagsCreateButton => 'Создать';

  @override
  String get assistantTagsCreateDialogTitle => 'Создать тег';

  @override
  String get assistantTagsCreateDialogOk => 'Создать';

  @override
  String get assistantTagsCreateDialogCancel => 'Отмена';

  @override
  String get assistantTagsNameHint => 'Название тега';

  @override
  String get assistantTagsRenameButton => 'Переименовать';

  @override
  String get assistantTagsRenameDialogTitle => 'Переименовать тег';

  @override
  String get assistantTagsRenameDialogOk => 'Переименовать';

  @override
  String get assistantTagsDeleteButton => 'Удалить';

  @override
  String get assistantTagsDeleteConfirmTitle => 'Удалить тег';

  @override
  String get assistantTagsDeleteConfirmContent => 'Удалить этот тег?';

  @override
  String get assistantTagsDeleteConfirmOk => 'Удалить';

  @override
  String get assistantTagsDeleteConfirmCancel => 'Отмена';

  @override
  String get assistantTagsContextMenuEditAssistant => 'Изменить ассистента';

  @override
  String get assistantTagsContextMenuManageTags => 'Управление тегами';

  @override
  String get mcpTransportOptionStdio => 'STDIO';

  @override
  String get mcpTransportTagStdio => 'STDIO';

  @override
  String get mcpTransportTagInmemory => 'Встроенный';

  @override
  String get mcpTransportTagSse => 'SSE';

  @override
  String get mcpTransportTagHttp => 'HTTP';

  @override
  String get mcpServerEditSheetStdioCommandLabel => 'Команда';

  @override
  String get mcpServerEditSheetStdioArgumentsLabel => 'Аргументы';

  @override
  String get mcpServerEditSheetStdioWorkingDirectoryLabel =>
      'Рабочий каталог (необязательно)';

  @override
  String get mcpWorkspaceBindingLabel =>
      'Привязать рабочее пространство (необязательно)';

  @override
  String get mcpWorkspaceBindingHint =>
      'Сервер получит доступ к этому рабочему пространству по пути /workspace. Оставьте рабочий каталог пустым для запуска в нём. Привязка не меняется при переключении чатов.';

  @override
  String get mcpWorkspaceBindingMobileOnly =>
      'Привязка рабочего пространства доступна в мобильной Linux-среде. Уберите привязку, чтобы запустить этот сервер на компьютере.';

  @override
  String get mcpServerEditSheetStdioEnvironmentTitle => 'Окружение';

  @override
  String get mcpServerEditSheetStdioEnvNameLabel => 'Имя';

  @override
  String get mcpServerEditSheetStdioEnvValueLabel => 'Значение';

  @override
  String get mcpServerEditSheetStdioAddEnv => 'Добавить переменную';

  @override
  String get mcpServerEditSheetStdioCommandRequired =>
      'Для STDIO необходимо указать команду';

  @override
  String get assistantTagsContextMenuDeleteAssistant => 'Удалить ассистента';

  @override
  String get assistantTagsClearTag => 'Убрать тег';

  @override
  String get displaySettingsPageLanguageChineseLabel =>
      'Китайский (упрощённый)';

  @override
  String get displaySettingsPageLanguageEnglishLabel => 'Английский';

  @override
  String get homePagePleaseSelectModel => 'Сначала выберите модель';

  @override
  String get homePageAudioAttachmentUnsupported =>
      'Текущая модель не поддерживает аудиовложения. Выберите модель с поддержкой аудиоввода или удалите аудиофайл и повторите попытку.';

  @override
  String get homePagePleaseSetupTranslateModel =>
      'Сначала задайте модель для перевода';

  @override
  String get homePageTranslating => 'Перевод…';

  @override
  String homePageTranslateFailed(String error) {
    return 'Не удалось перевести: $error';
  }

  @override
  String get chatServiceDefaultConversationTitle => 'Новый чат';

  @override
  String get userProviderDefaultUserName => 'Пользователь';

  @override
  String get homePageDeleteMessage => 'Удалить эту версию';

  @override
  String get homePageDeleteMessageConfirm =>
      'Удалить эту версию? Отменить удаление нельзя.';

  @override
  String get homePageDeleteAllVersions => 'Удалить все версии';

  @override
  String get homePageDeleteAllVersionsConfirm =>
      'Удалить все версии этого сообщения? Отменить удаление нельзя.';

  @override
  String get homePageCancel => 'Отмена';

  @override
  String get homePageDelete => 'Удалить';

  @override
  String get homePageSelectMessagesToShare =>
      'Выберите сообщения, которыми хотите поделиться';

  @override
  String get homePageDone => 'Готово';

  @override
  String get homePageDropToUpload => 'Перетащите файлы для загрузки';

  @override
  String get assistantEditPageTitle => 'Ассистент';

  @override
  String get assistantEditPageNotFound => 'Ассистент не найден';

  @override
  String get assistantEditPageWorkspaceTab => 'Рабочее пространство';

  @override
  String get assistantEditPageBasicTab => 'Основное';

  @override
  String get assistantEditPagePromptsTab => 'Промпты';

  @override
  String get assistantEditPageMcpTab => 'MCP';

  @override
  String get assistantEditPageQuickPhraseTab => 'Быстрая фраза';

  @override
  String get assistantEditPageCustomTab => 'Свой вариант';

  @override
  String get assistantEditPageRegexTab => 'Замены по регулярным выражениям';

  @override
  String get assistantEditPageLocalToolsTab => 'Локальные инструменты';

  @override
  String get assistantEditTabLayoutTooltip => 'Настроить вкладки';

  @override
  String get assistantEditTabLayoutTitle => 'Настроить вкладки';

  @override
  String get assistantEditTabLayoutSubtitle =>
      'Перетаскивайте вкладки для изменения порядка. Отключайте ненужные вкладки.';

  @override
  String get assistantEditOutlineModeTitle => 'Настройки списком разделов';

  @override
  String get assistantEditOutlineModeSubtitle =>
      'Сначала показывать обзор ассистента, затем открывать разделы настроек из списка.';

  @override
  String get assistantEditTabLayoutResetTooltip =>
      'Сбросить расположение вкладок';

  @override
  String get assistantEditTabLayoutAtLeastOneVisible =>
      'Оставьте хотя бы одну видимую вкладку';

  @override
  String assistantEditTabLayoutDragHandle(String tab) {
    return 'Перетащите для перемещения вкладки «$tab»';
  }

  @override
  String get assistantEditRegexDescription =>
      'Создавайте правила с регулярными выражениями для замены или изменения отображения сообщений пользователя и ассистента.';

  @override
  String get assistantEditAddRegexButton => 'Добавить правило замены';

  @override
  String get assistantRegexAddTitle => 'Добавить правило замены';

  @override
  String get assistantRegexEditTitle => 'Изменить правило замены';

  @override
  String get assistantRegexNameLabel => 'Название правила';

  @override
  String get assistantRegexPatternLabel => 'Регулярное выражение';

  @override
  String get assistantRegexReplacementLabel => 'Строка замены';

  @override
  String get assistantRegexScopeLabel => 'Область действия';

  @override
  String get assistantRegexScopeUser => 'Пользователь';

  @override
  String get assistantRegexScopeAssistant => 'Ассистент';

  @override
  String get assistantRegexScopeVisualOnly => 'Только отображение';

  @override
  String get assistantRegexScopeReplaceOnly => 'Только замена';

  @override
  String get assistantRegexAddAction => 'Добавить';

  @override
  String get assistantRegexSaveAction => 'Сохранить';

  @override
  String get assistantRegexDeleteButton => 'Удалить';

  @override
  String get assistantRegexValidationError =>
      'Введите название и регулярное выражение, затем выберите хотя бы одну область действия.';

  @override
  String get assistantRegexInvalidPattern =>
      'Некорректное регулярное выражение';

  @override
  String get assistantRegexCancelButton => 'Отмена';

  @override
  String get assistantRegexUntitled => 'Правило без названия';

  @override
  String get assistantEditCustomHeadersTitle => 'Свои заголовки';

  @override
  String get assistantEditCustomHeadersAdd => 'Добавить заголовок';

  @override
  String get assistantEditCustomHeadersEmpty => 'Заголовки не добавлены';

  @override
  String get assistantEditCustomBodyTitle => 'Свои поля тела запроса';

  @override
  String get assistantEditCustomBodyAdd => 'Добавить поле';

  @override
  String get assistantEditCustomBodyEmpty => 'Поля тела запроса не добавлены';

  @override
  String get assistantEditHeaderNameLabel => 'Имя заголовка';

  @override
  String get assistantEditHeaderValueLabel => 'Значение заголовка';

  @override
  String get assistantEditBodyKeyLabel => 'Ключ поля';

  @override
  String get assistantEditBodyValueLabel => 'Значение поля (JSON)';

  @override
  String get assistantEditDeleteTooltip => 'Удалить';

  @override
  String get assistantEditAssistantNameLabel => 'Имя ассистента';

  @override
  String get assistantEditUseAssistantAvatarTitle =>
      'Использовать аватар ассистента';

  @override
  String get assistantEditUseAssistantAvatarSubtitle =>
      'Показывать аватар ассистента вместо аватара модели';

  @override
  String get assistantEditUseAssistantNameTitle =>
      'Использовать имя ассистента';

  @override
  String get assistantEditChatModelTitle => 'Модель для чата';

  @override
  String get assistantEditChatModelSubtitle =>
      'Модель по умолчанию для этого ассистента; иначе используется общая настройка';

  @override
  String get assistantEditTemperatureDescription =>
      'Управляет случайностью ответа, диапазон 0–2';

  @override
  String get assistantEditTopPDescription =>
      'Не меняйте, если не знаете назначения параметра';

  @override
  String get assistantEditParameterDisabled =>
      'Отключено (настройка провайдера)';

  @override
  String get assistantEditParameterDisabled2 => 'Отключено (без ограничений)';

  @override
  String get assistantEditContextMessagesTitle => 'Сообщения в контексте';

  @override
  String get assistantEditContextMessagesDescription =>
      'Сколько последних сообщений сохранять в контексте';

  @override
  String get assistantEditStreamOutputTitle => 'Потоковый вывод';

  @override
  String get assistantEditStreamOutputDescription =>
      'Показывать ответ по мере генерации';

  @override
  String get assistantEditThinkingBudgetTitle => 'Бюджет рассуждений';

  @override
  String get assistantEditConfigureButton => 'Настроить';

  @override
  String get assistantEditMaxTokensTitle => 'Максимум токенов';

  @override
  String get assistantEditMaxTokensDescription =>
      'Оставьте пустым, чтобы не ограничивать';

  @override
  String get assistantEditMaxTokensHint => 'Без ограничений';

  @override
  String get assistantEditChatBackgroundTitle => 'Фон чата';

  @override
  String get assistantEditChatBackgroundDescription =>
      'Задайте фоновое изображение для этого ассистента';

  @override
  String get assistantEditChooseImageButton => 'Выбрать изображение';

  @override
  String get assistantEditClearButton => 'Очистить';

  @override
  String get desktopNavChatTooltip => 'Чат';

  @override
  String get desktopNavTranslateTooltip => 'Перевести';

  @override
  String get desktopNavStorageTooltip => 'Хранилище';

  @override
  String get desktopNavGlobalSearchTooltip => 'Глобальный поиск';

  @override
  String get desktopNavThemeToggleTooltip => 'Тема оформления';

  @override
  String get desktopNavSettingsTooltip => 'Настройки';

  @override
  String get desktopAvatarMenuUseEmoji => 'Использовать эмодзи';

  @override
  String get cameraPermissionDeniedMessage =>
      'Камера недоступна: разрешение не предоставлено.';

  @override
  String get openSystemSettings => 'Открыть настройки';

  @override
  String get desktopAvatarMenuChangeFromImage => 'Выбрать изображение…';

  @override
  String get desktopAvatarMenuReset => 'Сбросить аватар';

  @override
  String get assistantEditAvatarChooseImage => 'Выбрать изображение';

  @override
  String get assistantEditAvatarChooseEmoji => 'Выбрать эмодзи';

  @override
  String get assistantEditAvatarEnterLink => 'Ввести ссылку';

  @override
  String get assistantEditAvatarImportQQ => 'Импортировать из QQ';

  @override
  String get assistantEditAvatarReset => 'Сбросить';

  @override
  String get displaySettingsPageChatMessageBackgroundTitle =>
      'Фон сообщений чата';

  @override
  String get displaySettingsPageChatMessageBackgroundDefault => 'По умолчанию';

  @override
  String get displaySettingsPageChatMessageBackgroundFrosted =>
      'Матовое стекло';

  @override
  String get displaySettingsPageChatMessageBackgroundSolid => 'Сплошной цвет';

  @override
  String get displaySettingsPageAndroidBackgroundChatTitle =>
      'Фоновая генерация (Android)';

  @override
  String get displaySettingsPageIosBackgroundChatTitle =>
      'Фоновая генерация (iOS)';

  @override
  String get iosBackgroundStatusOn => 'Вкл.';

  @override
  String get iosBackgroundStatusOff => 'Выкл.';

  @override
  String get iosLiveActivityTitle => 'Текущая активность';

  @override
  String get iosLiveActivitySubtitle =>
      'Показывать фоновые ответы на экране блокировки и в Dynamic Island, если устройство это поддерживает.';

  @override
  String get notificationChatCompletedTitle => 'Генерация завершена';

  @override
  String get notificationChatCompletedBody => 'Ответ ассистента готов';

  @override
  String get assistantEditEmojiDialogTitle => 'Выбрать эмодзи';

  @override
  String get assistantEditEmojiDialogHint =>
      'Введите или вставьте любой эмодзи';

  @override
  String get assistantEditEmojiDialogCancel => 'Отмена';

  @override
  String get assistantEditEmojiDialogSave => 'Сохранить';

  @override
  String get assistantEditImageUrlDialogTitle => 'Введите URL изображения';

  @override
  String get assistantEditImageUrlDialogHint =>
      'Например: https://example.com/avatar.png';

  @override
  String get assistantEditImageUrlDialogCancel => 'Отмена';

  @override
  String get assistantEditImageUrlDialogSave => 'Сохранить';

  @override
  String get assistantEditQQAvatarDialogTitle => 'Импортировать из QQ';

  @override
  String get assistantEditQQAvatarDialogHint => 'Введите номер QQ (5–12 цифр)';

  @override
  String get assistantEditQQAvatarRandomButton => 'Случайный';

  @override
  String get assistantEditQQAvatarFailedMessage =>
      'Не удалось получить случайный аватар QQ. Повторите попытку.';

  @override
  String get assistantEditQQAvatarDialogCancel => 'Отмена';

  @override
  String get assistantEditQQAvatarDialogSave => 'Сохранить';

  @override
  String get assistantEditGalleryErrorMessage =>
      'Не удалось открыть галерею. Попробуйте указать URL изображения.';

  @override
  String get assistantEditGeneralErrorMessage =>
      'Произошла ошибка. Попробуйте указать URL изображения.';

  @override
  String get providerDetailPageMultiKeyModeTitle => 'Режим нескольких ключей';

  @override
  String get providerDetailPageManageKeysButton => 'Управление ключами';

  @override
  String get multiKeyPageTitle => 'Менеджер ключей';

  @override
  String get multiKeyPageDetect => 'Проверить';

  @override
  String get multiKeyPageAdd => 'Добавить';

  @override
  String get multiKeyPageAddHint =>
      'Введите API-ключи через запятую или пробел';

  @override
  String multiKeyPageImportedSnackbar(int n) {
    return 'Импортировано ключей: $n';
  }

  @override
  String get multiKeyPagePleaseAddModel => 'Сначала добавьте модель';

  @override
  String get multiKeyPageTotal => 'Всего';

  @override
  String get multiKeyPageNormal => 'Исправны';

  @override
  String get multiKeyPageError => 'Ошибка';

  @override
  String get multiKeyPageAccuracy => 'Успешность';

  @override
  String get multiKeyPageStrategyTitle => 'Стратегия распределения нагрузки';

  @override
  String get multiKeyPageStrategyRoundRobin => 'По очереди';

  @override
  String get multiKeyPageStrategyPriority => 'По приоритету';

  @override
  String get multiKeyPageStrategyLeastUsed => 'Реже используемые';

  @override
  String get multiKeyPageStrategyRandom => 'Случайно';

  @override
  String get multiKeyPageNoKeys => 'Нет API-ключей';

  @override
  String get multiKeyPageStatusActive => 'Активен';

  @override
  String get multiKeyPageStatusDisabled => 'Отключено';

  @override
  String get multiKeyPageStatusError => 'Ошибка';

  @override
  String get multiKeyPageStatusRateLimited => 'Лимит запросов';

  @override
  String get multiKeyPageEditAlias => 'Изменить псевдоним';

  @override
  String get multiKeyPageEdit => 'Изменить';

  @override
  String get multiKeyPageKey => 'API-ключ';

  @override
  String get multiKeyPagePriority => 'Приоритет (1–10)';

  @override
  String get multiKeyPageDuplicateKeyWarning => 'Этот ключ уже добавлен';

  @override
  String get multiKeyPageAlias => 'Псевдоним';

  @override
  String get multiKeyPageCancel => 'Отмена';

  @override
  String get multiKeyPageSave => 'Сохранить';

  @override
  String get multiKeyPageDelete => 'Удалить';

  @override
  String get assistantEditSystemPromptTitle => 'Системный промпт';

  @override
  String get assistantEditSystemPromptHint => 'Введите системный промпт…';

  @override
  String get assistantEditSystemPromptImportButton => 'Импортировать файл';

  @override
  String get assistantEditSystemPromptImportSuccess =>
      'Системный промпт обновлён из файла';

  @override
  String get assistantEditSystemPromptImportFailed =>
      'Не удалось импортировать файл';

  @override
  String get assistantEditSystemPromptImportEmpty => 'Файл пуст';

  @override
  String get assistantEditAvailableVariables => 'Доступные переменные:';

  @override
  String get assistantEditVariableDate => 'Дата';

  @override
  String get assistantEditVariableTime => 'Время';

  @override
  String get assistantEditVariableDatetime => 'Дата и время';

  @override
  String get assistantEditVariableModelId => 'ID модели';

  @override
  String get assistantEditVariableModelName => 'Название модели';

  @override
  String get assistantEditVariableLocale => 'Язык и регион';

  @override
  String get assistantEditVariableTimezone => 'Часовой пояс';

  @override
  String get assistantEditVariableSystemVersion => 'Версия системы';

  @override
  String get assistantEditVariableDeviceInfo => 'Сведения об устройстве';

  @override
  String get assistantEditVariableBatteryLevel => 'Уровень заряда';

  @override
  String get assistantEditVariableNickname => 'Никнейм';

  @override
  String get assistantEditVariableAssistantName => 'Имя ассистента';

  @override
  String get assistantEditMessageTemplateTitle => 'Шаблон сообщения';

  @override
  String get assistantEditVariableRole => 'Роль';

  @override
  String get assistantEditVariableMessage => 'Сообщение';

  @override
  String get assistantEditPreviewTitle => 'Предпросмотр';

  @override
  String get assistantEditPromptTimeVarWarning =>
      'Переменные времени в системном промпте меняют начало каждого запроса. Поэтому кэш промптов не используется, а стоимость и время до первого токена растут. Чтобы модель знала текущее время, используйте переключатель «Добавлять текущее время» ниже.';

  @override
  String get assistantEditPromptIso8601Title => 'Формат ISO 8601';

  @override
  String get assistantEditPromptIso8601Subtitle =>
      'Добавлять смещение часового пояса, например 2026-08-08T14:30:05+08:00';

  @override
  String get assistantEditPromptAppendTimeTitle => 'Добавлять текущее время';

  @override
  String get assistantEditPromptAppendTimeSubtitle =>
      'Добавлять время отправки в конец каждого сообщения пользователя. Время остаётся в конце запроса и не мешает кэшированию промптов.';

  @override
  String get assistantEditPromptAppendTimeInfoTitle =>
      'Формат добавляемого времени';

  @override
  String assistantEditPromptAppendTimeInfoBody(String example) {
    return 'Когда функция включена, в конец каждого сообщения пользователя добавляются пустая строка и следующий тег:\n\n$example\n\nИспользуется время отправки самого сообщения, поэтому при повторной попытке оно не меняется.';
  }

  @override
  String get assistantEditPromptAppendTimeInfoClose => 'Понятно';

  @override
  String get assistantEditPromptTimeVarDialogTitle =>
      'В системном промпте есть переменные времени';

  @override
  String assistantEditPromptTimeVarDialogBody(String variables) {
    return 'В системном промпте используются $variables. Промпт формируется заново при каждом запросе, поэтому переменные времени меняют его начало и мешают кэшированию. Лучше удалить их и включить «Добавлять текущее время»: так время будет в конце запроса и не изменит его начало.';
  }

  @override
  String get assistantEditPromptTimeVarDialogRemove => 'Перейти к удалению';

  @override
  String get assistantEditPromptTimeVarDialogKeep => 'Всё равно включить';

  @override
  String get codeBlockPreviewButton => 'Предпросмотр';

  @override
  String get codeBlockSaveAsButton => 'Сохранить в файл';

  @override
  String get codeBlockCollapseButton => 'Свернуть';

  @override
  String get codeBlockExpandButton => 'Развернуть';

  @override
  String get codeBlockDefaultFileNameStem => 'code';

  @override
  String get markdownTableLabel => 'Таблица';

  @override
  String get markdownTableExportCsvTooltip => 'Экспорт в CSV';

  @override
  String get markdownTableSaveImageTooltip => 'Сохранить в галерею';

  @override
  String get markdownTableDefaultFileNameStem => 'table';

  @override
  String get markdownTableCopiedCsvSnackbar =>
      'CSV скопирован. Удерживайте кнопку копирования, чтобы скопировать как изображение.';

  @override
  String get markdownTableCopiedMarkdownSnackbar => 'Таблица скопирована.';

  @override
  String codeBlockCollapsedLines(int n) {
    return '… Свёрнуто строк: $n';
  }

  @override
  String get htmlPreviewNotSupportedOnLinux =>
      'Предпросмотр HTML не поддерживается в Linux';

  @override
  String get assistantEditSampleUser => 'Пользователь';

  @override
  String get assistantEditSampleMessage => 'Привет';

  @override
  String get assistantEditSampleReply => 'Здравствуйте! Чем могу помочь?';

  @override
  String get assistantEditMcpNoServersMessage => 'Нет работающих MCP-серверов';

  @override
  String get assistantEditMcpConnectedTag => 'Подключено';

  @override
  String assistantEditMcpToolsCountTag(String enabled, String total) {
    return 'Инструменты: $enabled/$total';
  }

  @override
  String get assistantEditModelUseGlobalDefault =>
      'Использовать общую настройку';

  @override
  String get assistantSettingsPageTitle => 'Настройки ассистента';

  @override
  String get assistantSettingsCopyButton => 'Копировать';

  @override
  String get assistantSettingsCopySuccess => 'Ассистент скопирован';

  @override
  String get assistantSettingsCopySuffix => 'Копия';

  @override
  String get assistantSettingsDeleteButton => 'Удалить';

  @override
  String get assistantSettingsEditButton => 'Изменить';

  @override
  String get assistantSettingsAddSheetTitle => 'Имя ассистента';

  @override
  String get assistantSettingsAddSheetHint => 'Введите имя';

  @override
  String get assistantSettingsAddSheetCancel => 'Отмена';

  @override
  String get assistantSettingsAddSheetSave => 'Сохранить';

  @override
  String get desktopAssistantsListTitle => 'Ассистенты';

  @override
  String get desktopSidebarTabAssistants => 'Ассистенты';

  @override
  String get desktopSidebarTabTopics => 'Темы';

  @override
  String get desktopTrayMenuShowWindow => 'Показать окно';

  @override
  String get desktopTrayMenuExit => 'Выход';

  @override
  String get hotkeyToggleAppVisibility => 'Показать/скрыть приложение';

  @override
  String get hotkeyCloseWindow => 'Закрыть окно';

  @override
  String get hotkeyOpenSettings => 'Открыть настройки';

  @override
  String get hotkeyNewTopic => 'Новая тема';

  @override
  String get hotkeySwitchModel => 'Сменить модель';

  @override
  String get hotkeyToggleAssistantPanel => 'Показать/скрыть ассистентов';

  @override
  String get hotkeyToggleTopicPanel => 'Показать/скрыть темы';

  @override
  String get hotkeysPressShortcut => 'Нажмите сочетание клавиш';

  @override
  String get hotkeysResetDefault => 'Сбросить по умолчанию';

  @override
  String get hotkeysClearShortcut => 'Убрать сочетание';

  @override
  String get hotkeysResetAll => 'Сбросить все сочетания';

  @override
  String get assistantEditTemperatureTitle => 'Температура';

  @override
  String get assistantEditTopPTitle => 'Top-p';

  @override
  String get assistantSettingsDeleteDialogTitle => 'Удалить ассистента';

  @override
  String get assistantSettingsDeleteDialogContent =>
      'Удалить этого ассистента? Отменить удаление нельзя.';

  @override
  String get assistantSettingsDeleteDialogCancel => 'Отмена';

  @override
  String get assistantSettingsDeleteDialogConfirm => 'Удалить';

  @override
  String get assistantSettingsAtLeastOneAssistantRequired =>
      'Должен остаться хотя бы один ассистент';

  @override
  String get mcpAssistantSheetTitle => 'MCP-серверы';

  @override
  String get mcpAssistantSheetSubtitle =>
      'Серверы, включённые для этого ассистента';

  @override
  String get mcpAssistantSheetSelectAll => 'Выбрать всё';

  @override
  String get mcpAssistantSheetClearAll => 'Очистить';

  @override
  String get backupPageTitle => 'Резервное копирование и восстановление';

  @override
  String get backupPageWebDavTab => 'WebDAV';

  @override
  String get backupPageImportExportTab => 'Импорт и экспорт';

  @override
  String get backupPageWebDavServerUrl => 'URL сервера WebDAV';

  @override
  String get backupPageUsername => 'Имя пользователя';

  @override
  String get backupPagePassword => 'Пароль';

  @override
  String get backupPagePath => 'Путь';

  @override
  String get backupPageChatsLabel => 'Чаты';

  @override
  String get backupPageFilesLabel => 'Файлы';

  @override
  String get backupPageTestDone => 'Проверка завершена';

  @override
  String get backupPageTestConnection => 'Проверить';

  @override
  String get backupPageRestartRequired => 'Требуется перезапуск';

  @override
  String get backupPageRestartContent =>
      'Импорт завершён. Перезапустите Moru, чтобы безопасно применить данные.';

  @override
  String backupPageRestartContentWithSkipped(int count) {
    return 'Импорт завершён, но пропущены диалоги с некорректным порядком сообщений: $count. Перезапустите Moru, чтобы безопасно применить импортированные данные.';
  }

  @override
  String get restartAppFailedMessage =>
      'Moru не удалось перезапустить автоматически. Полностью закройте приложение и откройте его снова.';

  @override
  String get backupRestoreRolledBackTitle =>
      'Восстановление отменено с откатом';

  @override
  String get backupRestoreRolledBackContent =>
      'Не удалось завершить восстановление. Moru проверило и сохранило ваши предыдущие данные.';

  @override
  String get backupRestoreFailureTitle => 'Проблема при восстановлении';

  @override
  String get backupRestoreFailureContent =>
      'Moru не удалось подтвердить целостность старого или нового набора данных, поэтому данные чатов не открыты. Закройте приложение и повторите попытку. Если ошибка повторится, сохраните диагностический код для обращения в поддержку.';

  @override
  String get backupRestoreBusinessLeaseUnavailableTitle => 'Moru уже запущено';

  @override
  String get backupRestoreBusinessLeaseUnavailableContent =>
      'Данные Moru используются другим процессом приложения. Закройте другие окна Moru и перезапустите приложение. Этот процесс не открывал данные чатов.';

  @override
  String get restoreProgressTitle => 'Восстановление резервной копии';

  @override
  String get restoreProgressWarning =>
      'Не закрывайте Moru до завершения. Если закрыть приложение сейчас, восстановление начнётся заново при следующем запуске.';

  @override
  String get restoreProgressStageCheckingBackup => 'Проверка резервной копии';

  @override
  String get restoreProgressStagePreservingCurrentData =>
      'Сохранение текущих данных';

  @override
  String get restoreProgressStageInstallingBackup =>
      'Применение резервной копии';

  @override
  String get restoreProgressStageVerifying => 'Проверка';

  @override
  String get restoreProgressStageRollingBack =>
      'Восстановление предыдущих данных';

  @override
  String get restoreProgressStageFinishing => 'Завершение';

  @override
  String get backupRestoreFailureRestartButton => 'Перезапустить Moru';

  @override
  String get backupRestoreFailureCopyButton =>
      'Скопировать диагностический код';

  @override
  String get backupRestoreFailureCopied => 'Диагностический код скопирован';

  @override
  String backupRestoreFailureDiagnostic(String code) {
    return 'Диагностический код: $code';
  }

  @override
  String get startupRecoveryMoreOptions => 'Другие способы восстановления';

  @override
  String get startupRecoveryRepairButton => 'Исправить и перезапустить';

  @override
  String get startupRecoveryExportButton => 'Экспортировать копию моих данных';

  @override
  String get startupRecoveryResetButton => 'Сбросить данные';

  @override
  String get startupRecoveryBusy => 'Выполняется…';

  @override
  String get startupRecoveryExportSucceeded => 'Копия ваших данных сохранена.';

  @override
  String get startupRecoveryExportFailed =>
      'Не удалось экспортировать копию данных.';

  @override
  String get startupRecoveryRepairFailed =>
      'Исправить проблему не удалось. Экспортируйте копию данных, затем выполните сброс.';

  @override
  String get startupRecoveryResetFailed =>
      'Не удалось сбросить данные. Полностью закройте Moru и откройте его снова.';

  @override
  String get startupRecoveryResetDialogTitle => 'Сбросить все данные?';

  @override
  String get startupRecoveryResetDialogContent =>
      'База данных Moru на этом устройстве будет безвозвратно удалена, и приложение начнёт работу с нуля. Если данные могут понадобиться, сначала экспортируйте их копию. Отменить сброс нельзя.';

  @override
  String get startupRecoveryResetDialogConfirm => 'Сбросить и перезапустить';

  @override
  String get startupRecoveryResetDialogCancel => 'Отмена';

  @override
  String get startupRecoveryWhatFailed => 'Что произошло';

  @override
  String get startupRecoveryStageLabel => 'Этап';

  @override
  String get startupRecoveryStageRestore => 'Подготовка восстановления';

  @override
  String get startupRecoveryStageDatabase => 'Запуск базы данных';

  @override
  String get startupRecoveryDiagnosticLabel => 'Диагностический код';

  @override
  String get startupRecoverySchemaLabel => 'Версия базы данных';

  @override
  String startupRecoverySchemaValue(String installed, int expected) {
    return 'На диске: $installed · требуется этой сборке: $expected';
  }

  @override
  String get startupRecoveryAppVersionLabel => 'Приложение';

  @override
  String get startupRecoveryUnknownValue => 'неизвестно';

  @override
  String get startupRecoveryCollecting => 'Сбор диагностики…';

  @override
  String get startupRecoveryShowDetails => 'Показать технические сведения';

  @override
  String get startupRecoveryHideDetails => 'Скрыть технические сведения';

  @override
  String get startupRecoveryCopyReport => 'Скопировать полный отчёт';

  @override
  String get startupRecoveryReportCopied => 'Полный отчёт скопирован';

  @override
  String get startupRecoveryShareReport => 'Экспортировать отчёт';

  @override
  String startupRecoveryReportStored(String path) {
    return 'Копия отчёта сохранена в $path';
  }

  @override
  String startupRecoveryReportSaved(String path) {
    return 'Отчёт сохранён в $path';
  }

  @override
  String get startupRecoveryReportShared => 'Отчёт экспортирован.';

  @override
  String get startupRecoveryReportSaveFailed =>
      'Не удалось экспортировать отчёт.';

  @override
  String get startupRecoverySectionDataTitle => 'Ваши данные';

  @override
  String get startupRecoverySectionDataBody =>
      'Ничего не удалено. Прежде чем выполнять действия ниже, сохраните копию данных в надёжном месте.';

  @override
  String startupRecoveryExportSavedTo(String path) {
    return 'Копия ваших данных сохранена в $path';
  }

  @override
  String get startupRecoverySectionRepairTitle => 'Диагностика и исправление';

  @override
  String get startupRecoverySectionRepairBody =>
      'Проверка целостности только читает базу данных. Исправление удаляет остаточные метаданные прерванного обновления и повторяет запуск, но никогда не удаляет чаты.';

  @override
  String get startupRecoveryIntegrityButton => 'Проверить целостность базы';

  @override
  String get startupRecoveryIntegrityHealthy =>
      'SQLite не обнаружил повреждений в файле базы данных.';

  @override
  String startupRecoveryIntegrityDamaged(String detail) {
    return 'SQLite обнаружил проблемы: $detail';
  }

  @override
  String get startupRecoveryIntegrityMissing =>
      'В папке данных не найден файл базы.';

  @override
  String get startupRecoveryIntegrityFailed =>
      'Не удалось запустить проверку целостности.';

  @override
  String get startupRecoveryDangerZone => 'Опасные действия';

  @override
  String get startupRecoveryDangerBody =>
      'Сброс безвозвратно удалит базу данных Moru на этом устройстве. Сначала экспортируйте копию: сброс также уничтожит сведения, необходимые для поиска причины проблемы.';

  @override
  String get startupRecoveryResetAcknowledge =>
      'Я сохранил копию, или эти данные мне не нужны.';

  @override
  String get startupDatabaseUpdateRequiredTitle =>
      'Обновите Moru, чтобы продолжить';

  @override
  String get startupDatabaseUpdateRequiredContent =>
      'База чатов на этом устройстве создана более новой версией Moru и не может быть открыта этой версией. Ваши данные не изменены. Установите последнюю версию Moru и откройте приложение снова.';

  @override
  String get startupDatabaseUpdateRequiredDowngradeTitle =>
      'Если нужна старая версия';

  @override
  String get startupDatabaseUpdateRequiredDowngradeIntro =>
      'Эта версия не может открыть базу данных на устройстве. Если необходимо пользоваться старой версией, выполните шаги ниже. Не удаляйте и не перезаписывайте данные, пока не сделаете резервную копию.';

  @override
  String get startupDatabaseUpdateRequiredDowngradeStep1 =>
      'Установите и откройте последнюю версию Moru, затем экспортируйте резервную копию: Настройки → Резервное копирование.';

  @override
  String startupDatabaseUpdateRequiredDowngradeStep2(String url) {
    return 'Откройте $url и преобразуйте резервную копию для нужной старой версии.';
  }

  @override
  String get startupDatabaseUpdateRequiredDowngradeStep3 =>
      'Убедившись, что данные устройства сохранены, установите старую версию и импортируйте преобразованную копию.';

  @override
  String get startupDatabaseUpdateRequiredOpenTool => 'Открыть конвертер';

  @override
  String backupPageRestoreFailedMessage(String error) {
    return 'Не удалось восстановить: $error';
  }

  @override
  String backupPageExportFailedMessage(String error) {
    return 'Не удалось экспортировать: $error';
  }

  @override
  String get backupPageOK => 'ОК';

  @override
  String get backupPageCancel => 'Отмена';

  @override
  String get backupPageSelectImportMode => 'Режим импорта';

  @override
  String get backupPageSelectImportModeDescription =>
      'Выберите режим восстановления. Переключатели чатов и файлов определяют, какие компоненты будут включены.';

  @override
  String get backupPageOverwriteMode => 'Полная замена';

  @override
  String get backupPageOverwriteModeDescription =>
      'Заменить выбранные компоненты; сохранить невыбранные компоненты и остальные локальные настройки';

  @override
  String get backupPageMergeMode => 'Объединить';

  @override
  String get backupPageMergeModeDescription =>
      'Сохранить локальные данные и добавить данные из копии. Одинаковые диалоги пропускаются, а конфликтующим назначаются новые ID.';

  @override
  String get backupPageRestore => 'Восстановить';

  @override
  String get backupPageForwardCompatTitle =>
      'Копия создана более новой версией';

  @override
  String backupPageForwardCompatBody(int backupVersion, int currentVersion) {
    return 'Эта копия создана более новой версией Moru (формат данных $backupVersion; эта версия поддерживает $currentVersion). В копии не указано, могут ли старые версии её читать.\n\nМожно продолжить: неизвестные этой версии данные будут пропущены, а сам файл копии не изменится. Но если новая версия изменила способ хранения существующих данных, часть содержимого может импортироваться некорректно.\n\nБезопаснее сначала обновить Moru.';
  }

  @override
  String get backupPageForwardCompatContinue => 'Всё равно импортировать';

  @override
  String get backupPageForwardCompatCancel => 'Отмена';

  @override
  String get backupPageSchemaTooNewMessage =>
      'Эта копия создана более новой версией Moru и не поддерживается текущей. Обновите Moru и повторите попытку.';

  @override
  String get backupPageBackupUploaded => 'Резервная копия загружена';

  @override
  String get backupPageBackup => 'Резервное копирование';

  @override
  String get backupPageExporting => 'Экспорт…';

  @override
  String get backupProgressCancel => 'Отмена';

  @override
  String get backupProgressCancelled => 'Отменено';

  @override
  String get backupProgressPreparing => 'Подготовка';

  @override
  String get backupProgressSnapshotting => 'Создание снимка базы данных';

  @override
  String get backupProgressPacking => 'Упаковка';

  @override
  String get backupProgressVerifying => 'Проверка';

  @override
  String get backupProgressUploading => 'Отправка';

  @override
  String get backupProgressDownloading => 'Загрузка';

  @override
  String get backupProgressExtracting => 'Распаковка';

  @override
  String get backupProgressValidating => 'Проверка данных';

  @override
  String get backupProgressReadingSettings => 'Чтение настроек';

  @override
  String get backupProgressStaging => 'Подготовка данных';

  @override
  String get backupProgressCommitting => 'Применение изменений';

  @override
  String get backupProgressImportingSessions => 'Импорт диалогов';

  @override
  String get backupProgressImportingMessages => 'Импорт сообщений';

  @override
  String get backupProgressMaterializingFiles => 'Запись файлов';

  @override
  String get backupProgressListingRemote => 'Получение списка удалённых копий';

  @override
  String get backupProgressFinalizing => 'Завершение';

  @override
  String backupProgressBytes(String done, String total) {
    return '$done / $total';
  }

  @override
  String backupProgressItems(String done, String total) {
    return '$done / $total';
  }

  @override
  String get backupPageExportToFile => 'Экспортировать в файл';

  @override
  String get backupPageExportToFileSubtitle =>
      'Сохранить данные приложения в файл';

  @override
  String get backupPageImportBackupFile => 'Импортировать резервную копию';

  @override
  String get backupPageImportBackupFileSubtitle =>
      'Импортировать локальный файл резервной копии';

  @override
  String get backupPageImportFromOtherApps => 'Импорт из других приложений';

  @override
  String get backupPageNotSupportedYet => 'Пока не поддерживается';

  @override
  String get backupPageRemoteBackups => 'Удалённые резервные копии';

  @override
  String get backupPageNoBackups => 'Нет резервных копий';

  @override
  String get backupPageRestoreTooltip => 'Восстановить';

  @override
  String get backupPageDeleteTooltip => 'Удалить';

  @override
  String get backupPageDeleteConfirmTitle => 'Подтверждение удаления';

  @override
  String backupPageDeleteConfirmContent(Object name) {
    return 'Удалить удалённую резервную копию «$name»? Отменить удаление нельзя.';
  }

  @override
  String get backupPageBackupManagement => 'Управление резервными копиями';

  @override
  String get backupPageWebDavBackup => 'Копирование в WebDAV';

  @override
  String get backupPageWebDavServerSettings => 'Настройки сервера WebDAV';

  @override
  String get backupPageS3Backup => 'Копирование в S3';

  @override
  String get backupPageS3ServerSettings => 'Настройки S3';

  @override
  String get backupPageS3Endpoint => 'Адрес сервера';

  @override
  String get backupPageS3Region => 'Регион';

  @override
  String get backupPageS3Bucket => 'Бакет';

  @override
  String get backupPageS3AccessKeyId => 'ID ключа доступа';

  @override
  String get backupPageS3SecretAccessKey => 'Секретный ключ доступа';

  @override
  String get backupPageS3SessionToken => 'Токен сессии (необязательно)';

  @override
  String get backupPageS3Prefix => 'Префикс';

  @override
  String get backupPageS3PathStyle => 'Адресация через путь';

  @override
  String get backupPageUserAgent => 'User-Agent';

  @override
  String get backupPageUserAgentHint => 'Необязательно';

  @override
  String get backupPageSave => 'Сохранить';

  @override
  String get backupPageBackupNow => 'Создать копию';

  @override
  String get backupPageLocalBackup => 'Локальная резервная копия';

  @override
  String get backupPageImportFromCherryStudio => 'Импорт из Cherry Studio';

  @override
  String backupPageCherryStudioUnsupportedBackupVersion(String version) {
    return 'Эта копия использует формат Cherry Studio версии $version, который Moru пока не поддерживает. Экспортируйте данные из Cherry Studio v1 или дождитесь обновления Moru с поддержкой копий Cherry Studio v2.';
  }

  @override
  String get backupPageImportFromChatbox => 'Импорт из Chatbox';

  @override
  String get backupReminderSectionTitle =>
      'Напоминание о резервном копировании';

  @override
  String get backupReminderEnableTitle => 'Напоминать о создании копии';

  @override
  String get backupReminderFrequencyTitle => 'Периодичность';

  @override
  String get backupReminderTimeTitle => 'Время напоминания';

  @override
  String get backupReminderTimeInputHint => 'ЧЧ:мм';

  @override
  String get backupReminderTimeInvalid => 'Введите время от 00:00 до 23:59.';

  @override
  String get backupReminderLastBackupTitle => 'Последняя копия';

  @override
  String get backupReminderNextReminderTitle => 'Следующее напоминание';

  @override
  String get backupReminderNever => 'Никогда';

  @override
  String get backupReminderDisabled => 'Выкл.';

  @override
  String get backupReminderDueNow => 'Пора создать копию';

  @override
  String get backupReminderEveryDay => 'Ежедневно';

  @override
  String get backupReminderEveryThreeDays => 'Каждые 3 дня';

  @override
  String get backupReminderEveryWeek => 'Еженедельно';

  @override
  String get backupReminderEveryFourteenDays => 'Каждые 14 дней';

  @override
  String get backupReminderEveryMonth => 'Ежемесячно';

  @override
  String backupReminderCustomDays(int days) {
    return 'Интервал в днях: $days';
  }

  @override
  String get backupReminderCustomOption => 'Свой вариант…';

  @override
  String get backupReminderCustomDialogTitle => 'Своя периодичность';

  @override
  String get backupReminderCustomDialogDescription =>
      'Укажите интервал между напоминаниями в днях.';

  @override
  String get backupReminderCustomDaysLabel => 'Дни';

  @override
  String get backupReminderCustomDaysInvalid => 'Введите число от 1 до 365.';

  @override
  String get backupReminderSidebarTitle => 'Напоминание о копии';

  @override
  String get backupReminderSidebarSubtitle =>
      'Пришло время создать резервную копию.';

  @override
  String get backupReminderSidebarAction => 'Перейти к копированию';

  @override
  String get backupReminderSnoozeTooltip => 'Напомнить позже';

  @override
  String get chatHistoryPageTitle => 'История чатов';

  @override
  String get chatHistoryPageSearchTooltip => 'Поиск';

  @override
  String get chatHistoryPageDeleteAllTooltip => 'Удалить незакреплённые';

  @override
  String get chatHistoryPageDeleteAllDialogTitle =>
      'Удалить незакреплённые диалоги';

  @override
  String get chatHistoryPageDeleteAllDialogContent =>
      'Удалить все незакреплённые диалоги этого ассистента? Закреплённые чаты останутся.';

  @override
  String get chatHistoryPageCancel => 'Отмена';

  @override
  String get chatHistoryPageDelete => 'Удалить';

  @override
  String get chatHistoryPageDeletedAllSnackbar =>
      'Незакреплённые диалоги удалены';

  @override
  String get chatHistoryPageSearchHint => 'Поиск диалогов';

  @override
  String get chatHistoryPageNoConversations => 'Нет диалогов';

  @override
  String get chatHistoryPagePinnedSection => 'Закреплённые';

  @override
  String get chatHistoryPagePin => 'Закрепить';

  @override
  String get chatHistoryPagePinned => 'Закреплённые';

  @override
  String get messageEditPageTitle => 'Изменить сообщение';

  @override
  String get messageEditPageSave => 'Сохранить';

  @override
  String get messageEditPageSaveAndSend => 'Сохранить и отправить';

  @override
  String get messageEditPageHint => 'Введите сообщение…';

  @override
  String get userMessageEditSaveOnly => 'Только сохранить';

  @override
  String get userMessageEditUnsupportedSnackbar =>
      'Это содержимое нельзя редактировать';

  @override
  String get userMessageEditOverwriteTitle => 'Внимание';

  @override
  String get userMessageEditOverwriteContent =>
      'Редактирование заменит текущий текст ввода. Продолжить?';

  @override
  String get selectCopyPageTitle => 'Выделить и скопировать';

  @override
  String get selectCopyPageCopyAll => 'Скопировать всё';

  @override
  String get selectCopyPageCopiedAll => 'Всё скопировано';

  @override
  String get bottomToolsSheetCamera => 'Камера';

  @override
  String get bottomToolsSheetPhotos => 'Фото';

  @override
  String get bottomToolsSheetUpload => 'Загрузить';

  @override
  String get bottomToolsSheetClearContext => 'Очистить контекст';

  @override
  String get compressContext => 'Сжать контекст';

  @override
  String get compressContextDesc => 'Создать сводку и начать новый чат';

  @override
  String get clearContextDesc => 'Отметить границу контекста';

  @override
  String get contextManagement => 'Управление контекстом';

  @override
  String get compressingContext => 'Сжатие контекста…';

  @override
  String get compressContextFailed => 'Не удалось сжать контекст';

  @override
  String get compressContextNoMessages => 'Нет сообщений для сжатия';

  @override
  String get compressContextNoConversation => 'Нет диалога для сжатия';

  @override
  String get compressContextNoModel => 'Модель сжатия не настроена';

  @override
  String get compressContextEmptySummary =>
      'Модель сжатия вернула пустую сводку';

  @override
  String get compressContextOptionsTitle => 'Сжать контекст';

  @override
  String get compressContextOptionsDesc =>
      'Выберите часть текущего чата, которую нужно отправить модели сжатия.';

  @override
  String get compressContextKeepStart => 'Начало';

  @override
  String get compressContextKeepRecent => 'Последние';

  @override
  String get compressContextUnlimited => 'Без ограничений';

  @override
  String get compressContextMaxCharsLabel => 'Символы';

  @override
  String get compressContextInvalidLimit =>
      'Введите положительное число символов';

  @override
  String get compressContextStartButton => 'Сжать';

  @override
  String get compressContextModelLabel => 'Модель';

  @override
  String get compressContextModelUnset => 'Выберите модель';

  @override
  String get compressContextKeepRecentMessages => 'Сохранить N';

  @override
  String get compressContextKeepCountLabel => 'Сохранить последние сообщения';

  @override
  String get compressContextKeepAllMessages =>
      'Это количество охватывает все сообщения — сжимать нечего';

  @override
  String compressContextEstimatePreview(
    int summarized,
    int kept,
    int minTokens,
    int maxTokens,
    int totalTokens,
  ) {
    return 'Сжать $summarized симв., сохранить $kept симв. без изменений → примерно $minTokens–$maxTokens токенов (исходно около $totalTokens токенов)';
  }

  @override
  String get bottomToolsSheetLearningMode => 'Режим обучения';

  @override
  String get bottomToolsSheetLearningModeDescription =>
      'Помощь в пошаговом обучении';

  @override
  String get bottomToolsSheetConfigurePrompt => 'Настроить промпт';

  @override
  String get bottomToolsSheetPrompt => 'Промпт';

  @override
  String get bottomToolsSheetPromptHint => 'Введите текст добавляемого промпта';

  @override
  String get bottomToolsSheetResetDefault => 'Сбросить по умолчанию';

  @override
  String get bottomToolsSheetSave => 'Сохранить';

  @override
  String get bottomToolsSheetOcr => 'Распознать текст на изображении';

  @override
  String get messageMoreSheetTitle => 'Другие действия';

  @override
  String get messageMoreSheetSelectCopy => 'Выделить и скопировать';

  @override
  String get messageMoreSheetRenderWebView => 'Открыть в веб-представлении';

  @override
  String get messageMoreSheetNotImplemented => 'Пока не реализовано';

  @override
  String get messageMoreSheetEdit => 'Изменить';

  @override
  String get messageMoreSheetShare => 'Поделиться';

  @override
  String get messageMoreSheetSelectMessages => 'Выбрать сообщения';

  @override
  String get messageMoreSheetCreateBranch => 'Создать ветку';

  @override
  String get messageMoreSheetDelete => 'Удалить эту версию';

  @override
  String get messageMoreSheetDeleteAllVersions => 'Удалить все версии';

  @override
  String get reasoningBudgetSheetOff => 'Выкл.';

  @override
  String get reasoningBudgetSheetAuto => 'Авто';

  @override
  String get reasoningBudgetSheetLight => 'Лёгкие рассуждения';

  @override
  String get reasoningBudgetSheetMedium => 'Средние рассуждения';

  @override
  String get reasoningBudgetSheetHeavy => 'Глубокие рассуждения';

  @override
  String get reasoningBudgetSheetXhigh => 'Очень глубокие рассуждения';

  @override
  String get reasoningBudgetSheetMax => 'Максимальные рассуждения';

  @override
  String get reasoningBudgetSheetTitle => 'Глубина рассуждений';

  @override
  String reasoningBudgetSheetCurrentLevel(String level) {
    return 'Текущий уровень: $level';
  }

  @override
  String get reasoningBudgetSheetOffSubtitle =>
      'Отвечать сразу, без рассуждений';

  @override
  String get reasoningBudgetSheetAutoSubtitle =>
      'Модель сама выберет глубину рассуждений';

  @override
  String get reasoningBudgetSheetLightSubtitle =>
      'Использовать лёгкие рассуждения для ответа';

  @override
  String get reasoningBudgetSheetMediumSubtitle =>
      'Использовать умеренные рассуждения для ответа';

  @override
  String get reasoningBudgetSheetHeavySubtitle =>
      'Глубоко рассуждать над сложными вопросами';

  @override
  String get reasoningBudgetSheetXhighSubtitle =>
      'Максимальная глубина рассуждений для самых сложных задач';

  @override
  String get reasoningBudgetSheetCustomLabel => 'Свой бюджет рассуждений';

  @override
  String get reasoningBudgetSheetCustomHint =>
      'Например: 2048 (−1 — авто, 0 — выкл.)';

  @override
  String chatMessageWidgetFileNotFound(String fileName) {
    return 'Файл не найден: $fileName';
  }

  @override
  String chatMessageWidgetCannotOpenFile(String message) {
    return 'Не удалось открыть файл: $message';
  }

  @override
  String chatMessageWidgetOpenFileError(String error) {
    return 'Ошибка открытия файла: $error';
  }

  @override
  String get chatMessageWidgetCopiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String get chatMessageWidgetResendTooltip => 'Отправить повторно';

  @override
  String get chatMessageWidgetMoreTooltip => 'Больше';

  @override
  String get chatMessageWidgetThinking => 'Думает…';

  @override
  String get chatMessageWidgetTranslation => 'Перевод';

  @override
  String get chatMessageWidgetTranslating => 'Перевод…';

  @override
  String get chatMessageWidgetCitationNotFound => 'Источник цитаты не найден';

  @override
  String chatMessageWidgetCannotOpenUrl(String url) {
    return 'Не удалось открыть ссылку: $url';
  }

  @override
  String get chatMessageWidgetOpenLinkError => 'Не удалось открыть ссылку';

  @override
  String get chatMessageWidgetAttachmentUnavailable => 'Вложение недоступно';

  @override
  String chatMessageWidgetCitationsTitle(int count) {
    return 'Источники ($count)';
  }

  @override
  String get chatMessageWidgetSearchResultsTitle => 'Результаты поиска';

  @override
  String get chatMessageWidgetCitationSourcesTitle => 'Источники цитат';

  @override
  String get chatMessageWidgetRegenerateTooltip => 'Сгенерировать заново';

  @override
  String get chatMessageWidgetRegenerateConfirmTitle =>
      'Подтвердите повторную генерацию';

  @override
  String get chatMessageWidgetRegenerateConfirmContent =>
      'Повторная генерация обновит только это сообщение и сохранит сообщения ниже. Продолжить?';

  @override
  String get chatMessageWidgetRegenerateConfirmDeleteTrailingContent =>
      'Повторная генерация удалит все сообщения ниже этого. Отменить удаление нельзя. Продолжить?';

  @override
  String get chatMessageWidgetRegenerateConfirmCancel => 'Отмена';

  @override
  String get chatMessageWidgetRegenerateConfirmOk => 'Сгенерировать заново';

  @override
  String get chatMessageWidgetStopTooltip => 'Остановить';

  @override
  String get chatMessageWidgetSpeakTooltip => 'Озвучить';

  @override
  String get chatMessageWidgetTranslateTooltip => 'Перевести';

  @override
  String get chatMessageWidgetBuiltinSearchHideNote =>
      'Скрыть карточки встроенного поиска';

  @override
  String get chatMessageWidgetDeepThinking => 'Глубокое размышление';

  @override
  String chatMessageWidgetWebSearch(String query) {
    return 'Веб-поиск: $query';
  }

  @override
  String get chatMessageWidgetBuiltinSearch => 'Встроенный поиск';

  @override
  String get chatMessageWidgetReadClipboard => 'Чтение буфера обмена';

  @override
  String get chatMessageWidgetWriteClipboard => 'Запись в буфер обмена';

  @override
  String get chatMessageWidgetSpeakingTitle => 'Озвучивание:';

  @override
  String chatMessageWidgetSpeakText(String text) {
    return 'Озвучивание: $text';
  }

  @override
  String get chatMessageWidgetMemoryRead => 'Чтение памяти';

  @override
  String get chatMessageWidgetMemoryUpdate => 'Обновление памяти';

  @override
  String get chatMessageWidgetMemorySearchProfile => 'Поиск в памяти';

  @override
  String get chatMessageWidgetMemoryEdit => 'Изменение памяти';

  @override
  String get chatMessageWidgetMemoryDelete => 'Удаление из памяти';

  @override
  String get chatMessageWidgetUpdateUserProfile =>
      'Обновление профиля пользователя';

  @override
  String get chatMessageWidgetChatSearch => 'Поиск в прошлых чатах';

  @override
  String get chatMessageWidgetCreateMemory => 'Создание записи в памяти';

  @override
  String chatMessageWidgetToolCall(String name) {
    return 'Вызов инструмента: $name';
  }

  @override
  String chatMessageWidgetToolResult(String name) {
    return 'Результат инструмента: $name';
  }

  @override
  String get chatMessageWidgetNoResultYet => '(Результата пока нет)';

  @override
  String get chatMessageWidgetArguments => 'Аргументы';

  @override
  String get chatMessageWidgetResult => 'Результат';

  @override
  String get chatMessageWidgetImages => 'Изображения';

  @override
  String chatMessageWidgetCitationsCount(int count) {
    return 'Источников: $count';
  }

  @override
  String chatSelectionSelectedCountTitle(int count) {
    return 'Выбрано сообщений: $count';
  }

  @override
  String get chatSelectionExportTxt => 'TXT';

  @override
  String get chatSelectionExportMd => 'MD';

  @override
  String get chatSelectionExportImage => 'Изображение';

  @override
  String get chatSelectionThinkingTools => 'Рассуждения и инструменты';

  @override
  String get chatSelectionThinkingContent => 'Содержимое рассуждений';

  @override
  String get chatSelectionDeleteSelected => 'Удалить выбранное';

  @override
  String get chatSelectionSelectMessagesToDelete =>
      'Выберите сообщения для удаления';

  @override
  String chatSelectionDeleteSelectedConfirm(int count) {
    return 'Удалить выбранные версии ($count)? Отменить удаление нельзя.';
  }

  @override
  String chatSelectionDeleteSelectedAllVersionsConfirm(int count) {
    return 'Удалить все версии выбранных сообщений ($count)? Отменить удаление нельзя.';
  }

  @override
  String get messageExportSheetAssistant => 'Ассистент';

  @override
  String get messageExportSheetDefaultTitle => 'Новый чат';

  @override
  String get messageExportSheetExporting => 'Экспорт…';

  @override
  String messageExportSheetExportFailed(String error) {
    return 'Не удалось экспортировать: $error';
  }

  @override
  String messageExportSheetExportedAs(String filename) {
    return 'Экспортировано в $filename';
  }

  @override
  String get displaySettingsPageEnableDollarLatexTitle =>
      'Формулы внутри \$...\$';

  @override
  String get displaySettingsPageEnableDollarLatexSubtitle =>
      'Отображать строчные формулы внутри \$...\$';

  @override
  String get displaySettingsPageEnableMathTitle => 'Отображение формул';

  @override
  String get displaySettingsPageEnableMathSubtitle =>
      'Отображать формулы LaTeX в строках и блоках';

  @override
  String get displaySettingsPageEnableUserMarkdownTitle =>
      'Markdown в сообщениях пользователя';

  @override
  String get displaySettingsPageEnableReasoningMarkdownTitle =>
      'Markdown в рассуждениях';

  @override
  String get displaySettingsPageEnableAssistantMarkdownTitle =>
      'Markdown в сообщениях ассистента';

  @override
  String get displaySettingsPageMobileCodeBlockWrapTitle =>
      'Перенос строк в блоках кода на телефоне';

  @override
  String get displaySettingsPageAutoCollapseCodeBlockTitle =>
      'Автоматически сворачивать блоки кода';

  @override
  String get displaySettingsPageAutoCollapseCodeBlockLinesTitle =>
      'Порог автосворачивания';

  @override
  String get displaySettingsPageAutoCollapseCodeBlockLinesUnit => 'строк';

  @override
  String get displaySettingsPageCollapseLongUserMessagesTitle =>
      'Сворачивать длинные сообщения';

  @override
  String get displaySettingsPageCollapseLongUserMessagesSubtitle =>
      'Скрывать часть длинных сообщений пользователя под кнопкой раскрытия';

  @override
  String get displaySettingsPageCollapseLongUserMessagesCharsTitle =>
      'Порог сворачивания';

  @override
  String get displaySettingsPageCollapseLongUserMessagesCharsUnit => 'симв.';

  @override
  String get chatMessageExpandLongText => 'Развернуть';

  @override
  String get chatMessageCollapseLongText => 'Свернуть';

  @override
  String get messageExportSheetFormatTitle => 'Формат экспорта';

  @override
  String get messageExportSheetMarkdown => 'Markdown';

  @override
  String get messageExportSheetSingleMarkdownSubtitle =>
      'Экспортировать это сообщение в файл Markdown';

  @override
  String get messageExportSheetBatchMarkdownSubtitle =>
      'Экспортировать выбранные сообщения в файл Markdown';

  @override
  String get messageExportSheetPlainText => 'Обычный текст';

  @override
  String get messageExportSheetSingleTxtSubtitle =>
      'Экспортировать это сообщение в файл TXT';

  @override
  String get messageExportSheetBatchTxtSubtitle =>
      'Экспортировать выбранные сообщения в файл TXT';

  @override
  String get messageExportSheetExportImage => 'Экспортировать как изображение';

  @override
  String get messageExportSheetSingleExportImageSubtitle =>
      'Сохранить это сообщение как изображение PNG';

  @override
  String get messageExportSheetBatchExportImageSubtitle =>
      'Сохранить выбранные сообщения как изображение PNG';

  @override
  String get messageExportSheetShowThinkingAndToolCards =>
      'Показывать рассуждения и карточки инструментов';

  @override
  String get messageExportSheetShowThinkingContent =>
      'Показывать содержимое рассуждений';

  @override
  String get messageExportThinkingContentLabel => 'Содержимое рассуждений';

  @override
  String get messageExportSheetDateTimeWithSecondsPattern =>
      'dd.MM.yyyy HH:mm:ss';

  @override
  String get exportDisclaimerAiGenerated =>
      'Содержимое создано ИИ. Внимательно проверяйте информацию.';

  @override
  String get imagePreviewSheetSaveImage => 'Сохранить изображение';

  @override
  String get imagePreviewSheetSaveSuccess => 'Сохранено в галерею';

  @override
  String imagePreviewSheetSaveFailed(String error) {
    return 'Не удалось сохранить: $error';
  }

  @override
  String get sideDrawerMenuRename => 'Переименовать';

  @override
  String get sideDrawerMenuPin => 'Закрепить';

  @override
  String get sideDrawerMenuUnpin => 'Открепить';

  @override
  String get sideDrawerMenuRegenerateTitle => 'Создать заголовок заново';

  @override
  String get sideDrawerMenuCopy => 'Копировать';

  @override
  String get sideDrawerMenuMoveTo => 'Переместить в';

  @override
  String get sideDrawerMenuDelete => 'Удалить';

  @override
  String get sideDrawerMenuSelect => 'Выбрать';

  @override
  String sideDrawerSelectionTitle(int count) {
    return 'Выбрано объектов: $count';
  }

  @override
  String get sideDrawerSelectionSelectAll => 'Выбрать всё';

  @override
  String get sideDrawerSelectionDeselectAll => 'Снять всё выделение';

  @override
  String get sideDrawerSelectionPin => 'Закрепить';

  @override
  String get sideDrawerSelectionUnpin => 'Открепить';

  @override
  String get sideDrawerSelectionMove => 'Переместить';

  @override
  String get sideDrawerSelectionDelete => 'Удалить';

  @override
  String get sideDrawerSelectionDeleteConfirmTitle => 'Удалить диалоги';

  @override
  String sideDrawerSelectionDeleteConfirmContent(int count) {
    return 'Удалить диалоги ($count)?';
  }

  @override
  String sideDrawerDeleteSelectedSnackbar(int count) {
    return 'Удалено диалогов: $count';
  }

  @override
  String sideDrawerMoveSelectedSnackbar(int count) {
    return 'Перемещено диалогов: $count';
  }

  @override
  String sideDrawerDeleteSnackbar(String title) {
    return 'Удалено: «$title»';
  }

  @override
  String get sideDrawerRenameHint => 'Введите новое название';

  @override
  String get sideDrawerCancel => 'Отмена';

  @override
  String get sideDrawerOK => 'ОК';

  @override
  String get sideDrawerSave => 'Сохранить';

  @override
  String get sideDrawerGreetingMorning => 'Доброе утро 👋';

  @override
  String get sideDrawerGreetingNoon => 'Добрый день 👋';

  @override
  String get sideDrawerGreetingAfternoon => 'Добрый день 👋';

  @override
  String get sideDrawerGreetingEvening => 'Добрый вечер 👋';

  @override
  String get sideDrawerDateToday => 'Сегодня';

  @override
  String get sideDrawerDateYesterday => 'Вчера';

  @override
  String get sideDrawerDateShortPattern => 'd MMM';

  @override
  String get sideDrawerDateFullPattern => 'd MMM yyyy';

  @override
  String get sideDrawerSearchHint => 'Поиск у текущего ассистента';

  @override
  String get sideDrawerSearchAssistantsHint => 'Поиск ассистентов';

  @override
  String get sideDrawerTopicSearchModeLabel => 'Поиск по темам';

  @override
  String get sideDrawerGlobalSearchModeLabel => 'Глобальный поиск';

  @override
  String get sideDrawerSearchModeSwipeToTopicHint =>
      'Смахните строку поиска для поиска по темам';

  @override
  String get sideDrawerSearchModeSwipeToGlobalHint =>
      'Смахните строку поиска для глобального поиска';

  @override
  String get sideDrawerGlobalSearchHint => 'Поиск во всех диалогах';

  @override
  String get sideDrawerGlobalSearchEmptyHint =>
      'Поиск по заголовкам и сообщениям';

  @override
  String get sideDrawerGlobalSearchNoResults => 'Подходящие диалоги не найдены';

  @override
  String sideDrawerGlobalSearchResultCount(int count) {
    return 'Результатов: $count';
  }

  @override
  String sideDrawerUpdateTitle(String version) {
    return 'Новая версия: $version';
  }

  @override
  String sideDrawerUpdateTitleWithBuild(String version, int build) {
    return 'Новая версия: $version ($build)';
  }

  @override
  String get sideDrawerLinkCopied => 'Ссылка скопирована';

  @override
  String get sideDrawerPinnedLabel => 'Закреплённые';

  @override
  String get sideDrawerHistory => 'История';

  @override
  String get sideDrawerSettings => 'Настройки';

  @override
  String get sideDrawerChooseAssistantTitle => 'Выберите ассистента';

  @override
  String get sideDrawerChooseImage => 'Выбрать изображение';

  @override
  String get sideDrawerChooseEmoji => 'Выбрать эмодзи';

  @override
  String get sideDrawerEnterLink => 'Ввести ссылку';

  @override
  String get sideDrawerImportFromQQ => 'Импортировать из QQ';

  @override
  String get sideDrawerReset => 'Сбросить';

  @override
  String get providerAvatarChooseBuiltInIcon => 'Выбрать встроенный значок';

  @override
  String get providerAvatarIconDialogTitle => 'Выбрать встроенный значок';

  @override
  String get providerAvatarIconSearchHint => 'Поиск значков';

  @override
  String get providerAvatarIconNoResults => 'Значки не найдены';

  @override
  String get providerAvatarInputLobehubIcon => 'Указать значок LobeHub';

  @override
  String get providerAvatarChooseLobehubIcon => 'Указать значок LobeHub';

  @override
  String get providerAvatarLobehubDialogTitle => 'Указать значок LobeHub';

  @override
  String get providerAvatarLobehubDialogHint =>
      'Введите название значка LobeHub, например openai';

  @override
  String get sideDrawerEmojiDialogTitle => 'Выбрать эмодзи';

  @override
  String get sideDrawerEmojiDialogHint => 'Введите или вставьте любой эмодзи';

  @override
  String get sideDrawerImageUrlDialogTitle => 'Введите URL изображения';

  @override
  String get sideDrawerImageUrlDialogHint =>
      'Например: https://example.com/avatar.png';

  @override
  String get sideDrawerQQAvatarDialogTitle => 'Импортировать из QQ';

  @override
  String get sideDrawerQQAvatarInputHint => 'Введите номер QQ (5–12 цифр)';

  @override
  String get sideDrawerQQAvatarFetchFailed =>
      'Не удалось получить случайный аватар QQ. Повторите попытку.';

  @override
  String get sideDrawerRandomQQ => 'Случайный QQ';

  @override
  String get sideDrawerGalleryOpenError =>
      'Не удалось открыть галерею. Попробуйте указать URL изображения.';

  @override
  String get sideDrawerGeneralImageError =>
      'Произошла ошибка. Попробуйте указать URL изображения.';

  @override
  String get sideDrawerSetNicknameTitle => 'Задать никнейм';

  @override
  String get sideDrawerNicknameLabel => 'Никнейм';

  @override
  String get sideDrawerNicknameHint => 'Введите новый никнейм';

  @override
  String get sideDrawerRename => 'Переименовать';

  @override
  String get chatInputBarHint => 'Напишите сообщение ИИ';

  @override
  String get chatInputBarSelectModelTooltip => 'Выбрать модель';

  @override
  String get chatInputBarOnlineSearchTooltip => 'Поиск в интернете';

  @override
  String get chatInputBarReasoningStrengthTooltip => 'Глубина рассуждений';

  @override
  String get chatInputBarMcpServersTooltip => 'MCP-серверы';

  @override
  String get chatInputBarToolsTooltip => 'Инструменты';

  @override
  String get chatInputBarMoreTooltip => 'Добавить';

  @override
  String get chatInputBarVoiceInputTooltip => 'Голосовой ввод';

  @override
  String get chatInputBarVoiceCancelTooltip => 'Удалить запись';

  @override
  String get chatInputBarVoiceStopTooltip =>
      'Остановить и вставить распознанный текст';

  @override
  String get chatInputBarVoiceSendTooltip => 'Распознать и отправить';

  @override
  String get chatInputBarVoiceTranscribing => 'Распознавание…';

  @override
  String get chatInputBarImageProcessing => 'Обработка изображения';

  @override
  String get chatInputBarImageMode => 'Режим изображений';

  @override
  String get chatInputBarDisableImageModeTooltip =>
      'Выключить режим изображений';

  @override
  String get chatInputBarQueuedPending => 'В очереди на отправку';

  @override
  String get chatInputBarQueuedCancel => 'Отменить отправку из очереди';

  @override
  String get chatInputBarInsertNewline => 'Новая строка';

  @override
  String get chatInputBarExpand => 'Развернуть';

  @override
  String get chatInputBarCollapse => 'Свернуть';

  @override
  String get mcpPageBackTooltip => 'Назад';

  @override
  String get mcpPageAddMcpTooltip => 'Добавить MCP';

  @override
  String get mcpPageNoServers => 'Нет MCP-серверов';

  @override
  String get mcpPageErrorDialogTitle => 'Ошибка подключения';

  @override
  String get mcpPageErrorNoDetails => 'Нет подробностей';

  @override
  String get mcpPageClose => 'Закрыть';

  @override
  String get mcpPageReconnect => 'Переподключить';

  @override
  String get mcpPageStatusConnected => 'Подключено';

  @override
  String get mcpPageStatusConnecting => 'Подключение…';

  @override
  String get mcpPageStatusDisconnected => 'Нет подключения';

  @override
  String get mcpPageStatusAuthorizationRequired => 'Требуется авторизация';

  @override
  String get mcpPageStatusAuthorizing => 'Авторизация…';

  @override
  String get mcpPageStatusDisabled => 'Отключено';

  @override
  String get mcpPageOAuthRequired => 'Требуется вход через OAuth';

  @override
  String get mcpPageOAuthSignIn => 'Войти через OAuth';

  @override
  String mcpPageToolsCount(int enabled, int total) {
    return 'Инструменты: $enabled/$total';
  }

  @override
  String get mcpPageConnectionFailed => 'Не удалось подключиться';

  @override
  String get mcpPageDetails => 'Подробности';

  @override
  String get mcpPageDelete => 'Удалить';

  @override
  String get mcpPageConfirmDeleteTitle => 'Подтвердите удаление';

  @override
  String get mcpPageConfirmDeleteContent =>
      'Это действие можно будет отменить. Удалить?';

  @override
  String get mcpPageServerDeleted => 'Сервер удалён';

  @override
  String get mcpPageUndo => 'Отменить';

  @override
  String get mcpPageCancel => 'Отмена';

  @override
  String get mcpConversationSheetTitle => 'MCP-серверы';

  @override
  String get mcpConversationSheetSubtitle =>
      'Выберите серверы для этого диалога';

  @override
  String get mcpConversationSheetSelectAll => 'Выбрать всё';

  @override
  String get mcpConversationSheetClearAll => 'Очистить';

  @override
  String get mcpConversationSheetNoRunning => 'Нет работающих MCP-серверов';

  @override
  String get mcpConversationSheetConnected => 'Подключено';

  @override
  String mcpConversationSheetToolsCount(int enabled, int total) {
    return 'Инструменты: $enabled/$total';
  }

  @override
  String get mcpServerEditSheetEnabledLabel => 'Включено';

  @override
  String get mcpServerEditSheetNameLabel => 'Имя';

  @override
  String get mcpServerEditSheetTransportLabel => 'Транспорт';

  @override
  String get mcpServerEditSheetUrlLabel => 'URL сервера';

  @override
  String get mcpServerEditSheetCustomHeadersTitle => 'Свои заголовки';

  @override
  String get mcpServerEditSheetHeaderNameLabel => 'Имя заголовка';

  @override
  String get mcpServerEditSheetHeaderNameHint => 'Например: Authorization';

  @override
  String get mcpServerEditSheetHeaderValueLabel => 'Значение заголовка';

  @override
  String get mcpServerEditSheetHeaderValueHint => 'Например: Bearer xxxxxx';

  @override
  String get mcpServerEditSheetRemoveHeaderTooltip => 'Убрать';

  @override
  String get mcpServerEditSheetAddHeader => 'Добавить заголовок';

  @override
  String get mcpServerEditSheetTitleEdit => 'Изменить MCP';

  @override
  String get mcpServerEditSheetTitleAdd => 'Добавить MCP';

  @override
  String get mcpServerEditSheetSyncToolsTooltip =>
      'Синхронизировать инструменты';

  @override
  String get mcpServerEditSheetTabBasic => 'Основное';

  @override
  String get mcpServerEditSheetTabTools => 'Инструменты';

  @override
  String get mcpServerEditSheetNoToolsHint =>
      'Нет инструментов. Нажмите обновление для синхронизации';

  @override
  String get mcpServerEditSheetCancel => 'Отмена';

  @override
  String get mcpServerEditSheetSave => 'Сохранить';

  @override
  String get mcpServerEditSheetUrlRequired => 'Введите URL сервера';

  @override
  String get defaultModelPageBackTooltip => 'Назад';

  @override
  String get defaultModelPageTitle => 'Модель по умолчанию';

  @override
  String get defaultModelPageChatModelTitle => 'Модель для чата';

  @override
  String get defaultModelPageChatModelSubtitle =>
      'Общая модель чата по умолчанию';

  @override
  String get defaultModelPageTitleModelTitle => 'Модель заголовков';

  @override
  String get defaultModelPageTitleModelSubtitle =>
      'Создаёт заголовки диалогов с помощью текущей модели чата или выбранной модели.';

  @override
  String get titleModelThinkingTitle => 'Включить рассуждения';

  @override
  String get defaultModelPageSummaryModelTitle => 'Модель сводок';

  @override
  String get defaultModelPageSummaryModelSubtitle =>
      'Создаёт сводки диалогов; лучше использовать быстрые и недорогие модели';

  @override
  String get defaultModelPageSuggestionModelTitle =>
      'Модель подсказок для чата';

  @override
  String get defaultModelPageSuggestionModelSubtitle =>
      'Создаёт варианты продолжения диалога с помощью текущей или выбранной модели. По умолчанию отключено.';

  @override
  String get assistantEditRecentChatsSummaryFrequencyTitle =>
      'Частота обновления сводки';

  @override
  String get assistantEditRecentChatsSummaryFrequencyDescription =>
      'Обновлять сводку последних чатов после указанного количества новых сообщений.';

  @override
  String assistantEditRecentChatsSummaryFrequencyOption(int count) {
    return 'Каждые $count';
  }

  @override
  String get assistantEditRecentChatsSummaryFrequencyCustomButton =>
      'Свой вариант';

  @override
  String get assistantEditRecentChatsSummaryFrequencyCustomTitle =>
      'Своя частота обновления сводки';

  @override
  String get assistantEditRecentChatsSummaryFrequencyCustomDescription =>
      'Укажите, сколько новых сообщений должно накопиться перед обновлением сводки чата.';

  @override
  String get assistantEditRecentChatsSummaryFrequencyCustomLabel =>
      'Количество новых сообщений';

  @override
  String get assistantEditRecentChatsSummaryFrequencyCustomHint =>
      'Введите число больше 0';

  @override
  String get assistantEditRecentChatsSummaryFrequencyCustomInvalid =>
      'Введите целое число больше 0';

  @override
  String get defaultModelPageTranslateModelTitle => 'Модель перевода';

  @override
  String get defaultModelPageTranslateModelSubtitle =>
      'Переводит сообщения; лучше использовать быстрые и точные модели';

  @override
  String get defaultModelPageOcrModelTitle =>
      'Модель распознавания изображений';

  @override
  String backgroundTaskFailed(String task, String error) {
    return 'Ошибка задачи «$task»: $error';
  }

  @override
  String get defaultModelPageOcrModelSubtitle =>
      'Извлекает текст и описания из изображений';

  @override
  String get defaultModelPageOcrModelRequiresImageInput =>
      'Выберите модель с поддержкой изображений для распознавания текста';

  @override
  String get defaultModelPagePromptLabel => 'Промпт';

  @override
  String get defaultModelPageTitlePromptHint =>
      'Введите шаблон промпта для создания заголовков';

  @override
  String get defaultModelPageSummaryPromptHint =>
      'Введите шаблон промпта для создания сводок';

  @override
  String get defaultModelPageSuggestionPromptHint =>
      'Введите шаблон промпта для подсказок чата';

  @override
  String get defaultModelPageTranslatePromptHint =>
      'Введите шаблон промпта для перевода';

  @override
  String get defaultModelPageOcrPromptHint =>
      'Введите шаблон промпта для распознавания изображений';

  @override
  String get defaultModelPageResetDefault => 'Сбросить по умолчанию';

  @override
  String get defaultModelPageDisable => 'Отключить';

  @override
  String get defaultModelPageSave => 'Сохранить';

  @override
  String defaultModelPageTitleVars(String contentVar, String localeVar) {
    return 'Переменные: содержимое — $contentVar, язык — $localeVar';
  }

  @override
  String defaultModelPageSummaryVars(
    String previousSummaryVar,
    String userMessagesVar,
  ) {
    return 'Переменные: предыдущая сводка — $previousSummaryVar, новые сообщения — $userMessagesVar';
  }

  @override
  String defaultModelPageSuggestionVars(String contentVar, String localeVar) {
    return 'Переменные: диалог — $contentVar, язык — $localeVar';
  }

  @override
  String get defaultModelPageCompressModelTitle => 'Модель сжатия';

  @override
  String get defaultModelPageCompressModelSubtitle =>
      'Сжимает контекст диалога; лучше использовать быстрые модели';

  @override
  String get defaultModelPageCompressPromptHint =>
      'Введите шаблон промпта для сжатия контекста';

  @override
  String defaultModelPageCompressVars(String contentVar, String localeVar) {
    return 'Переменные: диалог — $contentVar, язык — $localeVar';
  }

  @override
  String defaultModelPageTranslateVars(String sourceVar, String targetVar) {
    return 'Переменные: исходный текст — $sourceVar, язык перевода — $targetVar';
  }

  @override
  String get defaultModelPageUseCurrentModel =>
      'Использовать текущую модель чата';

  @override
  String get defaultModelPageNotEnabled => 'Не включено';

  @override
  String get translatePagePasteButton => 'Вставить';

  @override
  String get translatePageCopyResult => 'Скопировать результат';

  @override
  String get translatePageClearAll => 'Очистить всё';

  @override
  String get translatePageInputHint => 'Введите текст для перевода…';

  @override
  String get translatePageOutputHint => 'Здесь появится перевод…';

  @override
  String get modelDetailSheetAddModel => 'Добавить модель';

  @override
  String get modelDetailSheetEditModel => 'Изменить модель';

  @override
  String get modelDetailSheetBasicTab => 'Основное';

  @override
  String get modelDetailSheetAdvancedTab => 'Дополнительно';

  @override
  String get modelDetailSheetBuiltinToolsTab => 'Встроенные инструменты';

  @override
  String get modelDetailSheetModelIdLabel => 'ID модели';

  @override
  String get modelDetailSheetModelIdHint =>
      'Обязательно; рекомендуются строчные буквы, цифры и дефисы';

  @override
  String modelDetailSheetModelIdDisabledHint(String modelId) {
    return '$modelId';
  }

  @override
  String get modelDetailSheetModelNameLabel => 'Название модели';

  @override
  String get modelDetailSheetModelTypeLabel => 'Тип модели';

  @override
  String get modelDetailSheetChatType => 'Чат';

  @override
  String get modelDetailSheetEmbeddingType => 'Эмбеддинги';

  @override
  String get modelDetailSheetInputModesLabel => 'Типы ввода';

  @override
  String get modelDetailSheetOutputModesLabel => 'Типы вывода';

  @override
  String get modelDetailSheetAbilitiesLabel => 'Возможности';

  @override
  String get modelDetailSheetTextMode => 'Текст';

  @override
  String get modelDetailSheetImageMode => 'Изображение';

  @override
  String get modelDetailSheetToolsAbility => 'Инструменты';

  @override
  String get modelDetailSheetReasoningAbility => 'Рассуждения';

  @override
  String get modelDetailSheetCustomHeadersTitle => 'Свои заголовки';

  @override
  String get modelDetailSheetAddHeader => 'Добавить заголовок';

  @override
  String get modelDetailSheetCustomBodyTitle => 'Свои поля тела запроса';

  @override
  String get modelFetchInvertTooltip => 'Инвертировать выбор';

  @override
  String get modelDetailSheetSaveFailedMessage =>
      'Не удалось сохранить. Повторите попытку.';

  @override
  String get modelDetailSheetAddBody => 'Добавить поле';

  @override
  String get modelDetailSheetBuiltinToolsDescription =>
      'Встроенные инструменты зависят от провайдера и режима API.';

  @override
  String get modelDetailSheetSearchTool => 'Поиск';

  @override
  String get modelDetailSheetSearchToolDescription =>
      'Включить интеграцию с Google Search';

  @override
  String get modelDetailSheetUrlContextTool => 'Контекст по URL';

  @override
  String get modelDetailSheetUrlContextToolDescription =>
      'Включить чтение содержимого по URL';

  @override
  String get modelDetailSheetCodeExecutionTool => 'Выполнение кода';

  @override
  String get modelDetailSheetCodeExecutionToolDescription =>
      'Включить инструмент выполнения кода';

  @override
  String get modelDetailSheetYoutubeTool => 'YouTube';

  @override
  String get modelDetailSheetYoutubeToolDescription =>
      'Включить чтение YouTube по URL (ссылки в промптах распознаются автоматически)';

  @override
  String get modelDetailSheetOpenaiBuiltinToolsResponsesOnlyHint =>
      'Требуется OpenAI Responses API.';

  @override
  String get modelDetailSheetWebFetchTool => 'Чтение веб-страниц';

  @override
  String get modelDetailSheetOpenrouterWebFetchToolDescription =>
      'Включить серверный инструмент чтения веб-страниц OpenRouter';

  @override
  String get modelDetailSheetClaudeWebFetchToolDescription =>
      'Разрешить Claude читать страницы и PDF по ссылкам из диалога';

  @override
  String get modelDetailSheetClaudeCodeExecutionToolDescription =>
      'Разрешить Claude выполнять Python и Bash в среде Anthropic';

  @override
  String get modelDetailSheetOpenrouterShellTool => 'Оболочка';

  @override
  String get modelDetailSheetOpenrouterShellToolDescription =>
      'Выполнять команды Shell в удалённой изолированной среде';

  @override
  String get modelDetailSheetOpenaiCodeInterpreterTool => 'Интерпретатор кода';

  @override
  String get modelDetailSheetOpenaiCodeInterpreterToolDescription =>
      'Включить интерпретатор кода (контейнер auto, лимит памяти 4g)';

  @override
  String get modelDetailSheetOpenaiImageGenerationTool =>
      'Генерация изображений';

  @override
  String get modelDetailSheetOpenaiImageGenerationToolDescription =>
      'Включить инструмент генерации изображений';

  @override
  String get modelDetailSheetCancelButton => 'Отмена';

  @override
  String get modelDetailSheetAddButton => 'Добавить';

  @override
  String get modelDetailSheetConfirmButton => 'Подтвердить';

  @override
  String get modelDetailSheetInvalidIdError =>
      'Введите корректный ID модели (не менее 2 символов)';

  @override
  String get modelDetailSheetModelIdExistsError =>
      'Такой ID модели уже существует';

  @override
  String get modelDetailSheetHeaderKeyHint => 'Ключ заголовка';

  @override
  String get modelDetailSheetHeaderValueHint => 'Значение заголовка';

  @override
  String get modelDetailSheetBodyKeyHint => 'Ключ поля';

  @override
  String get modelDetailSheetBodyJsonHint => 'Тело запроса JSON';

  @override
  String get modelSelectSheetSearchHint => 'Поиск моделей или провайдеров';

  @override
  String get modelSelectSheetFavoritesSection => 'Избранное';

  @override
  String get modelSelectSheetFollowAssistant => 'По настройке ассистента';

  @override
  String get modelSelectSheetFavoriteTooltip => 'В избранное';

  @override
  String get modelSelectSheetChatType => 'Чат';

  @override
  String get modelSelectSheetEmbeddingType => 'Эмбеддинги';

  @override
  String get providerDetailPageShareTooltip => 'Поделиться';

  @override
  String get providerDetailPageDeleteProviderTooltip => 'Удалить провайдера';

  @override
  String get providerDetailPageDeleteProviderTitle => 'Удалить провайдера';

  @override
  String get providerDetailPageDeleteProviderContent =>
      'Удалить этого провайдера? Отменить удаление нельзя.';

  @override
  String get providerDetailPageCancelButton => 'Отмена';

  @override
  String get providerDetailPageDeleteButton => 'Удалить';

  @override
  String get providerDetailPageProviderDeletedSnackbar => 'Провайдер удалён';

  @override
  String get providerDetailPageConfigTab => 'Конфигурация';

  @override
  String get providerDetailPageModelsTab => 'Модели';

  @override
  String get providerDetailPageCustomRequestTitle => 'Свой запрос';

  @override
  String get providerDetailPageCustomRequestDescription =>
      'Применяется ко всем моделям этого провайдера. Настройки модели имеют приоритет над этими значениями, а эти значения — над настройками ассистента.';

  @override
  String get providerDetailPageNetworkTab => 'Сеть';

  @override
  String get providerDetailPageEnabledTitle => 'Включено';

  @override
  String get providerDetailPageManageSectionTitle => 'Управление';

  @override
  String get providerDetailPageNameLabel => 'Имя';

  @override
  String get providerDetailPageApiKeyHint =>
      'Оставьте пустым для значения по умолчанию';

  @override
  String get providerDetailPageHideTooltip => 'Скрыть';

  @override
  String get providerDetailPageShowTooltip => 'Показать';

  @override
  String get providerDetailPageApiPathLabel => 'Путь API';

  @override
  String get providerDetailPageResponseApiTitle => 'Responses API (/responses)';

  @override
  String get providerDetailPageAihubmixAppCodeLabel => 'APP-Code (скидка 10%)';

  @override
  String get providerDetailPageAihubmixAppCodeHelp =>
      'Добавляет заголовок APP-Code в запросы для скидки 10%. Только для AIhubmix.';

  @override
  String get providerDetailPageClaudePromptCachingTitle =>
      'Кэширование промптов Claude';

  @override
  String get providerDetailPageClaudePromptCachingHelp =>
      'Добавляет cache_control в запросы Claude через Anthropic или OpenRouter.';

  @override
  String get providerDetailPageClaudePromptCachingTtlTitle =>
      'Время жизни кэша';

  @override
  String get providerDetailPageClaudePromptCachingTtlHelp =>
      'По умолчанию 5 минут. Запись на 1 час стоит дороже, но может сократить повторное создание кэша в длинных диалогах.';

  @override
  String get providerDetailPageClaudePromptCachingTtl5m => '5 мин';

  @override
  String get providerDetailPageClaudePromptCachingTtl1h => '1 час';

  @override
  String get providerDetailPageBalanceTitle => 'Баланс аккаунта';

  @override
  String get providerDetailPageBalanceInfo => 'Узнать баланс аккаунта';

  @override
  String get providerDetailPageBalanceApiPathLabel => 'Путь API баланса';

  @override
  String get providerDetailPageBalanceResultPathLabel =>
      'Путь к результату в JSON';

  @override
  String get providerDetailPageBalanceQueryButton => 'Проверить баланс';

  @override
  String get providerDetailPageBalanceQuerying => 'Проверка…';

  @override
  String get providerDetailPageBalanceResetDefaultsButton => 'Сбросить';

  @override
  String get providerDetailPageBalanceResetDefaultsTooltip =>
      'Сбросить настройки баланса';

  @override
  String providerDetailPageBalanceResult(String value) {
    return 'Баланс: $value';
  }

  @override
  String providerDetailPageBalanceError(String message) {
    return 'Не удалось узнать баланс: $message';
  }

  @override
  String get providerDetailPageVertexAiTitle => 'Vertex AI';

  @override
  String get providerDetailPageLocationLabel => 'Местоположение';

  @override
  String get providerDetailPageProjectIdLabel => 'ID проекта';

  @override
  String get providerDetailPageServiceAccountJsonLabel =>
      'JSON сервисного аккаунта (вставьте или импортируйте)';

  @override
  String get providerDetailPageImportJsonButton => 'Импортировать JSON';

  @override
  String get providerDetailPageImportJsonReadFailedMessage =>
      'Не удалось прочитать файл';

  @override
  String get providerDetailPageTestButton => 'Проверить';

  @override
  String get providerDetailPageSaveButton => 'Сохранить';

  @override
  String get providerDetailPageProviderRemovedMessage => 'Провайдер удалён';

  @override
  String get providerDetailPageNoModelsTitle => 'Нет моделей';

  @override
  String get providerDetailPageNoModelsSubtitle =>
      'Нажмите кнопки ниже, чтобы добавить модели';

  @override
  String get providerDetailPageDeleteModelButton => 'Удалить';

  @override
  String get providerDetailPageConfirmDeleteTitle => 'Подтвердите удаление';

  @override
  String get providerDetailPageConfirmDeleteContent =>
      'Это действие можно будет отменить. Удалить?';

  @override
  String get providerDetailPageModelDeletedSnackbar => 'Модель удалена';

  @override
  String get providerDetailPageUndoButton => 'Отменить';

  @override
  String get providerDetailPageAddNewModelButton => 'Добавить модель';

  @override
  String get providerDetailPageFetchModelsButton => 'Получить';

  @override
  String get providerDetailPageEnableProxyTitle => 'Включить прокси';

  @override
  String get providerDetailPageHostLabel => 'Хост';

  @override
  String get providerDetailPagePortLabel => 'Порт';

  @override
  String get providerDetailPageUsernameOptionalLabel =>
      'Имя пользователя (необязательно)';

  @override
  String get providerDetailPagePasswordOptionalLabel =>
      'Пароль (необязательно)';

  @override
  String get providerDetailPageSavedSnackbar => 'Сохранено';

  @override
  String get providerDetailPageEmbeddingsGroupTitle => 'Эмбеддинги';

  @override
  String get providerDetailPageOtherModelsGroupTitle => 'Другое';

  @override
  String get providerDetailPageRemoveGroupTooltip => 'Убрать группу';

  @override
  String get providerDetailPageAddGroupTooltip => 'Добавить группу';

  @override
  String get providerDetailPageFilterHint =>
      'Введите название модели для фильтрации';

  @override
  String get providerDetailPageDeleteText => 'Удалить';

  @override
  String get providerDetailPageEditTooltip => 'Изменить';

  @override
  String get providerDetailPageTestConnectionTitle => 'Проверить подключение';

  @override
  String get providerDetailPageSelectModelButton => 'Выбрать модель';

  @override
  String get providerDetailPageChangeButton => 'Изменить';

  @override
  String get providerDetailPageUseStreamingLabel =>
      'Использовать потоковый вывод';

  @override
  String get providerDetailPageTestingMessage => 'Проверка…';

  @override
  String get providerDetailPageTestSuccessMessage => 'Успешно';

  @override
  String get providersPageTitle => 'Провайдеры';

  @override
  String get providersPageImportTooltip => 'Импорт';

  @override
  String get providersPageAddTooltip => 'Добавить';

  @override
  String get providersPageSearchHint => 'Поиск провайдеров или групп';

  @override
  String get providersPageProviderAddedSnackbar => 'Провайдер добавлен';

  @override
  String get providerGroupsGroupLabel => 'Группа';

  @override
  String get providerGroupsOther => 'Другое';

  @override
  String get providerGroupsOtherUngroupedOption => 'Другие (без группы)';

  @override
  String get providerGroupsPickerTitle => 'Выберите группу';

  @override
  String get providerGroupsManageTitle => 'Управление группами';

  @override
  String get providerGroupsManageAction => 'Управление группами';

  @override
  String get providerGroupsCreateNewGroupAction => 'Новая группа…';

  @override
  String get providerGroupsCreateDialogTitle => 'Новая группа';

  @override
  String get providerGroupsNameHint => 'Название группы';

  @override
  String get providerGroupsCreateDialogCancel => 'Отмена';

  @override
  String get providerGroupsCreateDialogOk => 'Создать';

  @override
  String get providerGroupsCreateFailedToast => 'Не удалось создать группу';

  @override
  String get providerGroupsDeleteConfirmTitle => 'Удалить группу?';

  @override
  String get providerGroupsDeleteConfirmContent =>
      'Провайдеры этой группы будут перемещены в «Другие».';

  @override
  String get providerGroupsDeleteConfirmCancel => 'Отмена';

  @override
  String get providerGroupsDeleteConfirmOk => 'Удалить';

  @override
  String get providerGroupsDeletedToast => 'Группа удалена';

  @override
  String get providerGroupsEmptyState => 'Групп пока нет.';

  @override
  String get providerGroupsExpandToMoveToast => 'Сначала разверните группу.';

  @override
  String get providersPageSiliconFlowName => 'SiliconFlow';

  @override
  String get providersPageAliyunName => 'Aliyun';

  @override
  String get providersPageZhipuName => 'Zhipu AI';

  @override
  String get providersPageByteDanceName => 'ByteDance';

  @override
  String get providersPageEnabledStatus => 'ВКЛ.';

  @override
  String get providersPageDisabledStatus => 'ВЫКЛ.';

  @override
  String get providersPageModelsCountSuffix => ' моделей';

  @override
  String get providersPageModelsCountSingleSuffix => ' моделей';

  @override
  String get addProviderSheetTitle => 'Добавить провайдера';

  @override
  String get addProviderSheetEnabledLabel => 'Включено';

  @override
  String get addProviderSheetNameLabel => 'Имя';

  @override
  String get addProviderSheetApiPathLabel => 'Путь API';

  @override
  String get addProviderSheetVertexAiLocationLabel => 'Местоположение';

  @override
  String get addProviderSheetVertexAiProjectIdLabel => 'ID проекта';

  @override
  String get addProviderSheetVertexAiServiceAccountJsonLabel =>
      'JSON сервисного аккаунта (вставьте или импортируйте)';

  @override
  String get addProviderSheetImportJsonButton => 'Импортировать JSON';

  @override
  String get addProviderSheetCancelButton => 'Отмена';

  @override
  String get addProviderSheetAddButton => 'Добавить';

  @override
  String get importProviderSheetTitle => 'Импортировать провайдера';

  @override
  String get importProviderSheetScanQrTooltip => 'Сканировать QR';

  @override
  String get importProviderSheetFromGalleryTooltip => 'Из галереи';

  @override
  String importProviderSheetImportSuccessMessage(int count) {
    return 'Импортировано провайдеров: $count';
  }

  @override
  String importProviderSheetImportFailedMessage(String error) {
    return 'Не удалось импортировать: $error';
  }

  @override
  String get importProviderSheetDescription =>
      'Вставьте строки конфигурации (можно несколько строк) или JSON ChatBox';

  @override
  String get importProviderSheetInputHint => 'ai-provider:v1:... или JSON';

  @override
  String get importProviderSheetCancelButton => 'Отмена';

  @override
  String get importProviderSheetImportButton => 'Импорт';

  @override
  String get shareProviderSheetTitle => 'Поделиться провайдером';

  @override
  String get shareProviderSheetDescription =>
      'Скопируйте конфигурацию или поделитесь QR-кодом.';

  @override
  String get shareProviderSheetCopiedMessage => 'Скопировано';

  @override
  String get shareProviderSheetCopyButton => 'Копировать';

  @override
  String get shareProviderSheetShareButton => 'Поделиться';

  @override
  String get desktopProviderContextMenuShare => 'Поделиться';

  @override
  String get desktopProviderShareCopyText => 'Скопировать код';

  @override
  String get desktopProviderShareCopyQr => 'Скопировать QR';

  @override
  String get providerDetailPageApiBaseUrlLabel => 'Базовый URL API';

  @override
  String get providerDetailPageModelsTitle => 'Модели';

  @override
  String get providerModelsGetButton => 'Получить';

  @override
  String get providerDetailPageCapsVision => 'Зрение';

  @override
  String get providerDetailPageCapsImage => 'Изображение';

  @override
  String get providerDetailPageCapsTool => 'Инструмент';

  @override
  String get providerDetailPageCapsReasoning => 'Рассуждения';

  @override
  String get qrScanPageTitle => 'Сканировать QR';

  @override
  String get qrScanPageInstruction => 'Поместите QR-код в рамку';

  @override
  String get searchServicesPageBackTooltip => 'Назад';

  @override
  String get searchServicesPageTitle => 'Сервисы поиска';

  @override
  String get searchServicesPageDone => 'Готово';

  @override
  String get searchServicesPageEdit => 'Изменить';

  @override
  String get searchServicesPageAddProvider => 'Добавить провайдера';

  @override
  String get searchServicesPageSearchProviders => 'Поисковые провайдеры';

  @override
  String get searchServicesPageGeneralOptions => 'Общие параметры';

  @override
  String get searchServicesPageAutoTestTitle =>
      'Проверять подключения при запуске';

  @override
  String get searchServicesPageMaxResults => 'Максимум результатов';

  @override
  String get searchServicesPageTimeoutSeconds => 'Тайм-аут (секунды)';

  @override
  String get searchServicesPageAtLeastOneServiceRequired =>
      'Нужен хотя бы один сервис поиска';

  @override
  String get searchServicesPageTestingStatus => 'Проверка…';

  @override
  String get searchServicesPageConnectedStatus => 'Подключено';

  @override
  String get searchServicesPageFailedStatus => 'Ошибка';

  @override
  String get searchServicesPageNotTestedStatus => 'Не проверено';

  @override
  String get searchServicesPageEditServiceTooltip => 'Изменить сервис';

  @override
  String get searchServicesPageTestConnectionTooltip => 'Проверить подключение';

  @override
  String get searchServicesPageDeleteServiceTooltip => 'Удалить сервис';

  @override
  String get searchServicesPageConfiguredStatus => 'Настроено';

  @override
  String get miniMapTitle => 'Мини-карта';

  @override
  String get miniMapTooltip => 'Мини-карта';

  @override
  String get miniMapScrollToBottomTooltip => 'Прокрутить вниз';

  @override
  String miniMapSearchMatchCount(int count) {
    return '$count';
  }

  @override
  String get miniMapSearchNoResults => 'Подходящие сообщения не найдены';

  @override
  String get searchServicesPageApiKeyRequiredStatus => 'Нужен API-ключ';

  @override
  String get searchServicesPageUrlRequiredStatus => 'Нужен URL';

  @override
  String get searchServicesAddDialogTitle => 'Добавить сервис поиска';

  @override
  String get searchServicesAddDialogServiceType => 'Тип сервиса';

  @override
  String get searchServicesAddDialogBingLocal => 'Локальный';

  @override
  String get searchServicesAddDialogCancel => 'Отмена';

  @override
  String get searchServicesAddDialogAdd => 'Добавить';

  @override
  String get searchServicesAddDialogApiKeyRequired =>
      'Необходимо указать API-ключ';

  @override
  String get searchServicesFieldCustomUrlOptional => 'Свой URL (необязательно)';

  @override
  String get searchServicesDialogApiKey => 'API-ключ';

  @override
  String get searchServicesDialogModel => 'Модель';

  @override
  String get searchServicesDialogSystemPrompt => 'Системный промпт';

  @override
  String get searchServicesAddDialogInstanceUrl => 'URL экземпляра';

  @override
  String get searchServicesAddDialogUrlRequired => 'Необходимо указать URL';

  @override
  String get searchServicesAddDialogEnginesOptional =>
      'Поисковые движки (необязательно)';

  @override
  String get searchServicesAddDialogLanguageOptional => 'Язык (необязательно)';

  @override
  String get searchServicesAddDialogUsernameOptional =>
      'Имя пользователя (необязательно)';

  @override
  String get searchServicesAddDialogPasswordOptional =>
      'Пароль (необязательно)';

  @override
  String get searchServicesAddDialogRegionOptional =>
      'Регион (необязательно, по умолчанию us-en)';

  @override
  String get searchServicesEditDialogEdit => 'Изменить';

  @override
  String get searchServicesEditDialogCancel => 'Отмена';

  @override
  String get searchServicesEditDialogSave => 'Сохранить';

  @override
  String get searchServicesEditDialogBingLocalNoConfig =>
      'Локальный поиск Bing не требует настройки.';

  @override
  String get searchServicesEditDialogApiKeyRequired =>
      'Необходимо указать API-ключ';

  @override
  String get searchServicesEditDialogInstanceUrl => 'URL экземпляра';

  @override
  String get searchServicesEditDialogUrlRequired => 'Необходимо указать URL';

  @override
  String get searchServicesEditDialogEnginesOptional =>
      'Поисковые движки (необязательно)';

  @override
  String get searchServicesEditDialogLanguageOptional => 'Язык (необязательно)';

  @override
  String get searchServicesEditDialogUsernameOptional =>
      'Имя пользователя (необязательно)';

  @override
  String get searchServicesEditDialogPasswordOptional =>
      'Пароль (необязательно)';

  @override
  String get searchServicesEditDialogRegionOptional =>
      'Регион (необязательно, по умолчанию us-en)';

  @override
  String get searchServiceEditorProviderTypeTitle => 'Провайдер поиска';

  @override
  String get searchServiceEditorConfigurationTitle => 'Конфигурация';

  @override
  String get searchServiceEditorNoConfiguration =>
      'Этот провайдер не требует дополнительной настройки.';

  @override
  String get searchServiceEditorMultiKeyTitle => 'Чередование ключей';

  @override
  String get searchServiceEditorMultiKeyNone => 'Не настроено';

  @override
  String get searchApiKeysPageDescription =>
      'Ключи используются по очереди в указанном порядке; первый — основной. Расход не запрашивается, чтобы не попасть под ограничения провайдера.';

  @override
  String get searchApiKeysPagePrimaryBadge => 'Основной';

  @override
  String get searchApiKeysPageBatchHint =>
      'Вставьте один или несколько ключей — по одному в строке или через запятую';

  @override
  String searchApiKeysPageBatchResult(String added, String skipped) {
    return 'Добавлено: $added; пропущено повторов: $skipped';
  }

  @override
  String get searchApiKeysPageAdd => 'Добавить';

  @override
  String get searchApiKeysPageEmpty => 'Ключи пока не настроены.';

  @override
  String searchServiceEditorMultiKeyCount(String count) {
    return 'Ключей: $count';
  }

  @override
  String get searchServiceEditorUsageTitle => 'Расход аккаунта';

  @override
  String get searchServiceEditorUsageNotQueried =>
      'Расход ещё не запрашивался.';

  @override
  String get searchServiceEditorUsageQuery => 'Проверить расход';

  @override
  String get searchServiceEditorUsageQuerying => 'Проверка…';

  @override
  String searchServiceEditorUsageRemaining(String remaining) {
    return 'Осталось кредитов: $remaining';
  }

  @override
  String searchServiceEditorUsageBalance(String balance) {
    return 'Баланс: $balance';
  }

  @override
  String searchServiceEditorUsageUsed(String used, String limit) {
    return 'Использовано кредитов: $used из $limit';
  }

  @override
  String searchServiceEditorUsageFailed(String message) {
    return 'Не удалось узнать расход: $message';
  }

  @override
  String get searchServiceEditorTestTitle => 'Проверка поиска';

  @override
  String get searchServiceEditorTestQueryHint => 'Введите запрос';

  @override
  String get searchServiceEditorTestRun => 'Выполнить тестовый поиск';

  @override
  String get searchServiceEditorTestRunning => 'Поиск…';

  @override
  String get searchServiceEditorTestNoResults =>
      'Провайдер не вернул результатов.';

  @override
  String searchServiceEditorTestFailed(String message) {
    return 'Не удалось выполнить поиск: $message';
  }

  @override
  String get searchServiceEditorResultOpenTooltip => 'Открыть результат';

  @override
  String get searchServiceEditorDeleteTooltip => 'Удалить сервис поиска';

  @override
  String get searchServiceEditorDeleteTitle => 'Удалить сервис поиска?';

  @override
  String searchServiceEditorDeleteMessage(String provider) {
    return 'Удалить $provider? Отменить удаление нельзя.';
  }

  @override
  String get searchServiceEditorDeleteConfirm => 'Удалить';

  @override
  String get searchServiceEditorDiscardTitle => 'Отменить изменения?';

  @override
  String get searchServiceEditorDiscardMessage =>
      'Несохранённые настройки сервиса поиска будут потеряны.';

  @override
  String get searchServiceEditorKeepEditing => 'Продолжить редактирование';

  @override
  String get searchServiceEditorDiscard => 'Не сохранять';

  @override
  String get searchSettingsSheetTitle => 'Настройки поиска';

  @override
  String get searchSettingsSheetBuiltinSearchTitle => 'Встроенный поиск';

  @override
  String get searchSettingsSheetBuiltinSearchDescription =>
      'Включить встроенный поиск модели';

  @override
  String get searchSettingsSheetClaudeDynamicSearchTitle =>
      'Динамическая фильтрация';

  @override
  String get searchSettingsSheetClaudeDynamicSearchDescription =>
      'Фильтровать результаты для экономии токенов';

  @override
  String get searchSettingsSheetWebSearchTitle => 'Веб-поиск';

  @override
  String get searchSettingsSheetWebSearchDescription =>
      'Включить поиск в интернете в чате';

  @override
  String get searchSettingsSheetOpenSearchServicesTooltip =>
      'Открыть сервисы поиска';

  @override
  String get searchSettingsSheetNoServicesMessage =>
      'Нет сервисов. Добавьте их в разделе «Сервисы поиска».';

  @override
  String get aboutPageEasterEggMessage =>
      'Спасибо за любопытство!\n(Пасхалки пока нет)';

  @override
  String get aboutPageEasterEggButton => 'Отлично!';

  @override
  String get aboutPageKelivoSearchUnlocked =>
      'Неизвестная дверь приоткрылась. Возможно, вы найдёте её в настройках.';

  @override
  String get aboutPageKelivoSearchAlreadyUnlocked =>
      'Вы уже проходили через эту дверь.';

  @override
  String get aboutPageAppName => 'Moru';

  @override
  String get aboutPageAppDescription =>
      'ИИ-ассистент с открытым исходным кодом';

  @override
  String get aboutPageNoQQGroup => 'Группы QQ пока нет';

  @override
  String get aboutPageVersion => 'Версия';

  @override
  String aboutPageVersionDetail(String version, String buildNumber) {
    return '$version / $buildNumber';
  }

  @override
  String get aboutPageSystem => 'Системная';

  @override
  String get aboutPageLoadingPlaceholder => '...';

  @override
  String get aboutPageUnknownPlaceholder => '-';

  @override
  String get aboutPagePlatformMacos => 'macOS';

  @override
  String get aboutPagePlatformWindows => 'Windows';

  @override
  String get aboutPagePlatformLinux => 'Linux';

  @override
  String get aboutPagePlatformAndroid => 'Android';

  @override
  String get aboutPagePlatformIos => 'iOS';

  @override
  String aboutPagePlatformOther(String os) {
    return 'Другая ($os)';
  }

  @override
  String get aboutPageWebsite => 'Сайт';

  @override
  String get aboutPageGithub => 'GitHub';

  @override
  String get aboutPageLicense => 'Лицензия';

  @override
  String get aboutPageJoinQQGroup => 'Присоединиться к группе QQ';

  @override
  String get aboutPageQQGroupOne => 'Группа Kelivo 1';

  @override
  String get aboutPageQQGroupTwo => 'Группа Kelivo 2';

  @override
  String get aboutPageQQGroupThree => 'Группа Kelivo 3';

  @override
  String get aboutPageJoinDiscord => 'Присоединиться к Discord';

  @override
  String get displaySettingsPageShowUserAvatarTitle =>
      'Показывать аватар пользователя';

  @override
  String get displaySettingsPageShowUserAvatarSubtitle =>
      'Отображать аватар пользователя в сообщениях чата';

  @override
  String get displaySettingsPageShowUserNameTimestampTitle =>
      'Имя пользователя и время';

  @override
  String get displaySettingsPageShowUserNameTimestampSubtitle =>
      'Показывать имя пользователя и время под ним в сообщениях чата';

  @override
  String get displaySettingsPageShowUserNameTitle =>
      'Показывать имя пользователя';

  @override
  String get displaySettingsPageShowUserTimestampTitle =>
      'Показывать время сообщений пользователя';

  @override
  String get displaySettingsPageShowUserMessageActionsTitle =>
      'Действия под сообщениями пользователя';

  @override
  String get displaySettingsPageShowUserMessageActionsSubtitle =>
      'Показывать кнопки копирования, повторной отправки и других действий под вашими сообщениями';

  @override
  String get displaySettingsPageShowModelNameTimestampTitle =>
      'Название модели и время';

  @override
  String get displaySettingsPageShowModelNameTimestampSubtitle =>
      'Показывать название модели и время под ним в сообщениях чата';

  @override
  String get displaySettingsPageShowModelNameTitle =>
      'Показывать название модели';

  @override
  String get displaySettingsPageShowModelTimestampTitle =>
      'Показывать время ответов модели';

  @override
  String get displaySettingsPageShowProviderInChatMessageTitle =>
      'Провайдер после названия модели';

  @override
  String get displaySettingsPageShowProviderInChatMessageSubtitle =>
      'Показывать провайдера после ID модели в чате (например: модель | провайдер)';

  @override
  String get displaySettingsPageChatModelIconTitle => 'Значок модели в чате';

  @override
  String get displaySettingsPageChatModelIconSubtitle =>
      'Показывать значок модели в сообщениях чата';

  @override
  String get displaySettingsPageShowTokenStatsTitle =>
      'Статистика токенов и контекста';

  @override
  String get displaySettingsPageShowTokenStatsSubtitle =>
      'Показывать расход токенов и количество сообщений';

  @override
  String get displaySettingsPageShowThinkingCardsTitle =>
      'Показывать карточки рассуждений';

  @override
  String get displaySettingsPageShowThinkingCardsSubtitle =>
      'Если отключено, карточки рассуждений скрыты в чате.';

  @override
  String get displaySettingsPageShowToolCardsTitle =>
      'Показывать карточки инструментов';

  @override
  String get displaySettingsPageShowToolCardsSubtitle =>
      'Если отключено, карточки вызовов инструментов скрыты в чате.';

  @override
  String get displaySettingsPageAutoCollapseThinkingTitle =>
      'Автоматически сворачивать рассуждения';

  @override
  String get displaySettingsPageAutoCollapseThinkingSubtitle =>
      'Сворачивать рассуждения после завершения';

  @override
  String get displaySettingsPageCollapseThinkingStepsTitle =>
      'Сворачивать этапы рассуждений';

  @override
  String get displaySettingsPageCollapseThinkingStepsSubtitle =>
      'Показывать только последние этапы до раскрытия';

  @override
  String get displaySettingsPageShowToolResultSummaryTitle =>
      'Показывать сводку результатов инструментов';

  @override
  String get displaySettingsPageInsertSuggestionOnlyTitle =>
      'Вставлять подсказки без отправки';

  @override
  String get displaySettingsPageShowToolResultSummarySubtitle =>
      'Показывать краткий результат под этапами работы инструментов';

  @override
  String get displaySettingsPageHideToolResultImagesTitle =>
      'Скрывать изображения в результатах инструментов';

  @override
  String get displaySettingsPageRegenerateDeleteTrailingMessagesTitle =>
      'Удалять сообщения ниже при повторной генерации';

  @override
  String get displaySettingsPageShowRegenerateConfirmDialogTitle =>
      'Подтверждать повторную генерацию';

  @override
  String get displaySettingsPageForkKeepMessageVersionsTitle =>
      'Сохранять версии сообщений при создании ветки';

  @override
  String get displaySettingsPageEditAssistantKeepThinkingToolCardsTitle =>
      'Сохранять рассуждения и инструменты при редактировании ответа';

  @override
  String get displaySettingsPageEditAssistantKeepThinkingToolCardsSubtitle =>
      'Если отключено, в изменённой версии останется только текст ассистента. Предыдущие рассуждения и карточки инструментов доступны при возврате к старой версии.';

  @override
  String chainOfThoughtExpandSteps(Object count) {
    return 'Показать ещё этапов: $count';
  }

  @override
  String get chainOfThoughtCollapse => 'Свернуть';

  @override
  String get displaySettingsPageShowChatListDateTitle =>
      'Показывать даты в списке чатов';

  @override
  String get displaySettingsPageShowChatListDateSubtitle =>
      'Группировать диалоги по датам и показывать подписи групп';

  @override
  String get displaySettingsPageEnableImageCropperTitle =>
      'Обрезка изображений';

  @override
  String get displaySettingsPageEnableImageCropperSubtitle =>
      'Обрезать изображения после выбора из галереи или съёмки';

  @override
  String get displaySettingsPageKeepSidebarOpenOnAssistantTapTitle =>
      'Не закрывать боковую панель при выборе ассистента';

  @override
  String get displaySettingsPageKeepSidebarOpenOnTopicTapTitle =>
      'Не закрывать боковую панель при выборе темы';

  @override
  String get displaySettingsPageKeepAssistantListExpandedOnSidebarCloseTitle =>
      'Не сворачивать список ассистентов при закрытии панели';

  @override
  String get displaySettingsPageShowUpdatesTitle => 'Показывать обновления';

  @override
  String get displaySettingsPageShowUpdatesSubtitle =>
      'Показывать уведомления об обновлениях приложения';

  @override
  String get displaySettingsPageKeepScreenOnDuringGenerationTitle =>
      'Не выключать экран во время генерации';

  @override
  String get displaySettingsPageKeepScreenOnDuringGenerationSubtitle =>
      'Предотвращает прерывание генерации блокировкой экрана. Увеличивает расход батареи.';

  @override
  String get displaySettingsPageMessageNavButtonsTitle =>
      'Кнопки навигации по сообщениям';

  @override
  String get displaySettingsPageMessageNavButtonsSubtitle =>
      'Когда показывать кнопки быстрого перехода';

  @override
  String get displaySettingsPageMessageNavButtonsModeAlways => 'Всегда';

  @override
  String get displaySettingsPageMessageNavButtonsModeScroll => 'При прокрутке';

  @override
  String get displaySettingsPageMessageNavButtonsModeHover =>
      'При наведении мыши';

  @override
  String get displaySettingsPageMessageNavButtonsModeScrollAndHover =>
      'При прокрутке или наведении';

  @override
  String get displaySettingsPageMessageNavButtonsModeNever =>
      'Никогда не показывать';

  @override
  String get displaySettingsPageUseNewAssistantAvatarUxTitle =>
      'Аватар ассистента в заголовке чата';

  @override
  String get displaySettingsPageHapticsOnSidebarTitle =>
      'Виброотклик боковой панели';

  @override
  String get displaySettingsPageHapticsOnSidebarSubtitle =>
      'Виброотклик при открытии и закрытии боковой панели';

  @override
  String get displaySettingsPageHapticsGlobalTitle => 'Общий виброотклик';

  @override
  String get displaySettingsPageHapticsIosSwitchTitle =>
      'Виброотклик переключателей';

  @override
  String get displaySettingsPageHapticsOnListItemTapTitle =>
      'Виброотклик элементов списка';

  @override
  String get displaySettingsPageHapticsOnCardTapTitle => 'Виброотклик карточек';

  @override
  String get displaySettingsPageHapticsOnGenerateTitle =>
      'Виброотклик при генерации';

  @override
  String get displaySettingsPageHapticsOnGenerateSubtitle =>
      'Включить виброотклик во время генерации';

  @override
  String get displaySettingsPageNewChatAfterDeleteTitle =>
      'Новый чат после удаления темы';

  @override
  String get displaySettingsPageNewChatOnAssistantSwitchTitle =>
      'Новый чат при смене ассистента';

  @override
  String get displaySettingsPageNewChatOnLaunchTitle => 'Новый чат при запуске';

  @override
  String get displaySettingsPageEnterToSendTitle => 'Отправлять по Enter';

  @override
  String get displaySettingsPageLongPasteAsFileTitle =>
      'Вставлять длинный текст как файл';

  @override
  String get displaySettingsPageLongPasteAsFileThresholdTitle =>
      'Порог преобразования';

  @override
  String get displaySettingsPageLongPasteAsFileThresholdUnit => 'символов';

  @override
  String get displaySettingsPageSendShortcutTitle => 'Клавиши отправки';

  @override
  String get displaySettingsPageSendShortcutEnter => 'Enter';

  @override
  String get displaySettingsPageSendShortcutCtrlEnter => 'Ctrl/Cmd + Enter';

  @override
  String get displaySettingsPageAutoSwitchTopicsTitle =>
      'Автоматически переходить к темам';

  @override
  String get desktopDisplaySettingsTopicPositionTitle => 'Расположение тем';

  @override
  String get desktopDisplaySettingsTopicPositionLeft => 'Слева';

  @override
  String get desktopDisplaySettingsTopicPositionRight => 'Справа';

  @override
  String get displaySettingsPageNewChatOnLaunchSubtitle =>
      'Автоматически создавать новый чат при запуске';

  @override
  String get displaySettingsPageChatFontSizeTitle => 'Размер шрифта чата';

  @override
  String get displaySettingsPageAutoScrollEnableTitle => 'Автопрокрутка вниз';

  @override
  String get displaySettingsPageAutoScrollIdleTitle =>
      'Задержка возврата автопрокрутки';

  @override
  String get displaySettingsPageAutoScrollIdleSubtitle =>
      'Время ожидания после ручной прокрутки перед переходом вниз';

  @override
  String get displaySettingsPageAutoScrollDisabledLabel => 'Выкл.';

  @override
  String get displaySettingsPageChatFontSampleText =>
      'Это пример текста в чате';

  @override
  String get displaySettingsPageChatBackgroundMaskTitle =>
      'Непрозрачность затемнения фона чата';

  @override
  String get displaySettingsPageChatInputBackgroundOpacityTitle =>
      'Непрозрачность фона поля ввода';

  @override
  String get displaySettingsPageThemeSettingsTitle => 'Настройки темы';

  @override
  String get displaySettingsPageThemeColorTitle => 'Цвет темы';

  @override
  String get desktopSettingsFontsTitle => 'Шрифты';

  @override
  String get displaySettingsPageTrayTitle => 'Системный трей';

  @override
  String get displaySettingsPageTrayShowTrayTitle => 'Показывать значок в трее';

  @override
  String get displaySettingsPageTrayMinimizeOnCloseTitle =>
      'Сворачивать в трей при закрытии';

  @override
  String get desktopFontAppLabel => 'Шрифт приложения';

  @override
  String get desktopFontCodeLabel => 'Шрифт кода';

  @override
  String get desktopFontFamilySystemDefault => 'Системный по умолчанию';

  @override
  String get desktopFontFamilyMonospaceDefault => 'Моноширинный';

  @override
  String get desktopFontFilterHint => 'Поиск шрифтов…';

  @override
  String get displaySettingsPageAppFontTitle => 'Шрифт приложения';

  @override
  String get displaySettingsPageCodeFontTitle => 'Шрифт кода';

  @override
  String get fontPickerChooseLocalFile => 'Выбрать локальный файл';

  @override
  String get desktopFontLoading => 'Загрузка шрифтов…';

  @override
  String get displaySettingsPageFontLocalFileLabel => 'Локальный файл';

  @override
  String get displaySettingsPageFontResetLabel => 'Сбросить настройки шрифтов';

  @override
  String get displaySettingsPageOtherSettingsTitle => 'Другие настройки';

  @override
  String get themeSettingsPageDynamicColorSection => 'Динамические цвета';

  @override
  String get themeSettingsPageUseDynamicColorTitle =>
      'Системные динамические цвета';

  @override
  String get themeSettingsPageUseDynamicColorSubtitle =>
      'Использовать системную палитру (Android 12+)';

  @override
  String get themeSettingsPageUsePureBackgroundTitle => 'Чистый фон';

  @override
  String get themeSettingsPageUsePureBackgroundSubtitle =>
      'Пузыри сообщений и акценты соответствуют теме.';

  @override
  String get themeAdvancedSettingsPageTitle => 'Дополнительные настройки темы';

  @override
  String get themeAdvancedSettingsPageUseLayeredSurfacesTitle =>
      'Многослойные поверхности (экспериментально)';

  @override
  String get themeAdvancedSettingsPageUseLayeredSurfacesSubtitle =>
      'Более тёмная страница и светлые карточки с оттенком темы. Отключите, чтобы вернуть прежний вид.';

  @override
  String get themeAdvancedSettingsPageUseLayeredSheetTilesTitle =>
      'Многослойные элементы панелей';

  @override
  String get themeAdvancedSettingsPageUseLayeredSheetTilesSubtitle =>
      'По умолчанию элементы совпадают с фоном панели.';

  @override
  String get themeSettingsPageColorPalettesSection => 'Цветовые палитры';

  @override
  String get themeSettingsPageCustomPaletteName => 'Свой вариант';

  @override
  String get themeSettingsPageCustomColorReset => 'Сбросить';

  @override
  String get themeSettingsPageCustomThemesSection => 'Свои темы';

  @override
  String get customThemeNewTheme => 'Новая тема';

  @override
  String get customThemeEditTheme => 'Изменить тему';

  @override
  String get customThemeImportTheme => 'Импортировать тему';

  @override
  String get customThemeNameLabel => 'Название темы';

  @override
  String get customThemePrimaryColor => 'Основной';

  @override
  String get customThemeSecondaryColor => 'Вторичный';

  @override
  String get customThemeTertiaryColor => 'Третичный';

  @override
  String get customThemeColorAuto => 'Авто';

  @override
  String get customThemeSave => 'Сохранить';

  @override
  String get customThemeCancel => 'Отмена';

  @override
  String get customThemeDelete => 'Удалить';

  @override
  String get customThemeDeleteConfirm => 'Удалить эту тему?';

  @override
  String get customThemeCopied => 'JSON темы скопирован в буфер обмена';

  @override
  String get customThemeCopyAction => 'Копировать';

  @override
  String get customThemeImportHint => 'Вставьте сюда JSON темы';

  @override
  String get customThemeImportInvalid => 'Некорректный JSON темы';

  @override
  String get customThemeHexLabel => 'HEX';

  @override
  String get ttsServicesPageBackButton => 'Назад';

  @override
  String get ttsServicesPageTitle => 'Голосовые сервисы';

  @override
  String get ttsServicesSectionTitle => 'Синтез речи';

  @override
  String get ttsServicesPageSettingsTooltip => 'Настройки синтеза речи';

  @override
  String get ttsServicesPageAddTooltip => 'Добавить';

  @override
  String get asrServicesSectionTitle => 'Распознавание речи';

  @override
  String get asrServicesSectionDescription =>
      'Преобразование речи в текст на устройстве, системным или облачным сервисом.';

  @override
  String get asrServicesAddTooltip => 'Добавить сервис распознавания речи';

  @override
  String get asrServicesEmptyTitle => 'Нет сервиса распознавания речи';

  @override
  String get asrServicesEmptySubtitle =>
      'Добавьте сервис, чтобы в поле ввода чата появился микрофон.';

  @override
  String get asrServicesOnDeviceGroup => 'На устройстве';

  @override
  String get asrServicesCloudGroup => 'Облако';

  @override
  String get asrServicesSystemTitle => 'Системная';

  @override
  String get asrServicesSystemSubtitle =>
      'Использует встроенное распознавание речи устройства';

  @override
  String get asrServicesLocalTitle => 'Офлайн-модель';

  @override
  String get asrServicesLocalSubtitle =>
      'После загрузки работает на устройстве без интернета';

  @override
  String get asrServicesOpenAiTitle => 'OpenAI Realtime';

  @override
  String get asrServicesOpenAiSubtitle =>
      'Потоковое распознавание с малой задержкой';

  @override
  String get asrServicesDashScopeTitle => 'DashScope';

  @override
  String get asrServicesDashScopeSubtitle =>
      'Распознавание Qwen в реальном времени';

  @override
  String get asrServicesVolcengineTitle => 'Volcengine';

  @override
  String get asrServicesVolcengineSubtitle => 'Потоковое распознавание Doubao';

  @override
  String get asrServicesMimoTitle => 'MiMo';

  @override
  String get asrServicesMimoSubtitle => 'Поэтапное облачное распознавание';

  @override
  String get asrServicesStepTitle => 'Step';

  @override
  String get asrServicesStepSubtitle => 'Поэтапное распознавание Step Audio';

  @override
  String get asrServicesAddTitle => 'Добавить распознавание речи';

  @override
  String get asrServicesEditTitle => 'Изменить распознавание речи';

  @override
  String get asrServicesSelectedLabel => 'Выбрано';

  @override
  String get asrServicesUnavailableLabel => 'Недоступно';

  @override
  String get asrServicesEditAction => 'Изменить';

  @override
  String get asrServicesDeleteAction => 'Удалить';

  @override
  String get asrServicesCancelAction => 'Отмена';

  @override
  String get asrServicesAddAction => 'Добавить';

  @override
  String get asrServicesSaveAction => 'Сохранить';

  @override
  String get asrServicesNameLabel => 'Имя';

  @override
  String get asrServicesApiKeyLabel => 'API-ключ';

  @override
  String get asrServicesEndpointLabel => 'Адрес сервера';

  @override
  String get asrServicesModelLabel => 'Модель';

  @override
  String get asrServicesResourceIdLabel => 'ID ресурса';

  @override
  String get asrServicesLanguageLabel => 'Язык';

  @override
  String get asrServicesAutomaticLabel => 'Автоматически';

  @override
  String get asrServicesApiKeyRequired =>
      'Введите API-ключ для использования этого сервиса.';

  @override
  String get asrServicesChooseModelTitle => 'Модель';

  @override
  String get asrServicesModelDownloadAction => 'Скачать';

  @override
  String get asrServicesModelUseAction => 'Использовать модель';

  @override
  String get asrServicesModelDeleteAction => 'Удалить загрузку';

  @override
  String get asrServicesModelDownloadedLabel => 'Загружено';

  @override
  String get asrServicesModelDownloadingLabel => 'Загрузка…';

  @override
  String get asrServicesModelNotDownloadedLabel => 'Не загружено';

  @override
  String asrServicesDownloadFailed(String error) {
    return 'Не удалось загрузить модель: $error';
  }

  @override
  String get asrServicesSystemChecking => 'Проверка…';

  @override
  String get asrServicesSystemAvailable => 'Доступно';

  @override
  String get asrServicesSystemCheckFailed =>
      'Системное распознавание речи недоступно на этом устройстве.';

  @override
  String get asrServicesMicrophonePermissionDenied =>
      'Разрешение на использование микрофона не предоставлено.';

  @override
  String get asrServicesNoSpeechDetected => 'Речь не обнаружена.';

  @override
  String asrServicesRecognitionFailed(String error) {
    return 'Не удалось распознать речь: $error';
  }

  @override
  String get ttsServicesPageAddNotImplemented =>
      'Добавление сервиса синтеза речи пока не реализовано';

  @override
  String get ttsServicesPageSystemTtsTitle => 'Системный синтез речи';

  @override
  String get ttsServicesPageSystemTtsAvailableSubtitle =>
      'Использовать встроенный системный синтез речи';

  @override
  String ttsServicesPageSystemTtsUnavailableSubtitle(String error) {
    return 'Недоступно: $error';
  }

  @override
  String get ttsServicesPageSystemTtsUnavailableNotInitialized =>
      'не инициализировано';

  @override
  String get ttsServicesPageTestSpeechText =>
      'Здравствуйте! Это проверка синтеза речи.';

  @override
  String get ttsServicesPageConfigureTooltip => 'Настроить';

  @override
  String get ttsServicesPageTestVoiceTooltip => 'Проверить голос';

  @override
  String get ttsServicesPageStopTooltip => 'Остановить';

  @override
  String get ttsServicesPageDeleteTooltip => 'Удалить';

  @override
  String get ttsServicesPageSystemTtsSettingsTitle =>
      'Настройки системного синтеза речи';

  @override
  String get ttsServicesPageEngineLabel => 'Движок';

  @override
  String get ttsServicesPageAutoLabel => 'Авто';

  @override
  String get ttsServicesPageLanguageLabel => 'Язык';

  @override
  String get ttsServicesPageSpeechRateLabel => 'Темп речи';

  @override
  String get ttsServicesPagePitchLabel => 'Высота голоса';

  @override
  String get ttsServicesPageSettingsSavedMessage => 'Настройки сохранены.';

  @override
  String get ttsServicesPageDoneButton => 'Готово';

  @override
  String get ttsServicesPageNetworkSectionTitle => 'Облачный синтез речи';

  @override
  String get ttsServicesPageNoNetworkServices => 'Нет сервисов синтеза речи.';

  @override
  String get ttsServicesDialogAddTitle => 'Добавить сервис синтеза речи';

  @override
  String get ttsServicesDialogEditTitle => 'Изменить сервис синтеза речи';

  @override
  String get ttsServicesDialogProviderType => 'Провайдер';

  @override
  String get ttsServicesDialogCancelButton => 'Отмена';

  @override
  String get ttsServicesDialogAddButton => 'Добавить';

  @override
  String get ttsServicesDialogSaveButton => 'Сохранить';

  @override
  String get ttsServicesFieldNameLabel => 'Имя';

  @override
  String get ttsServicesFieldApiKeyLabel => 'API-ключ';

  @override
  String get ttsServicesFieldBaseUrlLabel => 'Базовый URL API';

  @override
  String get ttsServicesFieldModelLabel => 'Модель';

  @override
  String get ttsServicesFieldVoiceLabel => 'Голос';

  @override
  String get ttsServicesFieldVoiceIdLabel => 'ID голоса';

  @override
  String get ttsServicesFieldEmotionLabel => 'Эмоция';

  @override
  String get ttsServicesFieldSpeedLabel => 'Скорость';

  @override
  String get ttsServicesFieldLanguageTypeLabel => 'Тип языка';

  @override
  String get ttsServicesFieldLanguageLabel => 'Язык';

  @override
  String get ttsServicesFieldWorkspaceIdLabel => 'ID рабочего пространства';

  @override
  String get ttsServicesFieldRegionLabel => 'Регион';

  @override
  String get ttsServicesFieldFormatLabel => 'Формат аудио';

  @override
  String get ttsServicesFieldOutputFormatLabel => 'Формат вывода';

  @override
  String get ttsServicesFieldSampleRateLabel => 'Частота дискретизации';

  @override
  String get ttsServicesFieldVolumeLabel => 'Громкость';

  @override
  String get ttsServicesFieldPitchLabel => 'Высота голоса';

  @override
  String get ttsServicesFieldLanguageBoostLabel => 'Приоритетный язык';

  @override
  String get ttsServicesFieldBitrateLabel => 'Битрейт';

  @override
  String get ttsServicesFieldChannelLabel => 'Каналы';

  @override
  String get ttsServicesFieldSubtitlesLabel => 'Создавать субтитры';

  @override
  String get ttsServicesFieldPronunciationDictionaryLabel =>
      'Словарь произношения (по одной записи в строке)';

  @override
  String get ttsServicesFieldInstructionLabel => 'Описание стиля и голоса';

  @override
  String get ttsServicesFieldStreamingLabel => 'Потоковый режим';

  @override
  String get ttsServicesFieldOptimizeTextPreviewLabel =>
      'Оптимизировать предпросмотр текста';

  @override
  String get ttsServicesFieldReferenceAudioLabel =>
      'Образец аудио (data URI WAV/MP3)';

  @override
  String get ttsServicesFieldChooseReferenceAudioButton =>
      'Выбрать образец аудио';

  @override
  String get ttsServicesFieldTemperatureLabel => 'Температура';

  @override
  String get ttsServicesFieldTopPLabel => 'Top P';

  @override
  String get ttsServicesFieldLatencyLabel => 'Задержка';

  @override
  String get ttsServicesEmotionAutoLabel => 'Подбирать автоматически';

  @override
  String get ttsServicesValidationApiKeyRequired =>
      'Необходимо указать API-ключ';

  @override
  String get ttsServicesValidationReferenceIdRequired =>
      'Необходимо указать ID голоса или образца';

  @override
  String get ttsServicesValidationInstructionRequired =>
      'Необходимо описание голоса';

  @override
  String ttsServicesValidationSampleRate(String format, String rates) {
    return 'Для $format требуется частота $rates Гц.';
  }

  @override
  String get ttsServicesViewDetailsButton => 'Подробнее';

  @override
  String get ttsServicesDialogErrorTitle => 'Сведения об ошибке';

  @override
  String get ttsServicesCloseButton => 'Закрыть';

  @override
  String get ttsSettingsPageTitle => 'Настройки синтеза речи';

  @override
  String get ttsSettingsPlaybackSection => 'Воспроизведение';

  @override
  String get ttsSettingsAutoPlayTitle =>
      'Автоматически озвучивать ответы ассистента';

  @override
  String get ttsSettingsAutoPlayDescription =>
      'Запускать озвучивание после завершения ответа ассистента.';

  @override
  String get ttsSettingsCacheReplayTitle =>
      'Повторно использовать готовое аудио';

  @override
  String get ttsSettingsCacheReplayDescription =>
      'При повторном воспроизведении использовать уже созданное облачное аудио без нового запроса к сервису.';

  @override
  String get ttsSettingsTextSelectionSection => 'Выбор текста';

  @override
  String get ttsSettingsTextSelectionFallbackDescription =>
      'Если подходящий текст не найден, озвучивается весь ответ.';

  @override
  String get ttsSettingsTextSelectionFullTextTitle => 'Весь текст';

  @override
  String get ttsSettingsTextSelectionFullTextDescription =>
      'Озвучивать полный ответ ассистента.';

  @override
  String get ttsSettingsTextSelectionQuotedOnlyTitle =>
      'Только текст в кавычках';

  @override
  String get ttsSettingsTextSelectionQuotedOnlyDescription =>
      'Озвучивать текст внутри “”, ‘’, \"\", \'\', 「」 или 『』.';

  @override
  String get ttsSettingsTextSelectionOutsideParenthesesTitle =>
      'Текст вне скобок';

  @override
  String get ttsSettingsTextSelectionOutsideParenthesesDescription =>
      'Пропускать текст внутри () и （）.';

  @override
  String get ttsSettingsTextSelectionItalicOnlyTitle => 'Только курсив';

  @override
  String get ttsSettingsTextSelectionItalicOnlyDescription =>
      'Озвучивать текст, выделенный курсивом в Markdown или HTML.';

  @override
  String get ttsSettingsTextSelectionNonItalicTitle =>
      'Только текст без курсива';

  @override
  String get ttsSettingsTextSelectionNonItalicDescription =>
      'Пропускать текст, выделенный курсивом в Markdown или HTML.';

  @override
  String get ttsFloatingPlayerLabel => 'Проигрыватель озвучивания';

  @override
  String get ttsFloatingPauseTooltip => 'Пауза';

  @override
  String get ttsFloatingResumeTooltip => 'Продолжить';

  @override
  String get ttsFloatingReplayTooltip => 'Воспроизвести снова';

  @override
  String get ttsFloatingRewind15Tooltip => 'Назад на 15 секунд';

  @override
  String get ttsFloatingForward15Tooltip => 'Вперёд на 15 секунд';

  @override
  String get ttsFloatingSpeedTooltip => 'Скорость воспроизведения';

  @override
  String get ttsFloatingCloseTooltip => 'Закрыть проигрыватель';

  @override
  String get ttsFloatingExpandTooltip =>
      'Развернуть управление воспроизведением';

  @override
  String get ttsFloatingCollapseTooltip =>
      'Свернуть управление воспроизведением';

  @override
  String get ttsFloatingSaveTooltip => 'Сохранить аудио';

  @override
  String get ttsSaveDialogTitle => 'Сохранить озвучивание';

  @override
  String get ttsSaveSuccess => 'Аудио сохранено.';

  @override
  String get ttsSaveNothing => 'Нет аудио для сохранения.';

  @override
  String ttsSaveFailed(String message) {
    return 'Не удалось сохранить аудио: $message';
  }

  @override
  String imageViewerPageShareFailedOpenFile(String message) {
    return 'Не удалось поделиться, выполнена попытка открыть файл: $message';
  }

  @override
  String imageViewerPageShareFailed(String error) {
    return 'Не удалось поделиться: $error';
  }

  @override
  String get imageViewerPageShareButton => 'Поделиться изображением';

  @override
  String get imageViewerPageCloseButton => 'Закрыть предпросмотр';

  @override
  String get imageViewerPageSaveButton => 'Сохранить изображение';

  @override
  String get imageViewerPageCopyButton => 'Скопировать изображение';

  @override
  String get imageViewerPagePreviousButton => 'Предыдущее изображение';

  @override
  String get imageViewerPageNextButton => 'Следующее изображение';

  @override
  String get imageViewerPageZoomInButton => 'Увеличить';

  @override
  String get imageViewerPageZoomOutButton => 'Уменьшить';

  @override
  String get imageViewerPageResetZoomButton => 'Сбросить масштаб';

  @override
  String get imageViewerPageFlipHorizontalButton => 'Отразить по горизонтали';

  @override
  String get imageViewerPageFlipVerticalButton => 'Отразить по вертикали';

  @override
  String get imageViewerPageRotateLeftButton => 'Повернуть влево';

  @override
  String get imageViewerPageRotateRightButton => 'Повернуть вправо';

  @override
  String imageViewerPageCounter(int index, int total) {
    return '$index/$total';
  }

  @override
  String imageViewerPageImageLabel(int index, int total) {
    return 'Изображение $index из $total';
  }

  @override
  String get imageViewerPageImageLoadFailed =>
      'Не удалось загрузить изображение';

  @override
  String get imageViewerPageSaveSuccess => 'Сохранено в галерею';

  @override
  String imageViewerPageSaveFailed(String error) {
    return 'Не удалось сохранить: $error';
  }

  @override
  String get settingsShare => 'Moru — ИИ-ассистент с открытым исходным кодом';

  @override
  String get searchProviderBingLocalDescription =>
      'Получает результаты со страниц Bing. API-ключ не нужен; работа может быть нестабильной.';

  @override
  String get searchProviderDuckDuckGoDescription =>
      'Поиск DuckDuckGo через DDGS с упором на конфиденциальность. API-ключ не нужен; доступен выбор региона.';

  @override
  String get searchProviderBraveDescription =>
      'Независимый поисковик Brave с упором на конфиденциальность, без отслеживания и профилирования.';

  @override
  String get searchProviderExaDescription =>
      'Нейропоиск с пониманием смысла. Подходит для исследований и поиска конкретных материалов.';

  @override
  String get searchProviderLinkUpDescription =>
      'API поиска с ответами и источниками. Предоставляет результаты и сводки, созданные ИИ.';

  @override
  String get searchProviderMetasoDescription =>
      'Китайский поиск Metaso. Оптимизирован для китайскоязычного содержимого и использует ИИ.';

  @override
  String get searchProviderSearXNGDescription =>
      'Метапоисковик с защитой конфиденциальности. Нужен собственный экземпляр; без отслеживания.';

  @override
  String get searchProviderTavilyDescription =>
      'Поисковый API, оптимизированный для языковых моделей. Предоставляет качественные и релевантные результаты.';

  @override
  String get searchProviderZhipuDescription =>
      'Китайский ИИ-поиск Zhipu AI. Оптимизирован для китайскоязычных материалов и запросов.';

  @override
  String get searchProviderOllamaDescription =>
      'API веб-поиска Ollama. Дополняет ответы моделей актуальной информацией.';

  @override
  String get searchProviderJinaDescription =>
      'Основа для ИИ-поиска: эмбеддинги, переранжирование, чтение страниц, глубокий поиск и малые языковые модели. Поддерживает разные языки и типы данных.';

  @override
  String get searchServiceNameBingLocal => 'Bing (локальный)';

  @override
  String get searchServiceNameDuckDuckGo => 'DuckDuckGo';

  @override
  String get searchServiceNameTavily => 'Tavily';

  @override
  String get searchServiceNameExa => 'Exa';

  @override
  String get searchServiceNameZhipu => 'Zhipu AI';

  @override
  String get searchServiceNameSearXNG => 'SearXNG';

  @override
  String get searchServiceNameLinkUp => 'LinkUp';

  @override
  String get searchServiceNameBrave => 'Brave Search';

  @override
  String get searchServiceNameMetaso => 'Metaso';

  @override
  String get searchServiceNameOllama => 'Ollama';

  @override
  String get searchServiceNameJina => 'Jina';

  @override
  String get searchServiceNamePerplexity => 'Perplexity';

  @override
  String get searchProviderPerplexityDescription =>
      'Поисковый API Perplexity. Ранжированные веб-результаты с фильтрами по регионам и доменам.';

  @override
  String get searchServiceNameBocha => 'Bocha';

  @override
  String get searchProviderBochaDescription =>
      'API веб-поиска Bocha. Точные веб-результаты с необязательными сводками.';

  @override
  String get searchServiceNameDoubao => 'Doubao';

  @override
  String get searchProviderDoubaoDescription =>
      'API веб-поиска Doubao от Volcano Engine.';

  @override
  String get searchServiceNameSerper => 'Serper';

  @override
  String get searchProviderSerperDescription =>
      'API поиска Google от Serper. Быстрые результаты с необязательными фильтрами по стране, языку, времени и странице.';

  @override
  String get searchServiceNameQuerit => 'Querit';

  @override
  String get searchProviderQueritDescription =>
      'Поисковый API Querit для приложений с языковыми моделями. Актуальные результаты с фильтрами по сайту, времени, стране и языку.';

  @override
  String get searchServiceNameGrok => 'Grok';

  @override
  String get searchProviderGrokDescription =>
      'Поиск Grok через xAI Responses API. Использует веб-поиск и поиск в X, возвращая ссылки на источники.';

  @override
  String get searchServiceNameStepFun => 'StepFun';

  @override
  String get searchProviderStepFunDescription =>
      'Веб-поиск StepFun через POST /v1/search.';

  @override
  String get searchServiceNameFirecrawl => 'Firecrawl';

  @override
  String get searchProviderFirecrawlDescription =>
      'Поисковый API Firecrawl v2. API-ключ необязателен. Извлечение содержимого страниц здесь не поддерживается.';

  @override
  String get searchServiceNameTinyFish => 'TinyFish';

  @override
  String get searchProviderTinyFishDescription =>
      'Поисковый API TinyFish с фильтрами по региону и языку. Требуется API-ключ. Получение и извлечение содержимого страниц здесь не поддерживается.';

  @override
  String get searchServiceNameAnySearch => 'AnySearch';

  @override
  String get searchProviderAnySearchDescription =>
      'Единый поиск для ИИ-агентов с автоматическим выбором веб-источников и специализированных данных. API-ключ необязателен.';

  @override
  String get searchServiceNameParallel => 'Parallel';

  @override
  String get searchProviderParallelDescription =>
      'Поисковый API Parallel. Возвращает веб-фрагменты для языковых моделей в режимах turbo, fast, basic и advanced.';

  @override
  String get searchServicesDialogSearchMode => 'Режим поиска';

  @override
  String get searchServiceNameYou => 'You.com';

  @override
  String get searchProviderYouDescription =>
      'Поисковый API You.com. Возвращает веб-результаты и новости с выделенными отрывками или краткими описаниями.';

  @override
  String get searchServicesDialogContentMode => 'Режим содержимого';

  @override
  String get searchServicesDialogHighlights => 'Выделенные отрывки';

  @override
  String get searchServicesDialogSnippets => 'Краткие описания';

  @override
  String get searchServicesDialogWebSearch => 'Веб-поиск';

  @override
  String get searchServicesDialogLlmContext => 'Контекст для модели';

  @override
  String get searchServicesDialogMaximumTokens => 'Максимум токенов';

  @override
  String get searchServicesDialogMaximumTokensInvalid =>
      'Максимальное число токенов должно быть от 1024 до 32768.';

  @override
  String get searchServiceNameKelivo => 'Moru';

  @override
  String get searchServicesDialogCountryOptional =>
      'Страна/регион (необязательно)';

  @override
  String get searchServicesDialogLanguageOptional => 'Язык (необязательно)';

  @override
  String get searchServicesDialogTimeFilterOptional =>
      'Фильтр по времени (необязательно)';

  @override
  String get searchServicesDialogPageOptional => 'Страница (необязательно)';

  @override
  String get searchServicesDialogPageInvalid =>
      'Номер страницы должен быть положительным целым числом.';

  @override
  String get searchServicesDialogSitesIncludeOptional =>
      'Включить сайты (необязательно)';

  @override
  String get searchServicesDialogSitesExcludeOptional =>
      'Исключить сайты (необязательно)';

  @override
  String get searchServicesDialogTimeRangeOptional => 'Период (необязательно)';

  @override
  String get searchServicesDialogCountriesOptional => 'Страны (необязательно)';

  @override
  String get searchServicesDialogLanguagesOptional => 'Языки (необязательно)';

  @override
  String get searchServicesDialogSitesHint => 'example.com, docs.example.com';

  @override
  String get searchServicesDialogTimeRangeHint => 'd7';

  @override
  String get searchServicesDialogCountriesHint => 'united states, japan';

  @override
  String get searchServicesDialogLanguagesHint => 'english, japanese';

  @override
  String get generationInterrupted => 'Генерация прервана';

  @override
  String get titleForLocale => 'Новый чат';

  @override
  String get temporaryChatTitle => 'Временный чат';

  @override
  String get temporaryChatEmptyMessage =>
      'Временные чаты не отображаются в истории и полностью удаляются после выхода.';

  @override
  String get temporaryChatToggleTooltip => 'Переключить временный чат';

  @override
  String get quickPhraseBackTooltip => 'Назад';

  @override
  String get quickPhraseGlobalTitle => 'Быстрая фраза';

  @override
  String get quickPhraseAssistantTitle => 'Быстрые фразы ассистента';

  @override
  String get quickPhraseAddTooltip => 'Добавить быструю фразу';

  @override
  String get quickPhraseEmptyMessage => 'Быстрых фраз пока нет';

  @override
  String get quickPhraseAddTitle => 'Добавить быструю фразу';

  @override
  String get quickPhraseEditTitle => 'Изменить быструю фразу';

  @override
  String get quickPhraseTitleLabel => 'Заголовок';

  @override
  String get quickPhraseContentLabel => 'Содержимое';

  @override
  String get quickPhraseCancelButton => 'Отмена';

  @override
  String get quickPhraseSaveButton => 'Сохранить';

  @override
  String get instructionInjectionTitle => 'Добавление инструкций';

  @override
  String get instructionInjectionBackTooltip => 'Назад';

  @override
  String get instructionInjectionAddTooltip => 'Добавить инструкцию';

  @override
  String get instructionInjectionImportTooltip => 'Импортировать из файлов';

  @override
  String get instructionInjectionEmptyMessage => 'Карточек инструкций пока нет';

  @override
  String get instructionInjectionDefaultTitle => 'Режим обучения';

  @override
  String get instructionInjectionAddTitle => 'Добавить инструкцию для чата';

  @override
  String get instructionInjectionEditTitle => 'Изменить добавляемую инструкцию';

  @override
  String get instructionInjectionNameLabel => 'Имя';

  @override
  String get instructionInjectionPromptLabel => 'Промпт';

  @override
  String get instructionInjectionUngroupedGroup => 'Без группы';

  @override
  String get instructionInjectionGroupLabel => 'Группа';

  @override
  String get instructionInjectionGroupHint => 'Необязательно';

  @override
  String instructionInjectionImportSuccess(int count) {
    return 'Импортировано инструкций: $count';
  }

  @override
  String get instructionInjectionSheetSubtitle =>
      'Выберите промпт, который будет применён перед общением';

  @override
  String get mcpJsonEditButtonTooltip => 'Изменить JSON';

  @override
  String get mcpJsonEditTitle => 'Изменить JSON';

  @override
  String get mcpJsonEditParseFailed => 'Не удалось разобрать JSON';

  @override
  String get mcpJsonEditSavedApplied => 'Сохранено и применено';

  @override
  String get mcpTimeoutSettingsTooltip =>
      'Настроить тайм-аут вызова инструмента';

  @override
  String get mcpTimeoutDialogTitle => 'Тайм-аут вызова инструмента';

  @override
  String get mcpTimeoutSecondsLabel => 'Тайм-аут вызова инструмента (секунды)';

  @override
  String get mcpTimeoutInvalid => 'Введите положительное число секунд';

  @override
  String get quickPhraseEditButton => 'Изменить';

  @override
  String get quickPhraseDeleteButton => 'Удалить';

  @override
  String get quickPhraseMenuTitle => 'Быстрая фраза';

  @override
  String get chatInputBarQuickPhraseTooltip => 'Быстрая фраза';

  @override
  String get assistantEditQuickPhraseDescription =>
      'Управляйте быстрыми фразами этого ассистента. Нажмите кнопку ниже, чтобы добавить фразы.';

  @override
  String get assistantEditManageQuickPhraseButton =>
      'Управление быстрыми фразами';

  @override
  String get assistantEditPageMemoryTab => 'Память';

  @override
  String get assistantEditLocalToolTimeInfoTitle => 'Дата и время';

  @override
  String get assistantEditLocalToolTimeInfoSubtitle =>
      'Читать дату, день недели, время, часовой пояс, смещение UTC и метку времени устройства.';

  @override
  String get assistantEditLocalToolClipboardTitle => 'Буфер обмена';

  @override
  String get assistantEditLocalToolClipboardSubtitle =>
      'Читать или записывать обычный текст в буфер обмена устройства при явной необходимости.';

  @override
  String get assistantEditLocalToolTextToSpeechTitle => 'Озвучивание текста';

  @override
  String get assistantEditLocalToolTextToSpeechSubtitle =>
      'Позволить ассистенту читать текст вслух с помощью настроенного синтеза речи.';

  @override
  String get assistantEditLocalToolAskUserTitle => 'Спросить пользователя';

  @override
  String get assistantEditLocalToolAskUserSubtitle =>
      'Позволить ассистенту задавать короткие вопросы и продолжать после вашего ответа.';

  @override
  String get assistantEditLocalToolCalculateTitle => 'Калькулятор';

  @override
  String get assistantEditLocalToolCalculateSubtitle =>
      'Вычислять математические выражения: +, −, *, /, степени, sqrt, sin, cos и другие функции.';

  @override
  String get assistantEditLocalToolScreenTimeTitle => 'Экранное время';

  @override
  String get assistantEditLocalToolScreenTimeSubtitle =>
      'Получать статистику использования приложений. Требуется разрешение на доступ к статистике использования.';

  @override
  String get chatMessageWidgetScreenTimeTotal => 'Общее экранное время';

  @override
  String get chatMessageWidgetScreenTimePermissionRequired =>
      'Нет разрешения на доступ к статистике использования. Включите его в системных настройках и повторите попытку.';

  @override
  String get assistantEditLocalToolCalendarQueryTitle => 'Чтение календаря';

  @override
  String get assistantEditLocalToolCalendarQuerySubtitle =>
      'Читать события календаря на устройстве. Требуется разрешение на доступ к календарю.';

  @override
  String get assistantEditLocalToolCalendarCreateTitle => 'Создать событие';

  @override
  String get assistantEditLocalToolCalendarCreateSubtitle =>
      'Создавать события календаря с вашим подтверждением. Требуется разрешение на доступ к календарю.';

  @override
  String get assistantEditLocalToolLocationTitle => 'Текущее местоположение';

  @override
  String get assistantEditLocalToolLocationSubtitle =>
      'Однократно получать местоположение устройства. Требуется разрешение на доступ к геопозиции.';

  @override
  String get assistantEditLocalToolWeatherTitle => 'Погода';

  @override
  String get assistantEditLocalToolWeatherSubtitle =>
      'Получать Apple Weather для текущего или указанного места. В результате отображается указание источника WeatherKit.';

  @override
  String get assistantEditLocalToolHealthTitle => 'Сводка здоровья';

  @override
  String get assistantEditLocalToolHealthSubtitle =>
      'Читать сводку активности из Apple Health с сохранением конфиденциальности. Требуется доступ к данным здоровья.';

  @override
  String assistantEditLocalToolHealthSelectedCount(int selected, int total) {
    return 'Выбрано: $selected/$total';
  }

  @override
  String get healthDataSettingsTitle => 'Данные здоровья';

  @override
  String get healthDataSettingsDescription =>
      'Данные HealthKit, доступные текущему ассистенту в обычных диалогах. Переключатели задают, что Moru может запрашивать; фактическим доступом к данным управляет iOS.';

  @override
  String healthDataSettingsBadge(int selected, int total) {
    return 'Включено: $selected/$total';
  }

  @override
  String get healthDataSettingsIosReadTitle => 'Чтение данных здоровья iOS';

  @override
  String get healthDataSettingsIosReadSubtitle =>
      'Устройство поддерживается; объём доступных данных определяет iOS';

  @override
  String get healthDataSettingsOpenSystemSettings =>
      'Открыть системные настройки';

  @override
  String get healthDataSettingsEnableAll => 'Включить всё';

  @override
  String get healthDataSettingsDisableAll => 'Отключить всё';

  @override
  String get healthDataSettingsCategoryActivity => 'Активность';

  @override
  String get healthDataSettingsCategoryRest => 'Отдых';

  @override
  String get healthDataSettingsCategoryHeart => 'Сердце';

  @override
  String get healthDataSettingsCategoryBody => 'Тело';

  @override
  String get healthDataSettingsTypeStepsTitle => 'Шаги';

  @override
  String get healthDataSettingsTypeStepsSubtitle => 'Сводка пройденных шагов';

  @override
  String get healthDataSettingsTypeDaylightTitle => 'Дневной свет';

  @override
  String get healthDataSettingsTypeDaylightSubtitle =>
      'Время на улице при дневном свете';

  @override
  String get healthDataSettingsTypeActiveEnergyTitle => 'Энергия';

  @override
  String get healthDataSettingsTypeActiveEnergySubtitle =>
      'Активно потраченная энергия';

  @override
  String get healthDataSettingsTypeExerciseMinutesTitle => 'Упражнения';

  @override
  String get healthDataSettingsTypeExerciseMinutesSubtitle =>
      'Минуты упражнений Apple';

  @override
  String get healthDataSettingsTypeStandTimeTitle => 'Стояние';

  @override
  String get healthDataSettingsTypeStandTimeSubtitle => 'Время стояния';

  @override
  String get healthDataSettingsTypeDistanceTitle => 'Расстояние';

  @override
  String get healthDataSettingsTypeDistanceSubtitle =>
      'Расстояние ходьбы и бега';

  @override
  String get healthDataSettingsTypeWorkoutsTitle => 'Тренировки';

  @override
  String get healthDataSettingsTypeWorkoutsSubtitle =>
      'Записи тренировок: тип, длительность, расстояние и энергия';

  @override
  String get healthDataSettingsTypeSleepTitle => 'Сон';

  @override
  String get healthDataSettingsTypeSleepSubtitle =>
      'За последние 24 часа: сон, время в постели, периоды бодрствования и фазы сна';

  @override
  String get healthDataSettingsTypeMindfulnessTitle => 'Покой';

  @override
  String get healthDataSettingsTypeMindfulnessSubtitle =>
      'Периоды осознанности или отдыха';

  @override
  String get healthDataSettingsTypeHeartRateTitle => 'Пульс';

  @override
  String get healthDataSettingsTypeHeartRateSubtitle =>
      'Последнее измерение пульса';

  @override
  String get healthDataSettingsTypeRestingHeartRateTitle => 'Пульс в покое';

  @override
  String get healthDataSettingsTypeRestingHeartRateSubtitle =>
      'Измерение пульса в покое';

  @override
  String get healthDataSettingsTypeBloodOxygenTitle => 'Кислород в крови';

  @override
  String get healthDataSettingsTypeBloodOxygenSubtitle =>
      'Насыщение крови кислородом';

  @override
  String get healthDataSettingsTypeDietaryEnergyTitle => 'Потреблённая энергия';

  @override
  String get healthDataSettingsTypeDietaryEnergySubtitle =>
      'Запись о потреблённых калориях';

  @override
  String get healthDataSettingsTypeWaterTitle => 'Вода';

  @override
  String get healthDataSettingsTypeWaterSubtitle => 'Запись о потреблении воды';

  @override
  String get healthDataSettingsTypeWeightTitle => 'Вес';

  @override
  String get healthDataSettingsTypeWeightSubtitle => 'Измерение массы тела';

  @override
  String get healthDataSettingsTypeBmiTitle => 'ИМТ';

  @override
  String get healthDataSettingsTypeBmiSubtitle => 'Индекс массы тела';

  @override
  String get healthDataSettingsTypeBloodGlucoseTitle => 'Глюкоза в крови';

  @override
  String get healthDataSettingsTypeBloodGlucoseSubtitle =>
      'Измерение глюкозы в крови';

  @override
  String get assistantEditLocalToolRemindersQueryTitle => 'Чтение напоминаний';

  @override
  String get assistantEditLocalToolRemindersQuerySubtitle =>
      'Читать напоминания на устройстве. Требуется полный доступ к напоминаниям.';

  @override
  String get assistantEditLocalToolRemindersCreateTitle =>
      'Создать напоминание';

  @override
  String get assistantEditLocalToolRemindersCreateSubtitle =>
      'Создавать напоминания с вашим подтверждением. Требуется полный доступ к напоминаниям.';

  @override
  String get assistantEditLocalToolRemindersCompleteTitle =>
      'Завершить напоминание';

  @override
  String get assistantEditLocalToolRemindersCompleteSubtitle =>
      'Отмечать напоминания выполненными с вашим подтверждением. Требуется полный доступ к напоминаниям.';

  @override
  String get assistantEditMemorySwitchDescription =>
      'Позволить ассистенту создавать и использовать записи памяти между чатами.';

  @override
  String get assistantEditRecentChatsSwitchTitle =>
      'Сведения о последних чатах';

  @override
  String get assistantEditRecentChatsSwitchDescription =>
      'Добавлять заголовки последних диалогов для улучшения контекста.';

  @override
  String get assistantEditAddMemoryButton => 'Добавить запись в память';

  @override
  String get assistantEditMemoryEmpty => 'Записей в памяти пока нет';

  @override
  String get assistantEditMemoryDialogTitle => 'Память';

  @override
  String get assistantEditMemoryDialogHint => 'Введите содержимое записи';

  @override
  String get assistantEditAddQuickPhraseButton => 'Добавить быструю фразу';

  @override
  String get multiKeyPageDeleteSnackbarDeletedOne => 'Удалён 1 ключ';

  @override
  String get multiKeyPageUndo => 'Отменить';

  @override
  String get multiKeyPageUndoRestored => 'Восстановлено';

  @override
  String get multiKeyPageDeleteErrorsTooltip => 'Удалить неисправные';

  @override
  String get multiKeyPageDeleteErrorsConfirmTitle =>
      'Удалить все ключи с ошибками?';

  @override
  String get multiKeyPageDeleteErrorsConfirmContent =>
      'Будут удалены все ключи, помеченные как неисправные.';

  @override
  String multiKeyPageDeletedErrorsSnackbar(int n) {
    return 'Удалено ключей с ошибками: $n';
  }

  @override
  String get providerDetailPageProviderTypeTitle => 'Тип провайдера';

  @override
  String get displaySettingsPageChatItemDisplayTitle => 'Отображение сообщений';

  @override
  String get displaySettingsPageRenderingSettingsTitle =>
      'Настройки отображения содержимого';

  @override
  String get displaySettingsPageBehaviorStartupTitle => 'Поведение и запуск';

  @override
  String get displaySettingsPageHapticsSettingsTitle => 'Виброотклик';

  @override
  String get assistantSettingsNoPromptPlaceholder => 'Промпт пока не задан';

  @override
  String get providersPageMultiSelectTooltip => 'Множественный выбор';

  @override
  String get providersPageDeleteSelectedConfirmContent =>
      'Удалить выбранных провайдеров? Отменить удаление нельзя.';

  @override
  String get providersPageDeleteSelectedSnackbar =>
      'Выбранные провайдеры удалены';

  @override
  String providersPageExportSelectedTitle(int count) {
    return 'Экспорт провайдеров: $count';
  }

  @override
  String get providersPageExportCopyButton => 'Копировать';

  @override
  String get providersPageExportShareButton => 'Поделиться';

  @override
  String get providersPageExportCopiedSnackbar => 'Код экспорта скопирован';

  @override
  String get providersPageDeleteAction => 'Удалить';

  @override
  String get providersPageExportAction => 'Экспорт';

  @override
  String get assistantEditPresetTitle => 'Заготовка диалога';

  @override
  String get assistantEditPresetAddUser => 'Добавить сообщение пользователя';

  @override
  String get assistantEditPresetAddAssistant => 'Добавить сообщение ассистента';

  @override
  String get assistantEditPresetInputHintUser =>
      'Введите сообщение пользователя…';

  @override
  String get assistantEditPresetInputHintAssistant =>
      'Введите сообщение ассистента…';

  @override
  String get assistantEditPresetEmpty => 'Заготовленных сообщений пока нет';

  @override
  String get assistantEditPresetEditDialogTitle =>
      'Изменить заготовленное сообщение';

  @override
  String get assistantEditPresetRoleUser => 'Пользователь';

  @override
  String get assistantEditPresetRoleAssistant => 'Ассистент';

  @override
  String get desktopTtsPleaseAddProvider =>
      'Сначала добавьте провайдера синтеза речи';

  @override
  String get settingsPageNetworkProxy => 'Сетевой прокси';

  @override
  String get networkProxyEnableLabel => 'Включить прокси';

  @override
  String get networkProxySettingsHeader => 'Настройки прокси';

  @override
  String get networkProxyType => 'Тип прокси';

  @override
  String get networkProxyTypeHttp => 'HTTP';

  @override
  String get networkProxyTypeHttps => 'HTTPS';

  @override
  String get networkProxyTypeSocks5 => 'SOCKS5';

  @override
  String get networkProxyServerHost => 'Сервер';

  @override
  String get networkProxyPort => 'Порт';

  @override
  String get networkProxyUsername => 'Имя пользователя';

  @override
  String get networkProxyPassword => 'Пароль';

  @override
  String get networkProxyBypassLabel => 'Исключения прокси';

  @override
  String get networkProxyBypassHint =>
      'Хосты и CIDR через запятую, например localhost,127.0.0.1,192.168.0.0/16,*.local';

  @override
  String get networkProxyOptionalHint => 'Необязательно';

  @override
  String get networkProxyTestHeader => 'Проверка подключения';

  @override
  String get networkProxyTestUrlHint => 'URL для проверки';

  @override
  String get networkProxyTestButton => 'Проверить';

  @override
  String get networkProxyTesting => 'Проверка…';

  @override
  String get networkProxyTestSuccess => 'Подключение установлено';

  @override
  String networkProxyTestFailed(String error) {
    return 'Проверка не удалась: $error';
  }

  @override
  String get networkProxyNoUrl => 'Введите URL';

  @override
  String get networkProxyPriorityNote =>
      'Если включены и общий прокси, и прокси провайдера, используется прокси провайдера.';

  @override
  String get settingsPageAutoRetry => 'Автоповтор запросов';

  @override
  String get autoRetryEnableLabel => 'Включить автоповтор';

  @override
  String get autoRetryMaxRetries => 'Максимум повторов';

  @override
  String get autoRetryInitialDelay => 'Начальная задержка (мс)';

  @override
  String get autoRetryMultiplier => 'Множитель задержки';

  @override
  String get autoRetryMaxDelay => 'Максимальная задержка (мс)';

  @override
  String get autoRetryJitter => 'Случайный разброс';

  @override
  String get autoRetryJitterSubtitle =>
      'Изменять каждую задержку случайным образом в пределах ±20%';

  @override
  String get autoRetryOnNetworkError => 'Повторять при сетевых ошибках';

  @override
  String get autoRetryStatusCodes => 'Коды состояния для повтора';

  @override
  String get autoRetryKeywords => 'Ключевые слова для повтора';

  @override
  String get autoRetryStopKeywords => 'Ключевые слова для остановки';

  @override
  String get autoRetryAddHint => 'Добавить';

  @override
  String get autoRetryRestoreDefaults => 'Восстановить значения по умолчанию';

  @override
  String get autoRetryFooter =>
      'Автоповтор выполняется, только если модель ещё не начала выдавать ответ.';

  @override
  String autoRetryCountdown(int seconds, int attempt, int maxRetries) {
    return 'Повтор через $seconds с ($attempt/$maxRetries)';
  }

  @override
  String get desktopShowProviderInModelCapsule =>
      'Показывать провайдера в плашке модели';

  @override
  String get messageWebViewOpenInBrowser => 'Открыть в браузере';

  @override
  String get messageWebViewConsoleLogs => 'Журнал консоли';

  @override
  String get messageWebViewNoConsoleMessages => 'В консоли нет сообщений';

  @override
  String get messageWebViewRefreshTooltip => 'Обновить';

  @override
  String get messageWebViewForwardTooltip => 'Вперёд';

  @override
  String get chatInputBarOcrTooltip => 'Распознать текст на изображении';

  @override
  String get providerDetailPageMultiSelectButton => 'Множественный выбор';

  @override
  String get providerDetailPageBatchDetectButton => 'Проверить';

  @override
  String get providerDetailPageBatchDetecting => 'Проверка…';

  @override
  String get providerDetailPageBatchDetectStart => 'Начать проверку';

  @override
  String get providerDetailPageDetectSuccess => 'Проверка успешна';

  @override
  String get providerDetailPageDetectFailed => 'Проверка не удалась';

  @override
  String get providerDetailPageDeleteSelectedModelsButton => 'Удалить';

  @override
  String get providerDetailPageDeleteSelectedModelsTooltip =>
      'Удалить выбранные модели';

  @override
  String providerDetailPageDeleteSelectedModelsConfirm(int count) {
    return 'Удалить выбранные модели ($count)? Отменить удаление нельзя.';
  }

  @override
  String get providerDetailPageDeleteFailedDetectedModelsButton =>
      'Удалить недоступные';

  @override
  String get providerDetailPageDeleteFailedDetectedModelsTooltip =>
      'Удалить модели, не прошедшие проверку';

  @override
  String providerDetailPageDeleteFailedDetectedModelsConfirm(int count) {
    return 'Удалить модели, не прошедшие проверку ($count)? Отменить удаление нельзя.';
  }

  @override
  String providerDetailPageSelectedModelsDeletedSnackbar(int count) {
    return 'Удалено моделей: $count';
  }

  @override
  String get providerDetailPageDeleteAllModelsTooltip => 'Удалить все модели';

  @override
  String get providerDetailPageDeleteAllModelsWarning =>
      'Это действие нельзя отменить.';

  @override
  String get requestLogSettingTitle => 'Журнал запросов';

  @override
  String get requestLogSettingSubtitle =>
      'Записывать запросы и ответы в logs/logs.txt (новый файл каждый день).';

  @override
  String get flutterLogSettingTitle => 'Журнал Flutter';

  @override
  String get flutterLogSettingSubtitle =>
      'Записывать ошибки Flutter и вывод print в logs/flutter_logs.txt (новый файл каждый день).';

  @override
  String get contextLogSettingTitle => 'Журнал контекста';

  @override
  String get contextLogSettingSubtitle =>
      'Записывать точное содержимое сообщений, отправленных модели, в logs/context_logs.txt (новый файл каждый день).';

  @override
  String get contextLogViewerTitle => 'Контекст';

  @override
  String contextLogSnapshotMessages(int count) {
    return 'Сообщений: $count';
  }

  @override
  String contextLogSnapshotTokens(int count) {
    return 'Токенов: $count';
  }

  @override
  String get contextLogSourceSystemPrompt => 'Системный промпт';

  @override
  String get contextLogSourceMemoryRules => 'Правила памяти';

  @override
  String get contextLogSourceSearchPrompt => 'Промпт поиска';

  @override
  String get contextLogSourceInstructionInjection => 'Инструкция';

  @override
  String get contextLogSourceWorldBook => 'Книга мира';

  @override
  String get contextLogSourceMemorySnapshot => 'Снимок памяти';

  @override
  String get contextLogSourceChatHistory => 'История чата';

  @override
  String get contextLogSourceToolCall => 'Вызов инструмента';

  @override
  String get contextLogSourceToolResult => 'Результат инструмента';

  @override
  String get contextLogTokensEstimateHint =>
      'Количество токенов приблизительное; ориентируйтесь на фактический расход, сообщённый моделью.';

  @override
  String contextLogSnapshotsCount(int count) {
    return 'Снимков: $count';
  }

  @override
  String get contextLogSnapshotFallbackTitle => 'Снимок';

  @override
  String get contextLogKindFull => 'Полный снимок';

  @override
  String get contextLogKindUpdate => 'Добавочные изменения';

  @override
  String get contextLogSectionComposition => 'Состав';

  @override
  String get contextLogLoadOlder => 'Загрузить более ранние записи';

  @override
  String get contextLogLoading => 'Загрузка…';

  @override
  String get contextLogAllLoaded => 'Все записи загружены';

  @override
  String get logViewerTitle => 'Журналы запросов';

  @override
  String get logViewerEmpty => 'Записей пока нет';

  @override
  String get logViewerCurrentLog => 'Текущий журнал';

  @override
  String get logViewerExport => 'Экспорт';

  @override
  String get logViewerOpenFolder => 'Открыть папку журналов';

  @override
  String logViewerRequestsCount(int count) {
    return 'Запросов: $count';
  }

  @override
  String get logViewerFieldId => 'ID';

  @override
  String get logViewerFieldMethod => 'Метод';

  @override
  String get logViewerFieldStatus => 'Статус';

  @override
  String get logViewerFieldStarted => 'Начало';

  @override
  String get logViewerFieldEnded => 'Окончание';

  @override
  String get logViewerFieldDuration => 'Длительность';

  @override
  String get logViewerSectionSummary => 'Сводка';

  @override
  String get logViewerSectionParameters => 'Параметры';

  @override
  String get logViewerSectionRequestHeaders => 'Заголовки запроса';

  @override
  String get logViewerSectionRequestBody => 'Тело запроса';

  @override
  String get logViewerSectionResponseHeaders => 'Заголовки ответа';

  @override
  String get logViewerSectionResponseBody => 'Тело ответа';

  @override
  String get logViewerSectionWarnings => 'Предупреждения';

  @override
  String get logViewerErrorTitle => 'Ошибка';

  @override
  String logViewerMoreCount(int count) {
    return 'Ещё $count';
  }

  @override
  String get logViewerSectionAttachments => 'Вложения';

  @override
  String get logViewerPayloadOmitted => 'пропущено';

  @override
  String get logViewerShowMore => 'Показать больше';

  @override
  String get logSettingsTitle => 'Настройки журналов';

  @override
  String get logSettingsSaveOutput => 'Сохранять вывод ответа';

  @override
  String get logSettingsSaveOutputSubtitle =>
      'Записывать каждый фрагмент потока (может замедлять генерацию). Тела HTTP-ошибок сохраняются всегда.';

  @override
  String get logSettingsElidePayloads => 'Пропускать большие данные';

  @override
  String get logSettingsElidePayloadsSubtitle =>
      'Заменять встроенные base64-изображения и файлы заглушками. Уменьшает журналы и ускоряет просмотр.';

  @override
  String get logSettingsAutoDelete => 'Автоудаление';

  @override
  String get logSettingsAutoDeleteSubtitle =>
      'Удалять журналы старше указанного числа дней';

  @override
  String get logSettingsAutoDeleteDisabled => 'Отключено';

  @override
  String logSettingsAutoDeleteDays(int count) {
    return 'Дней: $count';
  }

  @override
  String get logSettingsMaxSize => 'Максимальный размер журналов';

  @override
  String get logSettingsMaxSizeSubtitle =>
      'При превышении удаляются самые старые журналы';

  @override
  String get logSettingsMaxSizeUnlimited => 'Без ограничений';

  @override
  String get assistantEditManageSummariesTitle => 'Управление сводками';

  @override
  String get assistantEditSummaryEmpty => 'Сводок пока нет';

  @override
  String get assistantEditSummaryDialogTitle => 'Изменить сводку';

  @override
  String get assistantEditSummaryDialogHint => 'Введите содержимое сводки';

  @override
  String get assistantEditDeleteSummaryTitle => 'Очистить сводку';

  @override
  String get assistantEditDeleteSummaryContent => 'Очистить эту сводку?';

  @override
  String get homePageProcessingFiles => 'Обработка файлов…';

  @override
  String get settingsPageWorldBook => 'Книга мира';

  @override
  String get settingsPageMemory => 'Память';

  @override
  String get memorySettingsPageTitle => 'Память';

  @override
  String get memorySettingsGlobalSubtitle => 'Режим памяти, модель и промпты';

  @override
  String get memorySettingsModeSection => 'Режим памяти';

  @override
  String get memorySettingsModelSection => 'Модель памяти';

  @override
  String get memorySettingsModelTitle => 'Модель обработки';

  @override
  String get memorySettingsModelUnset => 'Не выбрано';

  @override
  String get memorySettingsModelTip =>
      'После включения автоупорядочивания памяти эта модель часто вызывается в фоне. Лучше выбрать недорогую быструю модель.';

  @override
  String get memorySettingsAboutTitle => 'О памяти';

  @override
  String get memorySettingsAboutSubtitle =>
      'Как работает память и когда она используется';

  @override
  String get memoryAboutQuickstartTitle => 'Начало работы';

  @override
  String get memoryAboutQuickstartBody =>
      '1. Выберите модель обработки: Настройки → Память.\n2. На вкладке памяти ассистента включите долговременную память и автоупорядочивание.\n3. Отправьте несколько сообщений или нажмите «Упорядочить», затем откройте все записи памяти и посмотрите, что сохранено.';

  @override
  String get memoryAboutTypesTitle => 'Типы памяти';

  @override
  String get memoryAboutTypesBody =>
      'Личность: устойчивые сведения о пользователе — обращение, роль, язык и долгосрочные предпочтения. Формулируйте полные утверждения от третьего лица.\n\nРабочие привычки: предпочитаемые инструменты, форматы и порядок проверки результатов.\n\nСтиль общения: желаемые тон, длина ответов и манера речи ассистента.\n\nИнструкции: постоянные правила для ассистента, а не разовые задачи из текущего чата.';

  @override
  String get memoryAboutScopeTitle => 'Общая память и память ассистента';

  @override
  String get memoryAboutScopeBody =>
      'Общая память добавляется в контекст каждого ассистента. Записи конкретного ассистента видны только ему. Общая память подходит для сведений, нужных везде, а память ассистента — для правил и контекста одной роли.';

  @override
  String get memoryAboutInjectionTitle => 'Как память добавляется в контекст';

  @override
  String get memoryAboutInjectionBody =>
      'В начале чата в контекст модели добавляются самые новые записи каждого типа. Если их больше лимита, блок получает отметку mode=\"summary\" и счётчики общего и показанного количества. Остальное доступно через memory_search_profile. Увеличение лимита в Настройки → Память даёт больше контекста, но повышает расход токенов.';

  @override
  String get memoryAboutPipelineTitle => 'Фоновая обработка';

  @override
  String get memoryAboutPipelineBody =>
      'Автоупорядочивание запускается после общения: определяет, что стоит запомнить, извлекает записи, устраняет повторы и объединяет данные, а при необходимости переносит сведения о личности в профиль. Также можно нажать «Упорядочить» на вкладке памяти ассистента. Поэтому модель обработки вызывается часто.';

  @override
  String get memoryAboutCacheTitle => 'Эффективное кэширование';

  @override
  String get memoryAboutCacheBody =>
      'Добавляемый блок памяти сохраняется неизменным, чтобы при отсутствии изменений использовать кэш промптов и снижать стоимость и задержку. Избегайте ненужных массовых правок и перестановок. Обычные изменения отдельных записей, как правило, влияют меньше.';

  @override
  String get memoryAboutFaqTitle => 'Частые вопросы';

  @override
  String get memoryAboutFaqWhyNotRememberedTitle =>
      'Почему это не запомнилось?';

  @override
  String get memoryAboutFaqWhyNotRememberedBody =>
      'Упорядочивание пропускается, если новых сообщений недостаточно, их нет совсем или не выбрана модель обработки памяти. Временные чаты в память не сохраняются. Память и автоупорядочивание также можно отключить для отдельного ассистента.';

  @override
  String get memorySettingsThinkingTitle => 'Включить рассуждения';

  @override
  String get memorySettingsThinkingSubtitle =>
      'Разрешить модели памяти рассуждать, если она это поддерживает';

  @override
  String get memorySettingsInjectionSection => 'Добавление памяти в контекст';

  @override
  String get memorySettingsInjectionMaxItemsTitle =>
      'Записей каждого типа в контексте';

  @override
  String get memorySettingsInjectionMaxItemsSubtitle =>
      'При превышении лимита добавляются только новые записи. Остальные доступны через memory_search_profile. Больший лимит даёт более полный контекст, но расходует больше токенов. Если вы меняли промпт правил, обновите его или восстановите исходный.';

  @override
  String memorySettingsInjectionMaxItemsOption(int n) {
    return '$n';
  }

  @override
  String get memorySettingsInjectionMaxItemsCustomButton => 'Свой вариант';

  @override
  String get memorySettingsInjectionMaxItemsCustomTitle =>
      'Своё количество записей';

  @override
  String get memorySettingsInjectionMaxItemsCustomDescription =>
      'Введите число от 1 до 100.';

  @override
  String get memorySettingsInjectionMaxItemsCustomLabel => 'Количество';

  @override
  String get memorySettingsInjectionMaxItemsCustomHint => '1–100';

  @override
  String get memorySettingsInjectionMaxItemsCustomInvalid =>
      'Введите число от 1 до 100';

  @override
  String get memorySettingsPromptLangSection => 'Язык промптов';

  @override
  String get memorySettingsPromptLangAuto => 'Авто';

  @override
  String get memorySettingsPromptLangAutoSubtitle =>
      'По языку интерфейса (китайский → zh, остальные → en)';

  @override
  String get memorySettingsPromptLangZh => 'Китайский';

  @override
  String get memorySettingsPromptLangZhSubtitle =>
      'Всегда использовать китайские промпты памяти и описания инструментов';

  @override
  String get memorySettingsPromptLangEn => 'Английский';

  @override
  String get memorySettingsPromptLangEnSubtitle =>
      'Всегда использовать английские промпты памяти и описания инструментов';

  @override
  String get memorySettingsPromptsSection => 'Шаблоны промптов';

  @override
  String get memorySettingsLegacyPromptTitle => 'Старые правила памяти';

  @override
  String get memoryPromptEditRulesTitle => 'Правила памяти';

  @override
  String get memoryPromptEditRulesSubtitle =>
      'Добавляются в системный промпт основного чата';

  @override
  String get memoryPromptEditGateTitle => 'Отбор для памяти';

  @override
  String get memoryPromptEditGateSubtitle =>
      'Определяет, стоит ли запоминать ход диалога';

  @override
  String get memoryPromptEditExtractTitle => 'Извлечение';

  @override
  String get memoryPromptEditExtractSubtitle =>
      'Извлекает возможные записи памяти из диалога';

  @override
  String get memoryPromptEditSmartAddTitle => 'Умное добавление';

  @override
  String get memoryPromptEditSmartAddSubtitle =>
      'Определение повторов: NEW / MERGE / CONFLICT / SKIP';

  @override
  String get memoryPromptEditDistillTitle => 'Формирование профиля';

  @override
  String get memoryPromptEditDistillSubtitle =>
      'Переносит сведения о личности из памяти в поля профиля';

  @override
  String get memoryPromptEditMigrateTitle => 'Миграция старых данных';

  @override
  String get memoryPromptEditMigrateSubtitle =>
      'Используется при переформулировании записей во время миграции';

  @override
  String get memoryPromptEditReset => 'Сбросить по умолчанию';

  @override
  String get memoryPromptEditSave => 'Сохранить';

  @override
  String get memoryPromptEditSectionPerItem => 'Промпт для отдельной записи';

  @override
  String get memoryPromptEditSectionBatch => 'Промпт для пакета записей';

  @override
  String get memorySettingsEntriesSection => 'Все записи памяти';

  @override
  String get memorySettingsLegacySection => 'Старая память';

  @override
  String get memorySettingsEntriesTitle => 'Список записей памяти';

  @override
  String get memorySettingsEntriesSubtitle =>
      'Просмотр, изменение, архивирование и удаление записей';

  @override
  String get memorySettingsProfileTitle => 'Профиль пользователя';

  @override
  String get memorySettingsProfileSubtitle =>
      'Структурированные сведения о пользователе для модели';

  @override
  String get memorySettingsLegacyTitle => 'Старые записи (только чтение)';

  @override
  String get memorySettingsLegacySubtitle =>
      'Записи памяти из предыдущих версий';

  @override
  String get memoryEntryTypeIdentity => 'Личность';

  @override
  String get memoryEntryTypeWorkflow => 'Рабочие привычки';

  @override
  String get memoryEntryTypeVoice => 'Голос';

  @override
  String get memoryEntryTypeInstruction => 'Инструкция';

  @override
  String get memoryEntryScopeGlobal => 'Общая';

  @override
  String get memoryEntryScopeAssistant => 'Этот ассистент';

  @override
  String memoryEntryScopeAssistantNamed(String name) {
    return '$name';
  }

  @override
  String get memoryEntrySourceManual => 'Вручную';

  @override
  String get memoryEntrySourceTool => 'Инструмент';

  @override
  String get memoryEntrySourceExtracted => 'Извлечено';

  @override
  String get memoryEntrySourceDistilled => 'Сформировано';

  @override
  String get memoryEntryStatusActive => 'Активен';

  @override
  String get memoryEntryStatusArchived => 'В архиве';

  @override
  String memoryEntryUpdatedAt(String date) {
    return 'Обновлено: $date';
  }

  @override
  String get memoryEntryActionEdit => 'Изменить';

  @override
  String get memoryEntryActionDelete => 'Удалить';

  @override
  String get memoryEntryActionArchive => 'В архив';

  @override
  String get memoryEntryActionRestore => 'Восстановить';

  @override
  String get memoryEntryActionSwitchScope => 'Изменить область';

  @override
  String get memoryEntryActionBatchDelete => 'Удалить выбранное';

  @override
  String get memoryEntryActionAdd => 'Добавить запись';

  @override
  String get memoryEntryDeleteConfirmTitle => 'Удалить запись памяти?';

  @override
  String get memoryEntryDeleteConfirmContent =>
      'Запись памяти будет удалена навсегда. Отменить удаление нельзя.';

  @override
  String memoryEntryBatchDeleteConfirmTitle(int count) {
    return 'Удалить записи памяти ($count)?';
  }

  @override
  String get memoryEntryBatchDeleteConfirmContent =>
      'Выбранные записи памяти будут удалены навсегда.';

  @override
  String get memoryEntrySwitchScopeConfirmTitle =>
      'Изменить область записи памяти?';

  @override
  String get memoryEntrySwitchScopeToGlobal =>
      'Сделать эту запись общей для всех ассистентов?';

  @override
  String get memoryEntrySwitchScopeToAssistant =>
      'Сделать эту запись доступной только текущему ассистенту?';

  @override
  String get memoryEntryArchivedSection => 'В архиве';

  @override
  String get memoryEntryEmpty => 'Записей в памяти пока нет';

  @override
  String get memoryEntryEmptyDisabled =>
      'Долговременная память отключена для этого ассистента';

  @override
  String get memoryEntryEditTitle => 'Изменить запись памяти';

  @override
  String get memoryEntryCreateTitle => 'Новая запись памяти';

  @override
  String get memoryEntryContentHint => 'Введите содержимое записи';

  @override
  String get memoryEntryTypeLabel => 'Тип';

  @override
  String get memoryEntryScopeLabel => 'Область';

  @override
  String get memoryFilterScopeAll => 'Все области';

  @override
  String get memoryFilterScopeGlobal => 'Только общая';

  @override
  String get memoryFilterScopeAssistant => 'Ассистент';

  @override
  String get memoryFilterTypeAll => 'Все типы';

  @override
  String get memoryFilterStatusAll => 'Все состояния';

  @override
  String get memoryFilterStatusActive => 'Активен';

  @override
  String get memoryFilterStatusArchived => 'В архиве';

  @override
  String get memorySearchHint => 'Поиск в памяти';

  @override
  String get memorySearchEmpty => 'Подходящих записей нет';

  @override
  String memoryOrphanBanner(int count) {
    return 'Записей удалённых ассистентов: $count';
  }

  @override
  String get memoryOrphanCleanupButton => 'Очистить';

  @override
  String get memoryOrphanConfirmTitle =>
      'Очистить записи удалённых ассистентов?';

  @override
  String memoryOrphanConfirmContent(int count) {
    return 'Безвозвратно удалить записи памяти ($count), чьи ассистенты больше не существуют.';
  }

  @override
  String get memoryOrganizeButton => 'Упорядочить';

  @override
  String get memoryOrganizeNeedsConversation =>
      'Откройте чат с этим ассистентом, чтобы упорядочить память';

  @override
  String get memoryOrganizeNeedsModel =>
      'Сначала выберите модель памяти: Настройки → Память';

  @override
  String get memoryOrganizeStatusNever => 'Ещё не упорядочивалось';

  @override
  String memoryOrganizeStatusLast(String when) {
    return 'Последнее упорядочивание: $when';
  }

  @override
  String memoryOrganizeStatusExtracted(int count) {
    return 'извлечено: $count';
  }

  @override
  String get memoryOrganizeStatusSkipped => 'нечего запоминать';

  @override
  String memoryOrganizeStatusFailed(String reason) {
    return 'Ошибка: $reason';
  }

  @override
  String memoryOrganizeStatusSkippedReason(String reason) {
    return 'пропущено: $reason';
  }

  @override
  String get memoryOutcomeTemporaryConversation =>
      'Временные чаты не сохраняются в память';

  @override
  String get memoryOutcomeMemoryDisabled =>
      'Память отключена для этого ассистента';

  @override
  String get memoryOutcomeAutoOrganizeOff => 'Автоупорядочивание отключено';

  @override
  String get memoryOutcomeStreaming => 'Пропущено: ответ ещё генерируется';

  @override
  String get memoryOutcomeBelowThreshold =>
      'Недостаточно новых сообщений для упорядочивания';

  @override
  String get memoryOutcomeEmptyWindow =>
      'Нет новых сообщений для упорядочивания';

  @override
  String get memoryOutcomeMemoryModelUnset =>
      'Не выбрана модель обработки памяти';

  @override
  String get memoryOutcomeMemoryModelMissing =>
      'Выбранная модель памяти больше недоступна';

  @override
  String get memoryOutcomeAssistantMissing => 'Ассистент не найден';

  @override
  String get memoryOutcomeConversationMissing => 'Диалог не найден';

  @override
  String get memoryOutcomeQueueOverflow =>
      'Очередь упорядочивания заполнена; этот запуск пропущен';

  @override
  String get memoryOutcomeGateRequestFailed =>
      'Не удалось обратиться к модели памяти для проверки необходимости запоминания';

  @override
  String get memoryOutcomeGateParseFailed =>
      'Проверка необходимости запоминания вернула ответ, который не удалось прочитать';

  @override
  String get memoryOutcomeExtractRequestFailed =>
      'Не удалось обратиться к модели для извлечения записей памяти';

  @override
  String get memoryOutcomeExtractParseFailed =>
      'Не удалось разобрать ответ с извлечёнными записями памяти';

  @override
  String get memoryOutcomeDistillFailed =>
      'Не удалось сформировать профиль пользователя';

  @override
  String get memoryOutcomeMemoryExecutionError =>
      'Не удалось выполнить инструмент памяти';

  @override
  String get memoryOutcomeUnsupportedTool =>
      'Неподдерживаемый инструмент памяти';

  @override
  String get memoryOutcomeInvalidMemoryType => 'Некорректный тип записи памяти';

  @override
  String get memoryOutcomeInvalidMemoryContent =>
      'Некорректное содержимое записи памяти';

  @override
  String get memoryOutcomeInvalidQuery => 'Некорректный поисковый запрос';

  @override
  String get memoryOutcomeInvalidMemoryId => 'Некорректный ID записи памяти';

  @override
  String get memoryOutcomeMemoryNotFound => 'Запись памяти не найдена';

  @override
  String get memoryOutcomeInvalidProfileFields => 'Некорректные поля профиля';

  @override
  String get memoryOutcomeChatSearchUnavailable => 'Поиск по чатам недоступен';

  @override
  String get memoryOrganizeJustNow => 'только что';

  @override
  String memoryOrganizeMinutesAgo(int n) {
    return '$n мин назад';
  }

  @override
  String memoryOrganizeHoursAgo(int n) {
    return '$n ч назад';
  }

  @override
  String memoryOrganizeDaysAgo(int n) {
    return '$n дн. назад';
  }

  @override
  String get memoryModelMissingNotice =>
      'Сначала выберите модель обработки памяти: Настройки → Память.';

  @override
  String get memoryModelMissingGoSelect => 'Выбрать модель';

  @override
  String get memoryEntriesPageTitle => 'Все записи памяти';

  @override
  String get userProfilePageTitle => 'Профиль пользователя';

  @override
  String get userProfilePreferredName => 'Предпочитаемое имя';

  @override
  String get userProfilePreferredNameHint =>
      'Как модель должна к вам обращаться; не связано с именем в боковой панели';

  @override
  String get userProfileGender => 'Пол';

  @override
  String get userProfilePronouns => 'Местоимения';

  @override
  String get userProfilePreferredLanguage => 'Предпочитаемый язык';

  @override
  String get userProfileTimezone => 'Часовой пояс';

  @override
  String get userProfileOccupation => 'Род деятельности';

  @override
  String get userProfileLocation => 'Местоположение';

  @override
  String get userProfileCustomSection => 'Свои поля';

  @override
  String get userProfileAddCustom => 'Добавить своё поле';

  @override
  String get userProfileCustomKeyHint => 'Ключ (custom.name)';

  @override
  String get userProfileCustomValueHint => 'Значение';

  @override
  String get userProfileInvalidKey =>
      'Ключ должен начинаться с custom., затем содержать 1–32 буквы, цифры, _ или -';

  @override
  String get userProfileClear => 'Очистить';

  @override
  String get userProfileSave => 'Сохранить';

  @override
  String get userProfileEmptyValue => 'Не задано';

  @override
  String get legacyMemoryPageTitle => 'Старые записи памяти';

  @override
  String get legacyMemoryBanner =>
      'Эти записи созданы в старой версии и не используются в чатах. Их можно перенести в текущую систему памяти.';

  @override
  String get legacyMemoryEmpty => 'Нет старых записей памяти';

  @override
  String get legacyMemoryCopy => 'Копировать';

  @override
  String get legacyMemoryCopied => 'Скопировано';

  @override
  String get legacyMemoryExport => 'Экспорт';

  @override
  String get legacyMemoryExportTitle => 'Экспорт старых записей памяти Moru';

  @override
  String legacyMemoryAssistantHeader(String name) {
    return 'Ассистент: $name';
  }

  @override
  String get legacyMemorySearchHint => 'Поиск по старым записям';

  @override
  String get legacyMemoryMigrate => 'Перенести';

  @override
  String get legacyMemoryMigrationTitle => 'Перенести старые записи памяти';

  @override
  String legacyMemoryMigrationSubtitle(int count) {
    return 'Модель классифицирует и упорядочит старые записи памяти ($count). Исходные записи не изменятся.';
  }

  @override
  String get legacyMemoryMigrationModel => 'Модель переноса';

  @override
  String get legacyMemoryMigrationChooseModel => 'Выберите модель';

  @override
  String get legacyMemoryMigrationTarget => 'Сохранить в';

  @override
  String get legacyMemoryMigrationTargetGlobal => 'Общая';

  @override
  String get legacyMemoryMigrationTargetAssistant => 'Текущий ассистент';

  @override
  String get legacyMemoryMigrationTargetOriginalAssistants =>
      'Исходные ассистенты';

  @override
  String get legacyMemoryMigrationTargetGlobalDescription =>
      'Доступно всем ассистентам';

  @override
  String get legacyMemoryMigrationTargetAssistantDescription =>
      'Доступно только этому ассистенту';

  @override
  String get legacyMemoryMigrationTargetOriginalDescription =>
      'Оставить каждую запись у её исходного ассистента';

  @override
  String get legacyMemoryMigrationStart => 'Начать перенос';

  @override
  String get legacyMemoryMigrationAnalyzing => 'Анализ моделью';

  @override
  String get legacyMemoryMigrationWriting => 'Сохранение записей памяти';

  @override
  String legacyMemoryMigrationProgress(int current, int total) {
    return '$current из $total';
  }

  @override
  String get legacyMemoryMigrationComplete => 'Перенос завершён';

  @override
  String legacyMemoryMigrationResult(int created, int skipped) {
    return 'Перенесено: $created · уже существовало: $skipped';
  }

  @override
  String get legacyMemoryMigrationFailed =>
      'Перенос остановлен. Можно повторить: уже сохранённые записи будут пропущены.';

  @override
  String get legacyMemoryMigrationRetry => 'Повторить';

  @override
  String get legacyMemoryMigrationClose => 'Готово';

  @override
  String get legacyMemoryMigrationContentMode => 'Содержимое';

  @override
  String get legacyMemoryMigrationContentPreserve => 'Сохранить исходный текст';

  @override
  String get legacyMemoryMigrationContentOrganize =>
      'Переформулировать моделью';

  @override
  String get legacyMemoryMigrationContentPreserveDescription =>
      'Модель только определяет тип. Исходная формулировка сохраняется без изменений.';

  @override
  String get legacyMemoryMigrationContentOrganizeDescription =>
      'Модель классифицирует и переформулирует каждую запись по редактируемому промпту переноса.';

  @override
  String get legacyMemoryMigrationBatchSize => 'Размер пакета';

  @override
  String legacyMemoryMigrationPartial(int created, int skipped, int failed) {
    return 'Перенесено: $created · пропущено: $skipped · ошибок: $failed';
  }

  @override
  String get legacyMemoryMigrationContinue => 'Продолжить перенос';

  @override
  String get legacyMemoryMigrationErrorNetwork =>
      'Ошибка сети. Проверьте подключение и повторите попытку.';

  @override
  String get legacyMemoryMigrationErrorFormat =>
      'Модель вернула некорректный ответ.';

  @override
  String get legacyMemoryMigrationErrorAuth =>
      'Ошибка авторизации. Проверьте API-ключ.';

  @override
  String legacyMemoryMigrationErrorOther(String message) {
    return 'Не удалось перенести: $message';
  }

  @override
  String get legacyMemoryModeTitle => 'Использовать старую память';

  @override
  String get legacyMemoryModeSubtitle => 'Общая настройка для всех ассистентов';

  @override
  String legacyMemoryModeCacheWarning(String token) {
    return 'Шаблон по умолчанию добавляет текущее время через $token, что снижает долю попаданий в кэш. Удалите эту переменную, если время не нужно.';
  }

  @override
  String get memoryUiContentLabel => 'Содержимое';

  @override
  String get memoryUiValueLabel => 'Значение';

  @override
  String get memoryUiCustomKeyLabel => 'Ключ';

  @override
  String get memoryUiStatusLabel => 'Статус';

  @override
  String get memoryUiAssistantLabel => 'Ассистент';

  @override
  String get memoryUiAssistantAll => 'Все ассистенты';

  @override
  String get memoryUiSearchClear => 'Очистить поиск';

  @override
  String get memoryUiAssistantLegacyTitle => 'Старые записи (только чтение)';

  @override
  String get memoryUiAssistantLegacySubtitle =>
      'Записи памяти этого ассистента из предыдущих версий';

  @override
  String get assistantEditMemorySwitchTitle =>
      'Использовать долговременную память';

  @override
  String get assistantEditMemorySwitchSubtitle =>
      'Добавлять сохранённые записи в контекст чатов и разрешить ассистенту создавать новые';

  @override
  String get assistantEditAutoOrganizeTitle => 'Автоупорядочивание памяти';

  @override
  String get assistantEditAutoOrganizeSubtitle =>
      'Запускать обработку памяти после общения';

  @override
  String get assistantEditAllowPastRecallTitle =>
      'Разрешить вспоминать прошлые чаты';

  @override
  String get assistantEditAllowPastRecallSubtitle =>
      'Включить поиск по прошлым диалогам';

  @override
  String get assistantEditGenerateSummaryTitle => 'Создавать сводки диалогов';

  @override
  String get assistantEditGenerateSummarySubtitle =>
      'Сводки используются только при поиске по чатам';

  @override
  String get assistantEditManageMemoryTitle =>
      'Память, доступная этому ассистенту';

  @override
  String get assistantEditWriteScopeTitle => 'Область записи памяти';

  @override
  String get assistantEditWriteScopeSubtitle =>
      'Где по умолчанию сохраняются новые записи';

  @override
  String get assistantEditWriteScopeAlwaysGlobal => 'Всегда общая';

  @override
  String get assistantEditWriteScopeAlwaysGlobalSubtitle =>
      'Новые записи доступны всем ассистентам';

  @override
  String get assistantEditWriteScopeAlwaysAssistant => 'Всегда этот ассистент';

  @override
  String get assistantEditWriteScopeAlwaysAssistantSubtitle =>
      'Новые записи доступны только этому ассистенту';

  @override
  String get assistantEditWriteScopeToolDefaultGlobal =>
      'Выбирает модель (по умолчанию — общая)';

  @override
  String get assistantEditWriteScopeToolDefaultGlobalSubtitle =>
      'Модель выбирает общую память или память ассистента; по умолчанию — общую';

  @override
  String get assistantEditWriteScopeToolDefaultAssistant =>
      'Выбирает модель (по умолчанию — ассистент)';

  @override
  String get assistantEditWriteScopeToolDefaultAssistantSubtitle =>
      'Модель выбирает общую память или память ассистента; по умолчанию — память ассистента';

  @override
  String get assistantEditDedupeModeTitle => 'Поиск повторов';

  @override
  String get assistantEditDedupeModeSubtitle =>
      'Как новые записи сравниваются с существующими';

  @override
  String get assistantEditDedupeModeBatched => 'Пакетом';

  @override
  String get assistantEditDedupeModeBatchedSubtitle =>
      'Проверять все новые записи одним запросом. Быстрее и дешевле, но менее точно при большом числе записей.';

  @override
  String get assistantEditDedupeModePerItem => 'По одной';

  @override
  String get assistantEditDedupeModePerItemSubtitle =>
      'Проверять каждую запись отдельным запросом. Точнее, но требует больше обращений к модели.';

  @override
  String get assistantEditOrganizeFrequencyTitle =>
      'Упорядочивать каждые N ходов';

  @override
  String get assistantEditOrganizeFrequencySubtitle =>
      'Запускать автоупорядочивание после указанного числа ответов ассистента';

  @override
  String assistantEditOrganizeFrequencyOption(int n) {
    return 'Каждые $n';
  }

  @override
  String get assistantEditOrganizeFrequencyCustomButton => 'Свой вариант';

  @override
  String get assistantEditOrganizeFrequencyCustomTitle => 'Своя частота';

  @override
  String get assistantEditOrganizeFrequencyCustomDescription =>
      'Введите число от 1 до 20.';

  @override
  String get assistantEditOrganizeFrequencyCustomLabel => 'Ходы';

  @override
  String get assistantEditOrganizeFrequencyCustomHint => '1–20';

  @override
  String get assistantEditOrganizeFrequencyCustomInvalid =>
      'Введите число от 1 до 20';

  @override
  String get worldBookTitle => 'Книга мира';

  @override
  String get worldBookAdd => 'Добавить книгу мира';

  @override
  String get worldBookEmptyMessage => 'Книг мира пока нет';

  @override
  String get worldBookUnnamed => 'Книга мира без названия';

  @override
  String get worldBookDisabledTag => 'Отключено';

  @override
  String get worldBookAlwaysOnTag => 'Всегда включено';

  @override
  String get worldBookAddEntry => 'Добавить запись';

  @override
  String get worldBookExport => 'Поделиться / экспортировать';

  @override
  String get worldBookConfig => 'Настроить';

  @override
  String get worldBookDeleteTitle => 'Удалить книгу мира';

  @override
  String worldBookDeleteMessage(String name) {
    return 'Удалить «$name»? Отменить удаление нельзя.';
  }

  @override
  String get worldBookCancel => 'Отмена';

  @override
  String get worldBookDelete => 'Удалить';

  @override
  String worldBookExportFailed(String error) {
    return 'Не удалось экспортировать: $error';
  }

  @override
  String get worldBookNoEntriesHint => 'Нет записей';

  @override
  String get worldBookUnnamedEntry => 'Запись без названия';

  @override
  String worldBookKeywordsLine(String keywords) {
    return 'Ключевые слова: $keywords';
  }

  @override
  String get worldBookEditEntry => 'Изменить запись';

  @override
  String get worldBookDeleteEntry => 'Удалить запись';

  @override
  String get worldBookNameLabel => 'Имя';

  @override
  String get worldBookDescriptionLabel => 'Описание';

  @override
  String get worldBookEnabledLabel => 'Включено';

  @override
  String get worldBookSave => 'Сохранить';

  @override
  String get worldBookEntryNameLabel => 'Название записи';

  @override
  String get worldBookEntryEnabledLabel => 'Запись включена';

  @override
  String get worldBookEntryPriorityLabel => 'По приоритету';

  @override
  String get worldBookEntryKeywordsLabel => 'Ключевые слова';

  @override
  String get worldBookEntryKeywordsHint =>
      'Введите ключевое слово и нажмите +, чтобы добавить его.';

  @override
  String get worldBookEntryKeywordInputHint => 'Введите ключевое слово';

  @override
  String get worldBookEntryKeywordAddTooltip => 'Добавить ключевое слово';

  @override
  String get worldBookEntryUseRegexLabel => 'Использовать регулярные выражения';

  @override
  String get worldBookEntryCaseSensitiveLabel => 'Учитывать регистр';

  @override
  String get worldBookEntryAlwaysOnLabel => 'Всегда активно';

  @override
  String get worldBookEntryAlwaysOnHint =>
      'Всегда добавлять в контекст без проверки ключевых слов';

  @override
  String get worldBookEntryScanDepthLabel => 'Глубина поиска';

  @override
  String get worldBookEntryContentLabel => 'Содержимое';

  @override
  String get worldBookEntryInjectionPositionLabel => 'Место вставки';

  @override
  String get worldBookEntryInjectionRoleLabel => 'Роль вставки';

  @override
  String get worldBookEntryInjectDepthLabel => 'Глубина вставки';

  @override
  String get worldBookInjectionPositionBeforeSystemPrompt =>
      'Перед системным промптом';

  @override
  String get worldBookInjectionPositionAfterSystemPrompt =>
      'После системного промпта';

  @override
  String get worldBookInjectionPositionTopOfChat => 'В начале чата';

  @override
  String get worldBookInjectionPositionBottomOfChat => 'В конце чата';

  @override
  String get worldBookInjectionPositionAtDepth => 'На заданной глубине';

  @override
  String get worldBookInjectionRoleUser => 'Пользователь';

  @override
  String get worldBookInjectionRoleAssistant => 'Ассистент';

  @override
  String get mcpToolNeedsApproval => 'Требовать подтверждение';

  @override
  String get toolApprovalPending => 'Ожидание подтверждения';

  @override
  String get toolApprovalApprove => 'Разрешить';

  @override
  String get toolApprovalDeny => 'Отклонить';

  @override
  String get toolApprovalDenyTitle => 'Отклонить вызов инструмента';

  @override
  String get toolApprovalDenyHint => 'Причина (необязательно)';

  @override
  String toolApprovalDeniedMessage(Object reason, Object toolName) {
    return 'Пользователь отклонил вызов инструмента «$toolName». Причина: $reason';
  }

  @override
  String get askUserCardSubmit => 'Отправить ответ';

  @override
  String get askUserCardCustomHint => 'Введите ответ';

  @override
  String get askUserCardSomethingElse => 'Другой вариант';

  @override
  String get askUserCardSkip => 'Пропустить';

  @override
  String get askUserCardSkipped => 'Пропущено';

  @override
  String get askUserCardAnswered => 'Ответ получен';

  @override
  String get askUserCardInactive =>
      'Этот вопрос больше не активен. Сгенерируйте ответ заново или продолжите диалог.';

  @override
  String get askUserCardCancelled => 'Вопрос отменён';

  @override
  String askUserCardQuestionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Задать $count вопроса',
      many: 'Задать $count вопросов',
      few: 'Задать $count вопроса',
      one: 'Задать $count вопрос',
    );
    return '$_temp0';
  }

  @override
  String tokenDetailPromptTokens(int count) {
    return 'Токенов: $count';
  }

  @override
  String tokenDetailPromptTokensWithCache(int count, int cached) {
    return 'Токенов: $count (из кэша: $cached)';
  }

  @override
  String tokenDetailCompletionTokens(int count) {
    return 'Токенов: $count';
  }

  @override
  String tokenDetailSpeed(String value) {
    return '$value ток/с';
  }

  @override
  String tokenDetailDuration(String value) {
    return '$value с';
  }

  @override
  String tokenDetailTotalTokens(int count) {
    return 'Токенов: $count';
  }

  @override
  String get debugPageTitle => 'Отладка';

  @override
  String get debugPageConversationToolsTitle => 'Инструменты диалогов';

  @override
  String get debugPageCreateOversizedConversationButton =>
      'Создать очень большой диалог (30 МБ)';

  @override
  String get debugPageCreateManyMessagesConversationButton =>
      'Создать диалог из 1024 сообщений';

  @override
  String get debugPageCreateDailyMixedMarkdownConversationButton =>
      'Создать 3000 повседневных сообщений с разным Markdown';

  @override
  String get debugPageCreateLongReasoningConversationButton =>
      'Создать диалог с длинными рассуждениями (128 сообщений)';

  @override
  String get debugPageCreatingButton => 'Создание…';

  @override
  String get debugPageCreatingOversizedConversation =>
      'Создание большого диалога на 30 МБ…';

  @override
  String get debugPageCreatingManyMessagesConversation =>
      'Создание диалога из 1024 сообщений…';

  @override
  String get debugPageCreatingDailyMixedMarkdownConversation =>
      'Создание диалога из 3000 повседневных сообщений с разным Markdown…';

  @override
  String get debugPageCreatingLongReasoningConversation =>
      'Создание отладочного диалога с длинными рассуждениями…';

  @override
  String get debugPageNoCurrentAssistant =>
      'Нет текущего ассистента. Сначала создайте или выберите ассистента.';

  @override
  String debugPageConversationCreated(int count) {
    return 'Создан отладочный диалог. Сообщений: $count.';
  }

  @override
  String debugPageCreateConversationFailed(String error) {
    return 'Не удалось создать отладочный диалог: $error';
  }

  @override
  String debugPageOversizedConversationTitle(int sizeMB) {
    return 'Проверка большого диалога ($sizeMB МБ)';
  }

  @override
  String debugPageManyMessagesConversationTitle(int count) {
    return 'Проверка диалога: $count сообщений';
  }

  @override
  String debugPageDailyMixedMarkdownConversationTitle(int count) {
    return 'Проверка повседневного Markdown: $count сообщений';
  }

  @override
  String debugPageLongReasoningConversationTitle(int count) {
    return 'Проверка длинных рассуждений: $count сообщений';
  }

  @override
  String get debugPageOversizedConversationSeedText =>
      'Это длинный отладочный текст для воспроизведения медленной отрисовки очень больших диалогов. В нём есть повторяющийся текст, похожий на Markdown, знаки препинания, китайские, японские и корейские символы, а также обычные слова для профилирования отрисовки чата, хранения и прокрутки.';

  @override
  String debugPageManyMessagesSeedText(String role, int index) {
    return 'Сообщение $role №$index: короткий случайный отладочный пример для проверки отрисовки списка, устойчивости прокрутки, группировки сообщений и производительности истории диалога.';
  }

  @override
  String get migrationIntroTitle => 'Обновление хранилища чатов';

  @override
  String get migrationIntroSubtitle =>
      'Moru переносит историю чатов в более быструю базу SQLite. Обновление выполняется до открытия приложения, чтобы сохранить согласованность данных.';

  @override
  String get migrationBackupNote =>
      'Перед переносом Moru экспортирует ZIP-копию настроек, истории чатов и локальных файлов.';

  @override
  String get migrationPerformanceNote =>
      'После переноса запуск, загрузка истории и поиск используют индексы SQLite для более плавной работы с длинными чатами.';

  @override
  String get migrationSourceDatabaseLabel => 'Hive';

  @override
  String get migrationTargetDatabaseLabel => 'SQLite';

  @override
  String get migrationChooseFolderButton => 'Выбрать папку и создать копию';

  @override
  String get migrationSaveBackupButton => 'Сохранить ZIP-копию';

  @override
  String get migrationStartWithoutBackupButton =>
      'Перенести без резервной копии';

  @override
  String get migrationSkipChatsJsonOption => 'Пропустить chats.json';

  @override
  String get migrationSkipChatsJsonDescription =>
      'Исходные файлы Hive, настройки и локальные файлы всё равно сохраняются в копию. Рекомендуется для очень большой истории.';

  @override
  String get migrationSkipBackupOption => 'Пропустить эту копию';

  @override
  String get migrationSkipBackupDescription =>
      'Выбирайте только при наличии проверенной резервной копии. Перенос начнётся сразу.';

  @override
  String get migrationBackingUpTitle => 'Создание резервной копии';

  @override
  String get migrationBackingUpSubtitle =>
      'Экспорт настроек, истории чатов, загруженных файлов, изображений и шрифтов. Не закрывайте Moru до завершения.';

  @override
  String get migrationMigratingTitle => 'Перенос в SQLite';

  @override
  String get migrationMigratingSubtitle =>
      'Диалоги и сообщения записываются пакетами, чтобы большая история не перегружала память. Не сворачивайте Moru до завершения переноса.';

  @override
  String migrationBackingUpDetail(String fileName) {
    return 'Копирование: $fileName';
  }

  @override
  String migrationMigratingDetail(int count) {
    return 'Перенесено сообщений: $count';
  }

  @override
  String get migrationMigratingPrepareDetail => 'Подготовка базы SQLite';

  @override
  String get migrationMigratingToolEventsDetail =>
      'Перенос записей инструментов';

  @override
  String get migrationMigratingValidateDetail => 'Проверка перенесённых данных';

  @override
  String get migrationBackupReadyDetail => 'ZIP-копия готова';

  @override
  String get migrationSavingBackupZipDetail => 'Сохранение ZIP-копии';

  @override
  String get migrationBackupFileSavedTitle => 'ZIP-копия сохранена';

  @override
  String get migrationChecklistBackupFiles => 'Экспортировать ZIP-копию Hive';

  @override
  String get migrationChecklistPrepareSqlite => 'Подготовить базу SQLite';

  @override
  String get migrationChecklistMigrateMessages =>
      'Перенести диалоги и сообщения';

  @override
  String get migrationChecklistMigrateToolEvents =>
      'Перенести записи инструментов';

  @override
  String get migrationChecklistValidate => 'Проверить перенесённые данные';

  @override
  String get migrationStepBackup => 'Резервное копирование';

  @override
  String get migrationStepMigrate => 'Перенести';

  @override
  String get migrationStepComplete => 'Готово';

  @override
  String get migrationCompleteTitle => 'Обновление завершено';

  @override
  String get migrationCompleteSubtitle =>
      'История чатов теперь хранится в SQLite. Перезапустите Moru, чтобы открыть обновлённое приложение.';

  @override
  String get migrationConversationCount => 'Диалоги';

  @override
  String get migrationMessageCount => 'Сообщения';

  @override
  String get migrationConvertedCount => 'Преобразовано';

  @override
  String get migrationMalformedCount => 'Некорректных записей';

  @override
  String get migrationMissingFilesCount => 'Отсутствующих файлов';

  @override
  String get migrationRestartButton => 'Перезапустить Moru';

  @override
  String get migrationFailedTitle => 'Не удалось перенести данные';

  @override
  String get migrationFailedSubtitle =>
      'Исходные данные Hive не повреждены. Ранее созданные резервные копии не изменены. Изучите причину ниже и повторите попытку.';

  @override
  String get migrationUnknownError => 'Неизвестная ошибка переноса.';

  @override
  String get migrationFailureLogTitle => 'Журнал ошибки';

  @override
  String get migrationRetryButton => 'Повторить перенос';

  @override
  String get migrationSkipButton => 'Пропустить перенос и начать заново';

  @override
  String get migrationSkipDialogTitle => 'Пропустить перенос?';

  @override
  String get migrationSkipDialogMessage =>
      'Moru начнёт работу с пустой базой чатов. Старая история останется на диске с суффиксом .retired, но НЕ будет перенесена и не появится в приложении. Для последующего восстановления используйте резервную ZIP-копию.';

  @override
  String get migrationSkipDialogCancel => 'Отмена';

  @override
  String get migrationSkipDialogConfirm => 'Пропустить и начать заново';

  @override
  String get migrationChatsExportDegradedNote =>
      'Экспорт chats.json пропущен из-за ошибки. В ZIP-копии всё равно сохранены исходные файлы Hive с полной историей чатов.';

  @override
  String get timelineJumpToLatest => 'К последним сообщениям';

  @override
  String largeContentShowMore(int count) {
    return 'Показать ещё: $count';
  }

  @override
  String get largeContentCollapse => 'Свернуть';

  @override
  String get imageSettingsPageTitle => 'Обработка изображений';

  @override
  String get imageSettingsPageEditSectionTitle => 'Редактирование';

  @override
  String get imageSettingsPageQualitySectionTitle =>
      'Качество загружаемых изображений';

  @override
  String get imageSettingsPageQualityOriginal => 'Исходное';

  @override
  String get imageSettingsPageQualityOriginalSubtitle =>
      'Не сжимать; отправлять без изменений';

  @override
  String get imageSettingsPageQualityHigh => 'Высокое качество';

  @override
  String get imageSettingsPageQualityHighSubtitle =>
      'Длинная сторона 2048 пикс. · качество 90';

  @override
  String get imageSettingsPageQualityBalanced => 'Сбалансированное';

  @override
  String get imageSettingsPageQualityBalancedSubtitle =>
      'Длинная сторона 1568 пикс. · качество 85';

  @override
  String get imageSettingsPageQualitySaver => 'Экономия трафика';

  @override
  String get imageSettingsPageQualitySaverSubtitle =>
      'Длинная сторона 1024 пикс. · качество 70';

  @override
  String get imageSettingsPageQualityCustom => 'Свой вариант';

  @override
  String get imageSettingsPageQualityCustomSubtitle =>
      'Выберите качество сжатия';

  @override
  String get imageSettingsPageCustomQualityTitle => 'Качество сжатия';

  @override
  String get imageSettingsPageCompressTransparentTitle =>
      'Сжимать прозрачные и анимированные изображения';

  @override
  String get imageSettingsPageCompressTransparentSubtitle =>
      'Если включено, прозрачные PNG, GIF и подобные форматы сжимаются: прозрачность заменяется белым фоном, а из анимации остаётся только первый кадр.';

  @override
  String get imageSettingsPageFooter =>
      'Сжатие выполняется при добавлении изображений. Ранее сохранённые и отправленные изображения не меняются. Сжатые изображения отправляются как JPEG.';

  @override
  String get imageSettingsPageSendSectionTitle => 'Отправка';

  @override
  String get imageSettingsPageMarkdownImageLinksTitle =>
      'Отправлять Markdown-ссылки на изображения как изображения';

  @override
  String get imageSettingsPageMarkdownImageLinksSubtitle =>
      'Если включено, ссылка ![alt](url) в тексте сообщения отправляется модели с поддержкой зрения как изображение. Иначе она остаётся текстом. Прикреплённые вами изображения всегда отправляются как изображения.';

  @override
  String get memoryTraceSettingsTitle => 'Трассировка обработки';

  @override
  String get memoryTraceSettingsSubtitle =>
      'Пошаговая проверка каждого фонового запуска обработки памяти';

  @override
  String get memoryTracePageTitle => 'Трассировка обработки памяти';

  @override
  String get memoryTraceRecordingSection => 'Запись';

  @override
  String get memoryTraceToggleTitle => 'Записывать трассировки обработки';

  @override
  String get memoryTraceToggleSubtitle =>
      'Хранить промпты, ответы и изменения последних фоновых запусков только в оперативной памяти';

  @override
  String get memoryTraceRunsSection => 'Последние запуски';

  @override
  String get memoryTraceEmptyTitle => 'Трассировок пока нет';

  @override
  String get memoryTraceEmptySubtitle =>
      'Трассировки появятся после фоновой обработки памяти.';

  @override
  String get memoryTraceDisabledTitle => 'Запись отключена';

  @override
  String get memoryTraceDisabledSubtitle =>
      'Включите запись, чтобы зафиксировать следующий запуск фоновой обработки памяти.';

  @override
  String get memoryTraceClearAction => 'Очистить';

  @override
  String get memoryTraceClearSheetTitle => 'Очистить трассировки';

  @override
  String get memoryTraceClearSheetMessage =>
      'Будут удалены все записанные трассировки. Они не сохраняются на диск, поэтому другие данные не пострадают.';

  @override
  String get memoryTraceClearConfirm => 'Очистить трассировки';

  @override
  String get memoryTraceCancel => 'Отмена';

  @override
  String get memoryTraceClearedToast => 'Трассировки очищены';

  @override
  String get memoryTraceCopyAction => 'Копировать';

  @override
  String get memoryTraceCopiedToast => 'Скопировано в буфер обмена';

  @override
  String get memoryTraceTriggerAuto => 'Авто';

  @override
  String get memoryTraceTriggerManual => 'Вручную';

  @override
  String get memoryTraceTriggerTool => 'Вызов инструмента';

  @override
  String get memoryTraceTriggerSummary => 'Сводка';

  @override
  String get memoryTraceScopeAssistant => 'Ассистент';

  @override
  String get memoryTraceScopeGlobal => 'Общая';

  @override
  String get memoryTraceStepGatekeeper => 'Отбор для памяти';

  @override
  String get memoryTraceStepExtract => 'Извлечение';

  @override
  String get memoryTraceStepSmartAdd => 'Умное добавление';

  @override
  String get memoryTraceStepDistiller => 'Формирование профиля';

  @override
  String get memoryTraceStepSummary => 'Сводка диалога';

  @override
  String get memoryTraceStepChatSearch => 'Поиск по прошлым диалогам';

  @override
  String get memoryTraceStepTool => 'Инструмент памяти';

  @override
  String get memoryTraceStatusSuccess => 'Успешно';

  @override
  String get memoryTraceStatusFailed => 'Ошибка';

  @override
  String get memoryTraceStatusSkipped => 'Пропущено';

  @override
  String get memoryTraceStatusRunning => 'Выполняется';

  @override
  String get memoryTraceOutcomeAdvanced => 'Граница обработки сдвинута';

  @override
  String get memoryTraceOutcomeHeld => 'Граница обработки сохранена';

  @override
  String get memoryTraceOutcomeForced => 'Принудительный сдвиг';

  @override
  String get memoryTraceDetailTitle => 'Подробности трассировки';

  @override
  String get memoryTraceSectionOverview => 'Обзор';

  @override
  String get memoryTraceSectionPrompt => 'Промпт';

  @override
  String get memoryTraceSectionResponse => 'Исходный ответ';

  @override
  String get memoryTraceSectionParsed => 'Разобранный результат';

  @override
  String get memoryTraceSectionMutations => 'Применённые изменения';

  @override
  String get memoryTraceFieldTime => 'Начало';

  @override
  String get memoryTraceFieldDuration => 'Длительность';

  @override
  String get memoryTraceFieldTrigger => 'Причина запуска';

  @override
  String get memoryTraceFieldScope => 'Область';

  @override
  String get memoryTraceFieldConversation => 'Чат';

  @override
  String get memoryTraceFieldAssistant => 'Ассистент';

  @override
  String get memoryTraceFieldWindow => 'Диапазон';

  @override
  String get memoryTraceFieldWatermark => 'Граница обработки';

  @override
  String get memoryTraceFieldOutcome => 'Итог';

  @override
  String get memoryTraceFieldError => 'Ошибка';

  @override
  String get memoryTraceMutationCreated => 'Создано';

  @override
  String get memoryTraceMutationMerged => 'Объединено';

  @override
  String get memoryTraceMutationEdited => 'Изменено';

  @override
  String get memoryTraceMutationArchived => 'В архиве';

  @override
  String get memoryTraceMutationLinked => 'Связано';

  @override
  String get memoryTraceMutationProfileWritten => 'Поле профиля записано';

  @override
  String get memoryTraceMutationProfileCleared => 'Поле профиля очищено';

  @override
  String get memoryTraceMutationSummary => 'Сводка чата записана';

  @override
  String get memoryTraceBefore => 'До';

  @override
  String get memoryTraceAfter => 'После';

  @override
  String get memoryTraceEmptyValue => '(пусто)';

  @override
  String memoryTraceStepsCount(int count) {
    return 'Шагов: $count';
  }

  @override
  String memoryTraceMutationsCount(int count) {
    return 'Изменений: $count';
  }

  @override
  String memoryTraceRepeatCount(int count) {
    return 'повторено $count×';
  }

  @override
  String memoryTraceWindowValue(int size, int start, int end) {
    return 'Сообщений: $size · №$start–$end';
  }

  @override
  String get memoryTraceShowMore => 'Показать весь текст';

  @override
  String get memoryTraceShowLess => 'Свернуть';

  @override
  String get messageStyleSettingsPageTitle => 'Стиль сообщений';

  @override
  String get messageStyleSettingsPageReset => 'Сбросить';

  @override
  String get messageStyleSettingsPageResetConfirm =>
      'Сбросить все настройки стиля сообщений?';

  @override
  String get messageStyleSettingsPageCancel => 'Отмена';

  @override
  String get messageStyleSettingsPageLight => 'Светлая';

  @override
  String get messageStyleSettingsPageDark => 'Тёмная';

  @override
  String get messageStyleSettingsPageDefaultHint =>
      'Стиль по умолчанию соответствует текущей теме и не имеет дополнительных настроек.';

  @override
  String get messageStyleSettingsPageStyleDefaultSubtitle =>
      'Соответствует теме; не настраивается';

  @override
  String get messageStyleSettingsPageAssistantFitContent =>
      'Подгонять пузырь ассистента под содержимое';

  @override
  String get messageStyleSettingsPageAssistantFitContentSubtitle =>
      'Пузырь ответа занимает ширину текста, а не всю строку';

  @override
  String get messageStyleSettingsPageAssistantSplitParagraphs =>
      'Разделять абзацы на пузыри';

  @override
  String get messageStyleSettingsPageAssistantSplitParagraphsSubtitle =>
      'Пустые строки разделяют ответ ассистента на отдельные пузыри по абзацам';

  @override
  String get messageStyleSettingsPageStyleFrostedSubtitle =>
      'Полупрозрачное матовое стекло';

  @override
  String get messageStyleSettingsPageStyleSolidSubtitle =>
      'Непрозрачная заливка';

  @override
  String get messageStyleSettingsPageBlur => 'Размытие';

  @override
  String get messageStyleSettingsPageBlurHint =>
      'Размывается содержимое за пузырём. Без фонового изображения чата эффект почти незаметен.';

  @override
  String get messageStyleSettingsPageBackgroundColor => 'Фон';

  @override
  String get messageStyleSettingsPageBackgroundOpacity => 'Непрозрачность фона';

  @override
  String get messageStyleSettingsPageBorderColor => 'Рамка';

  @override
  String get messageStyleSettingsPageBorderOpacity => 'Непрозрачность рамки';

  @override
  String get messageStyleSettingsPageBorderWidth => 'Толщина рамки';

  @override
  String get messageStyleSettingsPageTextColor => 'Текст';

  @override
  String get messageStyleSettingsPageCornerRadius => 'Радиус скругления';

  @override
  String get messageStyleSettingsPagePreviewUser =>
      'Это сообщение пользователя';

  @override
  String get messageStyleSettingsPagePreviewAssistant =>
      'Это ответ ассистента.';

  @override
  String get messageStyleSettingsPagePreviewThinking => 'Размышление';

  @override
  String get messageStyleSettingsPageRoleUser => 'Пользователь';

  @override
  String get messageStyleSettingsPageRoleAssistant => 'Ассистент';

  @override
  String get messageStyleSettingsPageRoleAssistantHint =>
      'Настройки ассистента также применяются к карточкам рассуждений, вызовов инструментов и перевода.';

  @override
  String get localSnapshotSectionTitle => 'Локальные копии';

  @override
  String get localSnapshotEnabledTitle => 'Хранить локальные копии';

  @override
  String get localSnapshotEnabledSubtitle =>
      'Moru периодически сохраняет копию базы на этом устройстве, чтобы она не оставалась в единственном экземпляре.';

  @override
  String get localSnapshotIntervalTitle => 'Как часто';

  @override
  String get localSnapshotIntervalAutomatic => 'Автоматически';

  @override
  String get localSnapshotIntervalAutomaticDetail =>
      'Ежедневно; реже по мере роста базы';

  @override
  String localSnapshotIntervalDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Интервал: $days дн.',
      one: 'Каждый день',
    );
    return '$_temp0';
  }

  @override
  String get localSnapshotKeepTitle => 'Количество хранимых копий';

  @override
  String localSnapshotKeepValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count копии',
      many: '$count копий',
      few: '$count копии',
      one: '$count копия',
    );
    return '$_temp0';
  }

  @override
  String get localSnapshotKeepSubtitle =>
      'Также по одной копии за прошлую неделю и прошлый месяц, чтобы можно было восстановить данные при поздно обнаруженной проблеме.';

  @override
  String get localSnapshotKeepWeekly => 'Хранить копию за прошлую неделю';

  @override
  String get localSnapshotKeepMonthly => 'Хранить копию за прошлый месяц';

  @override
  String get localSnapshotKeepProtectedNote =>
      'Последняя копия, содержащая данные, никогда не удаляется автоматически независимо от этой настройки.';

  @override
  String get localSnapshotMaximumTitle => 'Лимит места';

  @override
  String get localSnapshotMaximumUnlimited => 'Без лимита';

  @override
  String get localSnapshotAnnounceTitle => 'Уведомлять о сохранении копии';

  @override
  String get localSnapshotAnnounceSubtitle =>
      'Об ошибках сообщается всегда. Эта настройка добавляет короткое уведомление об успешном сохранении.';

  @override
  String get localSnapshotTakeNow => 'Сохранить копию сейчас';

  @override
  String get localSnapshotManageCopies => 'Управление копиями';

  @override
  String localSnapshotUsage(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count копии',
      many: '$count копий',
      few: '$count копии',
      one: '$count копия',
      zero: 'Нет копий',
    );
    return '$_temp0 · $size';
  }

  @override
  String get localSnapshotStatusNever => 'Копий ещё нет';

  @override
  String localSnapshotStatusSuccess(String when) {
    return 'Последняя копия: $when';
  }

  @override
  String localSnapshotStatusFailure(String when, String reason) {
    return 'Последняя попытка не удалась ($when): $reason';
  }

  @override
  String get localSnapshotStatusSkippedSpace =>
      'Пропущено: недостаточно свободного места на устройстве';

  @override
  String get localSnapshotStatusUnchanged =>
      'С момента последней копии ничего не изменилось';

  @override
  String get localSnapshotCopiesTitle => 'Локальные копии';

  @override
  String get localSnapshotCopiesEmpty => 'Локальных копий пока нет';

  @override
  String get localSnapshotCopiesEmptyHint =>
      'Копия сохраняется автоматически при изменении данных и всегда создаётся перед восстановлением.';

  @override
  String get localSnapshotCopiesScopeNote =>
      'Локальные копии хранятся только на этом устройстве. Они защищают от повреждения данных внутри приложения, но не от потери устройства или удаления Moru. Для этого используйте WebDAV или S3.';

  @override
  String get localSnapshotOriginAutomatic => 'Автоматически';

  @override
  String get localSnapshotOriginManual => 'Сохранено вами';

  @override
  String get localSnapshotOriginBeforeRestore => 'Перед восстановлением';

  @override
  String get localSnapshotKindRecovered => 'Сохранено при исправлении';

  @override
  String localSnapshotCopyContents(int conversations, int messages) {
    String _temp0 = intl.Intl.pluralLogic(
      conversations,
      locale: localeName,
      other: '$conversations чата',
      many: '$conversations чатов',
      few: '$conversations чата',
      one: '$conversations чат',
    );
    String _temp1 = intl.Intl.pluralLogic(
      messages,
      locale: localeName,
      other: '$messages сообщения',
      many: '$messages сообщений',
      few: '$messages сообщения',
      one: '$messages сообщение',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get localSnapshotCopyContentsUnknown =>
      'Содержимое станет известно после восстановления';

  @override
  String get localSnapshotCopyPinned => 'Сохраняется';

  @override
  String get localSnapshotActionRestore => 'Восстановить';

  @override
  String get localSnapshotActionExport => 'Экспорт';

  @override
  String get localSnapshotActionDelete => 'Удалить';

  @override
  String get localSnapshotActionPin => 'Сохранять эту копию';

  @override
  String get localSnapshotActionUnpin => 'Больше не сохранять';

  @override
  String get localSnapshotRestoreTitle => 'Восстановить эту копию?';

  @override
  String localSnapshotRestoreMessage(String when) {
    return 'Текущие чаты и настройки будут заменены копией от $when. Сначала сохраняется копия текущих данных, поэтому изменение можно отменить.';
  }

  @override
  String get localSnapshotRestorePreparing => 'Подготовка копии';

  @override
  String get localSnapshotDeleteTitle => 'Удалить эту копию?';

  @override
  String get localSnapshotDeleteMessage =>
      'Копия будет безвозвратно удалена с устройства. Её данные, которых нет в текущей базе, будут потеряны.';

  @override
  String get localSnapshotDeleteLastWarning =>
      'Это единственная копия, в которой ещё есть данные.';

  @override
  String get localSnapshotExportPreparing => 'Подготовка экспорта';

  @override
  String get localSnapshotExportDone => 'Копия экспортирована';

  @override
  String localSnapshotExportFailed(String reason) {
    return 'Не удалось экспортировать копию: $reason';
  }

  @override
  String get localSnapshotTakeDone => 'Копия сохранена';

  @override
  String localSnapshotTakeFailed(String reason) {
    return 'Не удалось сохранить копию: $reason';
  }

  @override
  String get localSnapshotDeleteDone => 'Копия удалена';

  @override
  String get localSnapshotBusyMessage =>
      'Другая задача резервного копирования уже выполняется';

  @override
  String get localSnapshotRunInBackground => 'Продолжить в фоне';

  @override
  String get localSnapshotRunningInBackground => 'Сохранение копии в фоне';

  @override
  String startupRecoveryLocalCopiesAvailable(int count, String when) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count копии',
      many: '$count копий',
      few: '$count копии',
      one: '$count копия',
    );
    return 'На устройстве остаются локальные копии: $_temp0. Последняя — от $when. Сброс не удаляет их. После перезапуска можно восстановить копию: Настройки › Резервное копирование › Локальные копии.';
  }

  @override
  String startupRecoveryRecoveredCopiesDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count копии',
      many: '$count копий',
      few: '$count копии',
      one: '$count копия',
    );
    return 'Также на устройстве есть копии базы, сохранённые при предыдущем исправлении: $_temp0. При сбросе они БУДУТ безвозвратно удалены. Чтобы сохранить их, сначала экспортируйте данные.';
  }

  @override
  String get toolSchemaSettingsPageTitle => 'Описания инструментов';

  @override
  String get toolSchemaSettingsGroupSearch => 'Поиск';

  @override
  String get toolSchemaSettingsGroupMemory => 'Память';

  @override
  String get toolSchemaSettingsGroupLocal => 'Инструменты устройства';

  @override
  String get toolSchemaSettingsModified => 'Изменено';

  @override
  String get toolSchemaSettingsResetDefault => 'Восстановить исходное';

  @override
  String get toolSchemaSettingsResetAll => 'Восстановить все исходные значения';

  @override
  String get toolSchemaSettingsResetAllTitle =>
      'Восстановить все исходные значения?';

  @override
  String get toolSchemaSettingsResetAllMessage =>
      'Описания всех встроенных инструментов будут заменены исходными. Ваши формулировки будут потеряны.';

  @override
  String get toolSchemaSettingsResetAllConfirm => 'Восстановить';

  @override
  String toolSchemaSettingsParamDescriptions(int count) {
    return 'Описания параметров ($count)';
  }

  @override
  String get toolSchemaSettingsMemoryLangNote =>
      'Исходные описания инструментов памяти соответствуют языку промптов памяти. Своё описание сохраняется для инструмента в одном экземпляре и не меняется при смене этого языка.';

  @override
  String get toolSchemaSettingsDescriptionLabel => 'Описание';

  @override
  String get toolSchemaSettingsToolName => 'Название инструмента';

  @override
  String get toolSchemaEditorPageTitle => 'Изменить описание';

  @override
  String get toolSchemaSettingsCancel => 'Отмена';

  @override
  String get workspaceFileNotAvailable => 'Файл недоступен';

  @override
  String get workspaceTerminalNotAvailable => 'Терминал недоступен';

  @override
  String get workspacePreviewCopyPath => 'Скопировать путь';

  @override
  String get workspacePreviewShare => 'Поделиться';

  @override
  String get workspacePreviewOpenExternally => 'Открыть во внешнем приложении';

  @override
  String get workspacePreviewOpenWith => 'Открыть с помощью…';

  @override
  String get workspacePreviewFileTooLarge =>
      'Файл слишком большой для предпросмотра. Откройте его во внешнем приложении.';

  @override
  String get workspacePreviewSource => 'Источник';

  @override
  String get workspacePreviewRendered => 'Представление';

  @override
  String get workspacePreviewFileName => 'Имя';

  @override
  String get workspacePreviewFileSize => 'Размер';

  @override
  String get workspacePreviewFileModified => 'Изменено';

  @override
  String get workspacePreviewPathCopied => 'Путь скопирован';

  @override
  String workspacePreviewLineCount(int count) {
    return 'Строк: $count';
  }

  @override
  String get workspaceFilesSort => 'Сортировка';

  @override
  String get workspaceFilesSortName => 'Имя';

  @override
  String get workspaceFilesSortModified => 'Изменено';

  @override
  String get workspaceFilesSortSize => 'Размер';

  @override
  String get workspaceFilesSortAscending => 'По возрастанию';

  @override
  String get workspaceFilesSortDescending => 'По убыванию';

  @override
  String get workspaceFilesShowHidden => 'Показывать скрытые файлы';

  @override
  String get workspaceFilesHideHidden => 'Скрыть скрытые файлы';

  @override
  String get workspaceFilesRefresh => 'Обновить';

  @override
  String get workspaceFilesNewFolder => 'Новая папка';

  @override
  String get workspaceFilesNewFile => 'Новый файл';

  @override
  String get workspaceFilesImport => 'Импорт';

  @override
  String get workspaceFilesExport => 'Экспорт';

  @override
  String get workspaceFilesExportFolder => 'Экспортировать папку';

  @override
  String get workspaceFilesEmpty => 'Эта папка пуста';

  @override
  String get workspaceFilesError => 'Не удалось загрузить файлы';

  @override
  String get workspaceFilesRetry => 'Повторить';

  @override
  String get workspaceFilesPreview => 'Предпросмотр';

  @override
  String get workspaceFilesRename => 'Переименовать';

  @override
  String get workspaceFilesMove => 'Переместить';

  @override
  String get workspaceFilesDelete => 'Удалить';

  @override
  String get workspaceFilesShare => 'Поделиться';

  @override
  String get workspaceFilesCopyPath => 'Скопировать путь';

  @override
  String get workspaceFilesExportItem => 'Экспорт';

  @override
  String get workspaceFilesNameLabel => 'Имя';

  @override
  String get workspaceFilesNameHint => 'Введите имя';

  @override
  String get workspaceFilesCreate => 'Создать';

  @override
  String get workspaceFilesCancel => 'Отмена';

  @override
  String get workspaceFilesConfirm => 'Подтвердить';

  @override
  String get workspaceFilesSave => 'Сохранить';

  @override
  String get workspaceFilesDeleteTitle => 'Удалить этот объект?';

  @override
  String workspaceFilesDeleteMessage(String name) {
    return 'Удалить $name?';
  }

  @override
  String workspaceFilesDeleteFolderMessage(String name) {
    return 'Удалить папку $name со всем содержимым?';
  }

  @override
  String get workspaceFilesMoveTitle => 'Переместить в папку';

  @override
  String get workspaceFilesMoveHere => 'Переместить сюда';

  @override
  String get workspaceFilesPathCopied => 'Путь скопирован';

  @override
  String get workspaceFilesInvalidName => 'Недопустимое название';

  @override
  String get workspaceFilesInvalidPath =>
      'Этот путь находится за пределами папки';

  @override
  String workspaceFilesOperationFailed(String error) {
    return 'Не удалось выполнить действие: $error';
  }

  @override
  String get workspaceFilesActions => 'Действия';

  @override
  String get workspaceFilesMore => 'Больше';

  @override
  String get workspaceFilesJustNow => 'Только что';

  @override
  String workspaceFilesMinutesAgo(int count) {
    return '$count мин назад';
  }

  @override
  String workspaceFilesHoursAgo(int count) {
    return '$count ч назад';
  }

  @override
  String workspaceFilesDaysAgo(int count) {
    return '$count дн. назад';
  }

  @override
  String get workspaceFilesPanelTitle => 'Файлы диалога';

  @override
  String get workspaceFilesTabAttachments => 'Вложения';

  @override
  String get workspaceFilesTabOutputs => 'Результаты';

  @override
  String get workspaceFilesTabWorkspace => 'Рабочее пространство';

  @override
  String get workspaceFilesNoWorkspaceBound =>
      'Рабочее пространство не привязано';

  @override
  String get workspaceFilesKindManaged => 'Управляемое';

  @override
  String get workspaceFilesKindLinked => 'Связано';

  @override
  String get workspaceFilesMissingWorkspace =>
      'Рабочее пространство не найдено';

  @override
  String get workspaceFilesClose => 'Закрыть';

  @override
  String get workspacesTitle => 'Рабочие пространства';

  @override
  String get workspacesCreate => 'Создать';

  @override
  String get workspacesCreateTitle => 'Новое рабочее пространство';

  @override
  String get workspacesNameLabel => 'Имя';

  @override
  String get workspacesNameHint => 'Название рабочего пространства';

  @override
  String get workspacesLinkFolder => 'Привязать папку';

  @override
  String get workspacesEmpty => 'Рабочих пространств пока нет';

  @override
  String get workspacesEmptyCta => 'Создать рабочее пространство';

  @override
  String get workspacesSettings => 'Настройки';

  @override
  String get workspacesOpenFiles => 'Открыть файлы';

  @override
  String get workspacesLastUsedNever => 'Ещё не использовалось';

  @override
  String workspacesLastUsed(String when) {
    return 'Последнее использование: $when';
  }

  @override
  String get workspacesDeleteTitle => 'Удалить это рабочее пространство?';

  @override
  String workspacesDeleteMessage(String name) {
    return 'Удалить рабочее пространство $name?';
  }

  @override
  String get workspacesDeleteAlsoFiles => 'Также удалить файлы';

  @override
  String get workspacesUnlinkTitle => 'Отвязать это рабочее пространство?';

  @override
  String workspacesUnlinkMessage(String name) {
    return 'Отвязать $name? Файлы на диске сохранятся.';
  }

  @override
  String get workspacesSettingsTitle => 'Настройки рабочего пространства';

  @override
  String get workspacesShellNeedsApproval =>
      'Спрашивать перед выполнением команд Shell';

  @override
  String get workspacesDefaultCwd => 'Рабочий каталог по умолчанию';

  @override
  String get workspacesDefaultCwdHint => 'Относительный путь, например src';

  @override
  String get workspacesDefaultCwdInvalid => 'Укажите относительный путь без ..';

  @override
  String get workspacesCreateManaged => 'Создать рабочее пространство';

  @override
  String get workspacesLinkExisting => 'Привязать существующую папку';

  @override
  String get workspacesUnlink => 'Отвязать';

  @override
  String get workspacesItemMore => 'Действия с рабочим пространством';

  @override
  String get workspaceToolDenied => 'Отклонено';

  @override
  String get workspaceToolTimeout => 'время ожидания истекло';

  @override
  String get workspaceToolCancelled => 'отменено';

  @override
  String get workspaceToolInterrupted => 'прервано';

  @override
  String get workspaceToolEnvironmentNotReady =>
      'Изолированная среда не установлена';

  @override
  String get workspaceToolInstall => 'Установить';

  @override
  String get workspaceToolFuzzy => 'неточное совпадение';

  @override
  String get workspaceToolCreated => 'создано';

  @override
  String get workspaceToolUpdated => 'обновлено';

  @override
  String get workspaceToolTruncated => 'обрезано';

  @override
  String get workspaceToolImageTag => 'изображение';

  @override
  String get workspaceToolAllowAll => 'Разрешить всё в этой сессии';

  @override
  String get workspaceToolStdout => 'stdout';

  @override
  String get workspaceToolStderr => 'stderr';

  @override
  String get workspaceToolOpenFullOutput => 'Открыть полный вывод';

  @override
  String get workspaceToolChangedFiles => 'Изменённые файлы';

  @override
  String get workspaceToolCancel => 'Отмена';

  @override
  String get workspaceToolCopyCommand => 'Скопировать команду';

  @override
  String get workspaceToolCopyOutput => 'Скопировать вывод';

  @override
  String get workspaceToolCopyDiff => 'Скопировать изменения';

  @override
  String get workspaceToolCopied => 'Скопировано';

  @override
  String get workspaceToolDiffTruncated => 'Список изменений обрезан';

  @override
  String get workspaceToolOpenPreview => 'Открыть предпросмотр';

  @override
  String get workspaceToolNoOutput => 'Нет вывода';

  @override
  String get workspaceToolNotAvailable => 'Недоступно';

  @override
  String get workspaceToolClose => 'Закрыть';

  @override
  String get workspaceToolTitleShell => 'Выполнить команду';

  @override
  String get workspaceToolTitleReadFile => 'Прочитать файл';

  @override
  String get workspaceToolTitleWriteFile => 'Записать файл';

  @override
  String get workspaceToolTitleEditFile => 'Изменить файл';

  @override
  String get workspaceToolTitleListDir => 'Содержимое каталога';

  @override
  String get workspaceToolTitleGlob => 'Поиск файлов по шаблону';

  @override
  String get workspaceToolTitleGrep => 'Поиск по содержимому';

  @override
  String workspaceToolCount(int count) {
    return '$count';
  }

  @override
  String workspaceToolMoreFiles(int count) {
    return '+$count';
  }

  @override
  String workspaceToolDurationMs(int ms) {
    return '$ms мс';
  }

  @override
  String workspaceToolDurationSec(String sec) {
    return '$sec с';
  }

  @override
  String get workspaceEnvTitle => 'Окружение';

  @override
  String workspaceEnvEngineUbuntu(String version) {
    return 'Ubuntu $version (PRoot)';
  }

  @override
  String workspaceEnvEngineAlpine(String version) {
    return 'Alpine $version (iSH)';
  }

  @override
  String get workspaceEnvEngineNative => 'Системная оболочка';

  @override
  String get workspaceEnvPhaseNotInstalled => 'Не установлено';

  @override
  String get workspaceEnvPhaseDownloading => 'Загрузка';

  @override
  String get workspaceEnvPhaseVerifying => 'Проверка';

  @override
  String get workspaceEnvPhaseExtracting => 'Распаковка';

  @override
  String get workspaceEnvPhasePatching => 'Применение исправлений';

  @override
  String get workspaceEnvPhaseReady => 'Готово';

  @override
  String get workspaceEnvPhaseError => 'Ошибка';

  @override
  String get workspaceEnvPhaseNeedsRestart => 'Требуется перезапуск';

  @override
  String workspaceEnvMetaLine(String version, String arch) {
    return '$version · $arch';
  }

  @override
  String workspaceEnvInstalledAt(String date) {
    return 'Установлено: $date';
  }

  @override
  String workspaceEnvDiskUsage(String size) {
    return 'Занято на диске: $size';
  }

  @override
  String workspaceEnvRuntimeReason(String reason) {
    return '$reason';
  }

  @override
  String get workspaceEnvInstall => 'Установить';

  @override
  String get workspaceEnvInstallSubtitleAndroid =>
      'Выберите Ubuntu, Alpine, Debian или импортируйте локальный образ rootfs.';

  @override
  String get workspaceEnvInstallSubtitleIos =>
      'Встроено, загрузка не требуется';

  @override
  String get workspaceEnvCancel => 'Отмена';

  @override
  String get workspaceEnvRetry => 'Повторить';

  @override
  String get workspaceEnvRepair => 'Исправить';

  @override
  String get workspaceEnvReset => 'Сбросить';

  @override
  String get workspaceEnvResetConfirmTitle => 'Сбросить среду?';

  @override
  String get workspaceEnvResetConfirmBody =>
      'Будут удалены установленные пакеты и файловая система изолированной среды.';

  @override
  String get workspaceEnvCheckForUpdate => 'Проверить обновления';

  @override
  String get workspaceEnvUpdate => 'Обновить';

  @override
  String workspaceEnvAvailableVersion(String version) {
    return 'Доступна версия $version';
  }

  @override
  String get workspaceEnvUpToDate => 'Установлена последняя версия';

  @override
  String get workspaceEnvRestartBanner => 'Перезапустите Moru для завершения';

  @override
  String get workspaceEnvDetectingMirrors => 'Поиск самых быстрых зеркал…';

  @override
  String workspaceEnvApplyingMirror(String category) {
    return 'Применение зеркала $category…';
  }

  @override
  String get workspaceEnvMirrorsSection => 'Зеркала';

  @override
  String get workspaceEnvUseMirror => 'Использовать зеркало';

  @override
  String get workspaceEnvDetect => 'Проверить';

  @override
  String get workspaceEnvOfficial => 'Официальное';

  @override
  String get workspaceEnvMirrorsDisabled =>
      'Зеркала меняются внутри изолированной среды. Дождитесь её готовности.';

  @override
  String workspaceEnvMirrorsDisabledReason(String reason) {
    return 'Изменение зеркал в изолированной среде недоступно: $reason';
  }

  @override
  String get workspaceEnvMirrorDetectTitle => 'Скорость зеркал';

  @override
  String workspaceEnvMirrorLatency(int ms) {
    return '$ms мс';
  }

  @override
  String workspaceEnvMirrorFailed(String reason) {
    return '$reason';
  }

  @override
  String get workspaceEnvErrorUnsupportedAbi =>
      'Архитектура этого устройства не поддерживается.';

  @override
  String get workspaceEnvErrorArchitectureMismatch =>
      'Архитектура установленной среды не соответствует приложению. Переустановите среду, чтобы продолжить. Существующие файлы среды сохранены.';

  @override
  String get workspaceEnvErrorProotMissing =>
      'Исполняемый файл PRoot отсутствует.';

  @override
  String get workspaceEnvErrorInsufficientDisk =>
      'Недостаточно свободного места для установки среды.';

  @override
  String get workspaceEnvErrorInsufficientDiskHint =>
      'Освободите место для выбранного образа и повторите попытку.';

  @override
  String get workspaceEnvErrorNetwork =>
      'Не удалось загрузить. Проверьте подключение и повторите попытку.';

  @override
  String get workspaceEnvErrorChecksumMismatch =>
      'Загруженный файл повреждён. Повторите попытку.';

  @override
  String get workspaceEnvErrorExtractFailed =>
      'Не удалось распаковать образ среды.';

  @override
  String get workspaceEnvErrorPatchFailed =>
      'Не удалось завершить настройку среды.';

  @override
  String get workspaceEnvErrorCancelled => 'Установка отменена.';

  @override
  String get workspaceEnvErrorGeneric =>
      'Ошибка установки изолированной среды.';

  @override
  String get workspaceEnvChipInstall => 'Установить среду';

  @override
  String workspaceEnvChipInstalling(int percent) {
    return 'Установка… $percent %';
  }

  @override
  String get workspaceEnvChipInstallingIndeterminate => 'Установка…';

  @override
  String get workspaceEnvChipError => 'Ошибка среды';

  @override
  String get workspaceEnvChipRestart => 'Требуется перезапуск';

  @override
  String get workspaceEnvNativeExplanation =>
      'На компьютере Moru использует системную оболочку вместо изолированной Linux-среды.';

  @override
  String workspaceEnvNativeShellPath(String path) {
    return 'Оболочка: $path';
  }

  @override
  String get workspaceEnvNativeShellApproval =>
      'Для инструмента Shell требуется подтверждение, если в этой сессии не разрешены все инструменты.';

  @override
  String workspaceEnvDownloadProgress(
    String downloaded,
    String total,
    int percent,
  ) {
    return '$downloaded / $total МБ ($percent%)';
  }

  @override
  String get workspaceEnvMirrorsFailed => 'Не удалось проверить зеркала';

  @override
  String get workspaceEnvCategoryApt => 'APT';

  @override
  String get workspaceEnvCategoryApk => 'APK';

  @override
  String get workspaceEnvCategoryPip => 'pip';

  @override
  String get workspaceEnvCategoryNpm => 'npm';

  @override
  String get skillsTitle => 'Навыки';

  @override
  String get skillsTab => 'Навыки';

  @override
  String get skillsSearchHint => 'Поиск навыков';

  @override
  String get skillsEmptyTitle => 'Навыков пока нет';

  @override
  String get skillsEmptyBody =>
      'Навык — папка с файлом SKILL.md. Импортируйте Markdown, файл .md или .zip либо укажите ссылку GitHub.';

  @override
  String get skillsEmptyFormat =>
      '---\nname: my-skill\ndescription: Что делает этот навык\n---\n\n# Инструкции';

  @override
  String get skillsImport => 'Импорт';

  @override
  String get skillsImportPaste => 'Вставить Markdown';

  @override
  String get skillsImportFile => 'Из файла';

  @override
  String get skillsImportGitHub => 'Из GitHub';

  @override
  String get skillsImportPasteLabel => 'SKILL.md';

  @override
  String get skillsImportPasteHint => 'Вставьте SKILL.md с заголовком YAML';

  @override
  String get skillsImportGitHubLabel => 'URL GitHub';

  @override
  String get skillsImportGitHubHint =>
      'github.com/owner/repo или github.com/owner/repo/tree/ref/path';

  @override
  String get skillsImportConfirm => 'Импорт';

  @override
  String get skillsCancel => 'Отмена';

  @override
  String get skillsSave => 'Сохранить';

  @override
  String skillsUsedCount(int count) {
    return 'использований: $count';
  }

  @override
  String get skillsEnabled => 'Включено';

  @override
  String get skillsBrowseFiles => 'Просмотреть файлы';

  @override
  String get skillsEdit => 'Изменить';

  @override
  String get skillsExport => 'Экспорт';

  @override
  String get skillsDelete => 'Удалить';

  @override
  String get skillsDeleteTitle => 'Удалить этот навык?';

  @override
  String skillsDeleteMessage(String name) {
    return 'Удалить $name? Отменить удаление нельзя.';
  }

  @override
  String get skillsUseAll => 'Использовать все навыки';

  @override
  String get skillsUseAllSubtitle =>
      'Все включённые навыки доступны этому ассистенту.';

  @override
  String get skillsDisabledHint =>
      'Чтобы использовать навык здесь, включите его в разделе «Навыки».';

  @override
  String get skillsOpenPage => 'Управление навыками';

  @override
  String get skillsInheritAssistant => 'Наследовать от ассистента';

  @override
  String get skillsInheritAssistantSubtitle =>
      'Использовать те же навыки, что и у ассистента этого диалога.';

  @override
  String get skillsActiveLabel => 'Активен';

  @override
  String get skillsSessionTitle => 'Навыки для этого чата';

  @override
  String get skillsEditTitle => 'Изменить навык';

  @override
  String get skillsDetailKindLabel => 'Навык';

  @override
  String get skillsNoEnabled => 'Нет включённых навыков';

  @override
  String get terminalTitle => 'Терминал';

  @override
  String get terminalOpenInSystem => 'Открыть в системном терминале';

  @override
  String get terminalHostDirectory => 'Каталог основной системы';

  @override
  String get terminalBindWorkspaceFirst =>
      'Сначала привяжите рабочее пространство';

  @override
  String get terminalNotAvailable => 'Недоступно';

  @override
  String get terminalRuntimeUnavailable => 'Среда терминала не готова';

  @override
  String get terminalRename => 'Переименовать';

  @override
  String get terminalClose => 'Закрыть';

  @override
  String get terminalClear => 'Очистить';

  @override
  String get terminalCloseSession => 'Закрыть сессию';

  @override
  String get terminalCopy => 'Копировать';

  @override
  String get terminalPaste => 'Вставить';

  @override
  String get terminalNewSession => 'Новая сессия';

  @override
  String get terminalMore => 'Больше';

  @override
  String get terminalNameLabel => 'Имя';

  @override
  String get terminalCancel => 'Отмена';

  @override
  String get terminalSave => 'Сохранить';

  @override
  String get workspaceDeskMenuWorkspace => 'Рабочее пространство';

  @override
  String get workspaceDeskMenuSkills => 'Навыки';

  @override
  String get workspaceDeskBarTitle => 'Рабочее пространство';

  @override
  String get workspaceDeskBarNoWorkspace => 'Нет рабочего пространства';

  @override
  String get workspaceDeskBarEmptyHint =>
      'Привяжите рабочее пространство на панели инструментов для просмотра файлов';

  @override
  String get workspaceDeskBarToggle => 'Файлы рабочего пространства';

  @override
  String get workspaceDeskOpenSystemTerminal => 'Открыть в системном терминале';

  @override
  String get workspaceDeskReveal => 'Показать в файловом менеджере';

  @override
  String get workspaceDeskBarClose => 'Закрыть панель рабочего пространства';

  @override
  String get workspaceEntryBind => 'Привязать рабочее пространство';

  @override
  String get workspaceEntryUnbind => 'Отвязать';

  @override
  String get workspaceEntryChange => 'Изменить';

  @override
  String get workspaceEntrySetAssistantDefault => 'По умолчанию для ассистента';

  @override
  String get workspaceEntryLocked => 'Заблокировано';

  @override
  String get workspaceEntryChangeConfirmTitle =>
      'Сменить рабочее пространство?';

  @override
  String get workspaceEntryUnbindConfirmTitle => 'Отвязать?';

  @override
  String get workspaceEntryChangeConfirmBody =>
      'В этом диалоге уже использовались инструменты рабочего пространства. Ссылки на файлы в предыдущих сообщениях могут перестать работать.';

  @override
  String get workspaceEntryCwd => 'Рабочий каталог';

  @override
  String get workspaceEntryCwdHint =>
      'Относительно корня рабочего пространства';

  @override
  String get workspaceEntryCwdInvalid =>
      'Путь некорректен или выходит за пределы рабочего пространства';

  @override
  String get workspaceEntryCwdMissing => 'Такой каталог не существует';

  @override
  String get workspaceEntryCwdCreate => 'Создать';

  @override
  String get workspaceEntryFiles => 'Файлы';

  @override
  String get workspaceEntryTerminal => 'Терминал';

  @override
  String get workspaceEntryOpenSystemTerminal =>
      'Открыть в системном терминале';

  @override
  String get workspaceEntryReveal => 'Показать в файловом менеджере';

  @override
  String get workspaceEntrySessionSkills => 'Навыки';

  @override
  String get workspaceEntryAllowAll => 'Разрешить всё в этой сессии';

  @override
  String get workspaceEntryAllowAllSubtitle =>
      'Команды Shell в этом диалоге будут выполняться без подтверждения.';

  @override
  String get workspaceEntryEnvironment => 'Окружение';

  @override
  String get workspaceEntryManage => 'Управление рабочими пространствами';

  @override
  String get workspaceEntryCreate => 'Создать рабочее пространство…';

  @override
  String get workspaceEntryDefaultWorkspace =>
      'Рабочее пространство по умолчанию';

  @override
  String get workspaceEntryDefaultWorkspaceSubtitle =>
      'Новые диалоги с этим ассистентом будут привязаны к этому рабочему пространству.';

  @override
  String get workspaceEntryNone => 'Нет';

  @override
  String get workspaceEntryStartConversationFirst => 'Сначала начните диалог';

  @override
  String get workspaceEntryTooltip => 'Рабочее пространство';

  @override
  String get workspaceEntryPickerTitle => 'Выберите рабочее пространство';

  @override
  String get settingsPageWorkspace => 'Рабочее пространство и среда';

  @override
  String get settingsPageSkills => 'Навыки';

  @override
  String get commonClose => 'Закрыть';

  @override
  String get terminalCopyAllOutput => 'Скопировать весь вывод';

  @override
  String get terminalFontDecrease => 'Уменьшить шрифт';

  @override
  String get terminalFontIncrease => 'Увеличить шрифт';

  @override
  String get terminalCloseSessionConfirmMessage =>
      'Сессия ещё выполняется. При закрытии процесс будет завершён.';

  @override
  String get terminalCopiedAll => 'Весь вывод скопирован';

  @override
  String get terminalConfirm => 'Подтвердить';

  @override
  String terminalExitCode(int code) {
    return 'код выхода: $code';
  }

  @override
  String get workspaceMgmtNewWorkspace => 'Новое рабочее пространство';

  @override
  String get workspaceMgmtEmptyHint =>
      'Создайте рабочее пространство, чтобы хранить файлы проекта вместе.';

  @override
  String get workspaceMgmtKindManagedTitle =>
      'Управляемое рабочее пространство';

  @override
  String get workspaceMgmtKindManagedSubtitle =>
      'Папка приложения с доступом на чтение и запись из среды';

  @override
  String get workspaceMgmtKindLinkedTitle => 'Привязанная папка';

  @override
  String get workspaceMgmtKindLinkedSubtitle =>
      'Использовать папку на этом компьютере';

  @override
  String get workspaceMgmtImportFromFolder => 'Импортировать из папки';

  @override
  String get workspaceMgmtImportFromFolderSubtitle =>
      'Скопировать папку в новое управляемое рабочее пространство';

  @override
  String get workspaceMgmtKindSection => 'Тип';

  @override
  String get workspaceMgmtCreate => 'Создать';

  @override
  String get workspaceMgmtShellApprovalSubtitle =>
      'Спрашивать перед каждой командой';

  @override
  String get workspaceMgmtDefaultCwdRoot => '/';

  @override
  String get workspaceMgmtPickCwdTitle => 'Рабочий каталог по умолчанию';

  @override
  String get workspaceMgmtFolderPickerUnavailable => 'Выбор папки недоступен.';

  @override
  String get workspaceMgmtImportProgressTitle => 'Импорт папки';

  @override
  String get workspaceMgmtImportProgressPhase => 'Копирование файлов…';

  @override
  String get workspaceMgmtImportFailed => 'Не удалось импортировать папку.';

  @override
  String workspaceMgmtImportDone(String name) {
    return 'Импортировано: $name';
  }

  @override
  String get workspaceMgmtLastUsedJustNow => 'только что';

  @override
  String workspaceMgmtLastUsedMinutesAgo(int n) {
    return '$n мин назад';
  }

  @override
  String workspaceMgmtLastUsedHoursAgo(int n) {
    return '$n ч назад';
  }

  @override
  String workspaceMgmtLastUsedDaysAgo(int n) {
    return '$n дн. назад';
  }

  @override
  String workspaceMgmtRowDetail(String kind, String when) {
    return '$kind · Последнее использование: $when';
  }

  @override
  String workspaceMgmtRowDetailNever(String kind) {
    return '$kind · Ещё не использовалось';
  }

  @override
  String get workspacePreviewBack => 'Назад';

  @override
  String get workspacePreviewWrap => 'Переносить строки';

  @override
  String get workspacePreviewFontDecrease => 'Уменьшить текст';

  @override
  String get workspacePreviewFontIncrease => 'Увеличить текст';

  @override
  String get workspacePreviewCopy => 'Копировать';

  @override
  String get workspacePreviewRetry => 'Повторить';

  @override
  String get workspacePreviewLoadError => 'Не удалось загрузить файл.';

  @override
  String get workspacePreviewRevealInFinder => 'Показать в Finder';

  @override
  String get workspacePreviewOpenInSystemApp => 'Открыть системным приложением';

  @override
  String get workspacePreviewOpenInBrowser => 'Открыть в браузере';

  @override
  String get workspacePreviewTable => 'Таблица';

  @override
  String get workspacePreviewPlainLanguage => 'Код';

  @override
  String get workspacePreviewOpen => 'Открыть';

  @override
  String get workspacePreviewRevealFailed =>
      'Не удалось показать файл в файловом менеджере.';

  @override
  String get workspacePreviewEmptyTable => 'Эта таблица пуста.';

  @override
  String get workspaceFilesNew => 'Создать';

  @override
  String get workspaceFilesFoldersFirst => 'Сначала папки';

  @override
  String get workspaceFilesSelectDirectory => 'Выбрать эту папку';

  @override
  String get workspaceFilesEmptyHint =>
      'Используйте создание или импорт для добавления файлов';

  @override
  String get workspaceFilesEmptyAttachments => 'Вложений пока нет';

  @override
  String get workspaceFilesEmptyOutputs => 'Ассистент ещё не создал файлы';

  @override
  String get workspaceFilesMoveTo => 'Переместить в…';

  @override
  String workspaceFilesItemCount(int count) {
    return 'Объектов: $count';
  }

  @override
  String get skillsImportTooltip => 'Импортировать навык';

  @override
  String get skillsImportPasteSubtitle => 'Вставьте SKILL.md с заголовком YAML';

  @override
  String get skillsImportFileSubtitle => 'Выберите файл .md или .zip';

  @override
  String get skillsImportGitHubSubtitle =>
      'Импортировать SKILL.md из репозитория';

  @override
  String get skillsImportResolving => 'Поиск репозитория…';

  @override
  String get skillsImportDownloading => 'Загрузка…';

  @override
  String get skillsImportExtracting => 'Распаковка…';

  @override
  String get skillsImportInstalling => 'Установка…';

  @override
  String get skillsImportGitHubRepoLabel => 'URL репозитория';

  @override
  String get skillsImportGitHubUrlHint =>
      'https://github.com/owner/repo или owner/repo[/path]';

  @override
  String get skillsImportGitHubHelp =>
      'Поддерживается SKILL.md в корне репозитория или в подпапке.';

  @override
  String get skillsEmptyHint =>
      'Навык — файл SKILL.md с заголовком параметров. После импорта ассистент сможет использовать его по необходимости.';

  @override
  String get skillsMoreActions => 'Больше';

  @override
  String get skillsSearchClear => 'Очистить';

  @override
  String get skillsSessionEmpty =>
      'Включённых навыков пока нет. Сначала включите их в библиотеке.';

  @override
  String get workspaceToolRunning => 'Выполняется';

  @override
  String workspaceToolExitCode(int code) {
    return 'код выхода: $code';
  }

  @override
  String get workspaceToolAwaitingApproval => 'Ожидание разрешения';

  @override
  String get workspaceToolCompleted => 'Готово';

  @override
  String workspaceToolLines(int count) {
    return 'Строк: $count';
  }

  @override
  String workspaceToolItems(int count) {
    return 'Объектов: $count';
  }

  @override
  String workspaceToolFileMatches(int count) {
    return 'Совпадений: $count';
  }

  @override
  String workspaceToolContentMatches(int count) {
    return 'Совпадений: $count';
  }

  @override
  String get workspaceToolExpand => 'Развернуть';

  @override
  String get workspaceToolSectionCommand => 'Команда';

  @override
  String get workspaceToolSectionPath => 'Путь';

  @override
  String get workspaceToolSectionPattern => 'Шаблон';

  @override
  String get workspaceToolSectionOutput => 'Вывод';

  @override
  String get workspaceToolSectionDiff => 'Изменения';

  @override
  String get workspaceToolSectionError => 'Ошибка';

  @override
  String get workspaceToolSavedOutput => 'Полный вывод сохранён';

  @override
  String get workspaceToolApprove => 'Разрешить';

  @override
  String get workspaceToolDeny => 'Отклонить';

  @override
  String get workspaceToolCopy => 'Копировать';

  @override
  String get workspaceEnvEngineLocalShell => 'Локальная оболочка';

  @override
  String get workspaceEnvInstallEnvironment => 'Установить среду';

  @override
  String get workspaceEnvInstallDescription =>
      'Установите Linux-среду для выполнения инструментов в изолированном окружении.';

  @override
  String get workspaceEnvStatusLabel => 'Статус';

  @override
  String get workspaceEnvStatusInstalled => 'Установлено';

  @override
  String get workspaceEnvSizeLabel => 'Размер';

  @override
  String get workspaceEnvPathLabel => 'Путь';

  @override
  String get workspaceEnvInstalledAtLabel => 'Установлено';

  @override
  String get workspaceEnvArchLabel => 'Архитектура';

  @override
  String workspaceEnvArchVersion(String arch, String version) {
    return '$arch · $version';
  }

  @override
  String get workspaceEnvBrowseSection => 'Просмотр';

  @override
  String get workspaceEnvBrowseFiles => 'Просмотр файловой системы';

  @override
  String get workspaceEnvBrowseFilesDetail =>
      'Полное дерево каталогов внутри изолированной среды';

  @override
  String get workspaceEnvDetectFastMirrors => 'Найти быстрые зеркала';

  @override
  String get workspaceEnvActionsSection => 'Действия';

  @override
  String get workspaceEnvInfoSection => 'Информация';

  @override
  String get workspaceEnvInfoBody =>
      'Среда — корневая файловая система Linux для изолированного выполнения. Рабочие пространства хранятся отдельно и не удаляются при сбросе среды. Файлы находятся в распакованном rootfs на этом устройстве.';

  @override
  String get workspaceEnvRepairDetail => 'Повторно проверить и исправить файлы';

  @override
  String get workspaceEnvUpdateCurrent => 'Установлена последняя версия';

  @override
  String workspaceEnvUpdateAvailableShort(String version) {
    return 'Доступно обновление: $version';
  }

  @override
  String get workspaceEnvResetConfirmMessage =>
      'Будут удалены вся Linux-среда и установленные в ней пакеты. Файлы рабочих пространств не пострадают.';

  @override
  String get workspaceEnvRestartDoneBanner =>
      'Сброс завершён. Перезапустите приложение, чтобы завершить установку.';

  @override
  String get workspaceEnvPathCopied => 'Путь скопирован';

  @override
  String get workspaceEnvUseMirrorSubtitle =>
      'Записать выбранное зеркало в настройки среды';

  @override
  String get workspaceEnvRegionGlobal => 'Общая';

  @override
  String get workspaceEnvRegionChina => 'Китай';

  @override
  String get workspaceEnvRegionEurope => 'Европа';

  @override
  String get workspaceEnvRegionAsia => 'Азия';

  @override
  String get workspaceEnvMirrorTimeout => 'Время ожидания истекло';

  @override
  String get workspaceEnvSpeedTest => 'Проверить скорость';

  @override
  String get workspaceEnvApplySuccess => 'Зеркало применено';

  @override
  String get workspaceEnvApplyFailed => 'Не удалось применить зеркало';

  @override
  String get workspaceEnvRestoreSuccess => 'Официальный источник восстановлен';

  @override
  String get workspaceEnvMirrorsTested => 'Самые быстрые зеркала применены';

  @override
  String get workspaceEnvRelativeJustNow => 'Только что';

  @override
  String workspaceEnvRelativeMinutesAgo(int count) {
    return '$count мин назад';
  }

  @override
  String workspaceEnvRelativeHoursAgo(int count) {
    return '$count ч назад';
  }

  @override
  String workspaceEnvRelativeDaysAgo(int count) {
    return '$count дн. назад';
  }

  @override
  String workspaceEnvDownloadLine(
    String downloaded,
    String total,
    String phase,
  ) {
    return '$downloaded / $total · $phase';
  }

  @override
  String get workspaceEnvNativeUnsandboxed =>
      'Команды выполняются на этом компьютере, а не в изолированной среде. Для них требуется подтверждение, если в сессии не разрешены все инструменты.';

  @override
  String get workspaceEnvRootfsTitle => '/';

  @override
  String get workspaceEnvBrowserUnavailable =>
      'Файловая система среды недоступна.';

  @override
  String get workspaceEnvMirrorNameOfficial => 'Официальное';

  @override
  String get workspaceEnvMirrorNameOfficialCdn => 'Официальный CDN';

  @override
  String get workspaceEnvMirrorNameOfficialPypi => 'Официальный PyPI';

  @override
  String get workspaceEnvMirrorNameOfficialNpm => 'Официальный npm';

  @override
  String get workspaceEnvMirrorNameTuna => 'Tsinghua TUNA';

  @override
  String get workspaceEnvMirrorNameAlibaba => 'Alibaba';

  @override
  String get workspaceEnvMirrorNameUstc => 'USTC';

  @override
  String get workspaceEnvMirrorNameHuawei => 'Huawei';

  @override
  String get workspaceEnvMirrorNameTencent => 'Tencent';

  @override
  String get workspaceEnvMirrorNameNetease => 'NetEase';

  @override
  String get workspaceEnvMirrorNameLeaseweb => 'LEASEWEB (Великобритания)';

  @override
  String get workspaceEnvMirrorNameRwth => 'RWTH (Германия)';

  @override
  String get workspaceEnvMirrorNameJaist => 'JAIST (Япония)';

  @override
  String get workspaceEnvMirrorNameKakao => 'Kakao (Корея)';

  @override
  String get workspaceEnvMirrorNameNpmmirror => 'npmmirror';

  @override
  String workspaceEnvSelectionNamed(String name, String region) {
    return '$name · $region';
  }

  @override
  String get workspaceFilesEmptyPickerHint =>
      'Нажмите «Новая папка», чтобы добавить подпапку';

  @override
  String get skillsDetailBodyEmpty => 'Содержимого навыка пока нет';

  @override
  String skillsDetailBodyTooLarge(String size) {
    return 'Файл слишком большой для предпросмотра ($size).';
  }

  @override
  String get workspaceEnvSizeTimeout => 'Время ожидания истекло';

  @override
  String get workspaceEnvInfoCopied => 'Информация о среде скопирована';

  @override
  String get workspacePreviewEmptyFile => 'Этот файл пуст';

  @override
  String get workspacePreviewEmptyHint => 'Нет содержимого для предпросмотра.';

  @override
  String get workspacePreviewRevealInExplorer => 'Показать в Проводнике';

  @override
  String get workspacePreviewRevealInFileManager =>
      'Показать в файловом менеджере';

  @override
  String workspaceBindingSetAssistantDefault(String assistant) {
    return 'Рабочее пространство по умолчанию для «$assistant»';
  }

  @override
  String get storageSpaceCategoryWorkspaceFiles =>
      'Файлы рабочего пространства';

  @override
  String get storageSpaceCategoryWorkspaceFilesHint =>
      'Файлы в управляемых рабочих пространствах.';

  @override
  String get storageSpaceCategorySandboxEnvironment => 'Изолированная среда';

  @override
  String get storageSpaceCategorySandboxEnvironmentHint =>
      'Установка среды и корневая файловая система.';

  @override
  String get storageSpaceCategorySkills => 'Навыки';

  @override
  String get storageSpaceCategorySkillsHint => 'Файлы установленных навыков.';

  @override
  String get storageSpaceCategorySessionFiles => 'Файлы диалога';

  @override
  String get storageSpaceCategorySessionFilesHint =>
      'Вложения и результаты отдельных диалогов.';

  @override
  String get storageSpaceManageSkills => 'Управление навыками';

  @override
  String get storageSessionFilesCleanOrphans =>
      'Удалить файлы удалённых диалогов';

  @override
  String storageSessionFilesCleanOrphansHint(String size) {
    return 'Удаляет папки сессий, для которых больше нет диалога. Можно освободить: $size.';
  }

  @override
  String get workspaceDesktopFolderPath => 'Путь к папке';

  @override
  String get workspaceDesktopFolderMissing =>
      'Выберите существующую папку или введите абсолютный путь.';

  @override
  String get workspaceDesktopManagedHint =>
      'Moru создаёт папку для этого проекта и управляет ею.';

  @override
  String get workspaceDesktopHostHint =>
      'Файлы и команды используют этот компьютер.';

  @override
  String get workspaceDesktopSearch => 'Поиск рабочих пространств';

  @override
  String get workspaceDesktopNoResults => 'Подходящих рабочих пространств нет';

  @override
  String get workspaceEnvDependencies => 'Наборы инструментов среды';

  @override
  String get workspaceEnvDependenciesDetail =>
      'Установка инструментов в общую среду. Они доступны всем рабочим пространствам.';

  @override
  String get workspaceEnvDependencyPython =>
      'Python, pip и виртуальные окружения';

  @override
  String get workspaceEnvDependencyNode => 'Node.js и npm';

  @override
  String get workspaceEnvDependencyGit =>
      'Клонирование репозиториев и управление версиями';

  @override
  String get workspaceEnvDependencySsh => 'SSH, SCP, SFTP и создание ключей';

  @override
  String get workspaceEnvDependencyNetwork => 'Сетевые инструменты';

  @override
  String get workspaceEnvDependencyArchive => 'Архиваторы';

  @override
  String get workspaceEnvDependencyInstalled => 'Установлено';

  @override
  String get workspaceEnvDependencyUnknown => 'Не проверено';

  @override
  String get workspaceEnvDependencyChecking => 'Проверка инструментов…';

  @override
  String get workspaceEnvDependencyInstalling => 'Установка…';

  @override
  String get workspaceEnvDependencyCheckFailed =>
      'Не удалось проверить инструменты. Нажмите обновление для повторной попытки.';

  @override
  String get workspaceEnvDependencyInstallFailed =>
      'Установка не завершена. Проверьте журнал или смените источник пакетов и повторите попытку.';

  @override
  String get workspaceEnvDependencyLog => 'Журнал установки';

  @override
  String get workspaceEnvDependencyRefresh => 'Обновить состояние инструментов';

  @override
  String get workspaceEnvDependencyReadyFirst =>
      'Сначала установите среду, чтобы добавить эти инструменты.';

  @override
  String get workspaceEnvDependencySources => 'Источники пакетов';

  @override
  String get workspaceEnvDependencySourcesDetail =>
      'Для установки используется выбранный источник apt/apk. Источники pip и npm применяются к пакетам, устанавливаемым позднее.';

  @override
  String get workspaceEnvDownloadSource => 'Источник загрузки среды';

  @override
  String get workspaceEnvDownloadAutomatic => 'Автовыбор самого быстрого';

  @override
  String get workspaceEnvDownloadAutomaticDetail =>
      'Проверить официальный источник и встроенные зеркала перед загрузкой.';

  @override
  String get workspaceEnvDownloadCustom => 'Свой URL';

  @override
  String get workspaceEnvDownloadCustomHint =>
      'https://example.com/ubuntu-base/releases/24.04/release/';

  @override
  String get workspaceEnvDownloadCustomDetail =>
      'Введите URL каталога релиза или полного архива. Архив должен соответствовать выбранной системе, версии и архитектуре устройства.';

  @override
  String get workspaceEnvDownloadInvalidUrl =>
      'Введите корректный URL HTTP или HTTPS.';

  @override
  String get workspaceEnvDownloadVerified =>
      'Загружаемые файлы проверяются по официальной SHA-256 выбранного образа. Источники пакетов настраиваются отдельно.';

  @override
  String get workspaceEnvDownloadStart => 'Скачать и установить';

  @override
  String get workspaceEnvDownloadSave => 'Сохранить источник';

  @override
  String get workspaceToolsTitle => 'Инструменты';

  @override
  String get workspaceToolsDescription =>
      'Выберите инструменты, доступные диалогам в этом рабочем пространстве. Изменения сохраняются автоматически.';

  @override
  String get workspaceToolHelpShell =>
      'Выполнение команд в среде рабочего пространства.';

  @override
  String get workspaceToolHelpRead =>
      'Чтение файлов с номерами строк и постраничным выводом.';

  @override
  String get workspaceToolHelpWrite =>
      'Создание файлов или перезапись их содержимого.';

  @override
  String get workspaceToolHelpEdit =>
      'Замена указанного текста в существующем файле.';

  @override
  String get workspaceToolHelpList => 'Просмотр каталогов и их содержимого.';

  @override
  String get workspaceToolHelpGlob => 'Поиск файлов по имени или шаблону пути.';

  @override
  String get workspaceToolHelpGrep => 'Поиск текста внутри файлов.';

  @override
  String get workspaceEnvVariablesTitle => 'Переменные окружения';

  @override
  String get workspaceEnvVariablesEntryDetail =>
      'Переменные команд и настройки сокрытия значений в выводе';

  @override
  String get workspaceEnvVariablesEmpty =>
      'Переменных пока нет. Добавьте API-ключи или другие настройки инструментов.';

  @override
  String get workspaceEnvVariablesScope =>
      'Общие для всех рабочих пространств. Изменения применяются к новым командам агента и новым сессиям встроенного терминала; существующие сессии нужно открыть заново. Внешние системные терминалы используют своё окружение.';

  @override
  String get workspaceEnvPrivacyMode => 'Режим конфиденциальности';

  @override
  String get workspaceEnvPrivacyDetail =>
      'Команды используют настоящие значения. Перед отправкой вывода инструментов модели совпадающие значения длиной от 5 символов заменяются на [REDACTED]. Локальные журналы не меняются. Короткие значения не скрываются, чтобы не заменять обычные флаги и числа.';

  @override
  String get workspaceEnvVariableAdd => 'Добавить переменную';

  @override
  String get workspaceEnvVariableEdit => 'Изменить переменную';

  @override
  String get workspaceEnvVariableName => 'Имя';

  @override
  String get workspaceEnvVariableValue => 'Значение';

  @override
  String get workspaceEnvVariableNote => 'Примечание (необязательно)';

  @override
  String get workspaceEnvVariableNameHint =>
      'Используйте буквы, цифры и подчёркивания; не начинайте с цифры. Имена чувствительны к регистру. В командах обращайтесь к переменным как \$NAME.';

  @override
  String get workspaceEnvVariableInvalidName =>
      'Введите корректное имя переменной.';

  @override
  String get workspaceEnvVariableInvalidValue =>
      'Введите непустое значение без символов NUL.';

  @override
  String get workspaceEnvVariableDuplicate =>
      'Переменная с таким именем уже существует.';

  @override
  String get workspaceEnvVariablesSaveFailed =>
      'Не удалось сохранить настройки окружения. Повторите попытку.';

  @override
  String get incomingShareTitle => 'Полученное содержимое';

  @override
  String get incomingShareReplaceDraft =>
      'В поле ввода есть неотправленный текст. Заменить его полученным содержимым в новом чате?';

  @override
  String get incomingShareFailed =>
      'Часть полученного содержимого не удалось импортировать. Проверьте доступ к файлам и свободное место. За один раз можно передать до 32 файлов.';

  @override
  String get incomingShareImporting => 'Импорт';

  @override
  String get incomingShareMoveTo => 'Переместить в…';

  @override
  String get incomingShareNewChat => 'Новый диалог';

  @override
  String get incomingShareMoveHint =>
      'Переместите черновик и вложения в другой диалог. Ничего не будет отправлено автоматически.';

  @override
  String get incomingShareNoConversations => 'Подходящих диалогов нет';

  @override
  String get chatInputBarRemoveAttachment => 'Удалить вложение';

  @override
  String get incomingShareMoveFailed =>
      'Не удалось сменить диалог. Черновик сохранён.';

  @override
  String attachmentRequiresWorkspace(String name) {
    return 'Чтобы использовать «$name», привяжите рабочее пространство и включите файловые инструменты либо переместите черновик в диалог с рабочим пространством. В обычном чате этот файл прочитать нельзя.';
  }

  @override
  String get storageSessionFilesUnlinked => 'Непривязанный диалог';

  @override
  String get workspaceExternalMount => 'Подключить внешнюю папку';

  @override
  String get workspaceExternalMountSubtitle =>
      'Выбранные папки подключаются по пути /mounts/<name> и доступны всем рабочим пространствам. ИИ-инструменты, Shell и файловый менеджер могут обращаться к ним. До 10 папок.';

  @override
  String get workspaceExternalStorageTitle => 'Разрешить доступ к файлам';

  @override
  String get workspaceExternalStorageMessage =>
      'Чтобы читать и записывать внешние папки из рабочего пространства и Shell, разрешите Moru управлять файлами в настройках Android. На Android 11 и новее включите доступ ко всем файлам. Затем выберите папку на устройстве для подключения.';

  @override
  String get workspaceExternalGrantAccess => 'Предоставить доступ';

  @override
  String get workspaceExternalLocalOnly =>
      'На Android можно подключать только папки на устройстве. Этот поставщик документов не предоставляет локальную папку для Shell.';

  @override
  String get workspaceExternalUnavailable =>
      'Внешняя папка недоступна. Проверьте подключение накопителя и разрешения, затем выберите папку заново, чтобы восстановить доступ.';

  @override
  String get workspaceExternalReconnect => 'Выбрать папку заново';

  @override
  String get workspaceMountAdd => 'Добавить папку';

  @override
  String get workspaceMountEdit => 'Изменить подключение';

  @override
  String get workspaceMountEmpty => 'Нет подключённых папок';

  @override
  String get workspaceMountReadOnly => 'Только чтение';

  @override
  String get workspaceMountReadWrite => 'Чтение и запись';

  @override
  String get workspaceMountAllowWrite => 'Разрешить запись';

  @override
  String get workspaceMountPermissionsHint =>
      'Файловые ИИ-инструменты и файловый менеджер соблюдают эту настройку. Защита Shell охватывает обычные файловые команды; произвольные скрипты могут её обойти. Сохранение подключений останавливает выполняемые команды и сессии терминала.';

  @override
  String get workspaceMountBrowse => 'Просмотреть файлы';

  @override
  String get workspaceMountUnmount => 'Отключить папку';

  @override
  String get workspaceMountUnmountMessage =>
      'Отключить эту папку? Исходная папка и её файлы сохранятся.';

  @override
  String get workspaceMountInactive => 'Недоступно — выберите папку заново';

  @override
  String get workspaceMountInvalidName =>
      'Название должно содержать до 64 символов без слешей, двоеточий и управляющих символов. Не используйте . или ..';

  @override
  String get workspaceMountDuplicate =>
      'Подключение с таким названием уже существует.';

  @override
  String get workspaceMountLimit =>
      'Можно подключить до 10 папок. Удалите одно подключение перед добавлением нового.';

  @override
  String get workspaceMountOverlap =>
      'Эта папка пересекается с уже подключённой. Выберите другую, чтобы разрешения не противоречили друг другу.';

  @override
  String get workspaceMountTargetOccupied =>
      'В целевом каталоге внутри /mounts уже есть локальные файлы. Выберите другое имя подключения или сначала переместите файлы. Ничего не удалено.';

  @override
  String get workspaceEnvSystemImage => 'Образ системы';

  @override
  String get workspaceEnvDistribution => 'Дистрибутив';

  @override
  String get workspaceEnvSystemVersion => 'Версия';

  @override
  String get workspaceEnvLocalImage => 'Локальный образ';

  @override
  String get workspaceEnvChooseImage => 'Выбрать архив rootfs';

  @override
  String get workspaceEnvLocalImageHint =>
      'Импортируйте архив корневой файловой системы (.tar.gz, .tar.xz или .tar), а не ISO или образ диска. Он должен соответствовать архитектуре процессора и содержать /bin/sh. Система и версия определяются после распаковки.';

  @override
  String get workspaceEnvImportImage => 'Импортировать образ';

  @override
  String get workspaceEnvInvalidImage =>
      'Выберите подходящий архив rootfs для устройства. Он должен содержать исполняемый /bin/sh для нужной архитектуры процессора.';

  @override
  String get workspaceEnvReplaceSystem => 'Заменить систему';

  @override
  String get workspaceEnvReplaceSystemHint =>
      'Будут заменены установленные пакеты и файлы текущей среды, а её команды и сессии терминала — остановлены. Рабочие пространства, файлы чатов и внешние папки сохранятся. Если подготовка нового образа завершится ошибкой, текущая среда останется нетронутой.';

  @override
  String get workspaceEnvProotOptions => 'Параметры PRoot';

  @override
  String get workspaceEnvShellPath => 'Путь к оболочке';

  @override
  String get workspaceEnvShellAutomatic => 'Автоматически';

  @override
  String get workspaceEnvShellHint =>
      'Оставьте пустым для /bin/bash, если он доступен, иначе используется /bin/sh. Своя оболочка указывается абсолютным путём внутри среды.';

  @override
  String get workspaceEnvProotArguments => 'Дополнительные аргументы PRoot';

  @override
  String get workspaceEnvProotArgumentsHint =>
      'По одному аргументу на строку, без кавычек оболочки. Например, укажите -k и 5.10.0 на отдельных строках или используйте --kernel-release=5.10.0. Изменения применяются к новым командам и сессиям терминала.';

  @override
  String get workspaceEnvProotInvalid =>
      'Введите корректный абсолютный путь к оболочке и по одному аргументу PRoot на строку.';

  @override
  String get workspaceFileMissing => 'Файл больше не существует';

  @override
  String get workspaceFilePreviewUnavailable => 'Предпросмотр недоступен';

  @override
  String get workspaceToolRelatedFiles => 'Связанные файлы';

  @override
  String get workspaceToolFilesTruncated => 'Показана только часть файлов.';

  @override
  String get displaySettingsPageShowProducedFilesTitle =>
      'Показывать файлы под ответами';

  @override
  String get displaySettingsPageShowProducedFilesSubtitle =>
      'Показывать файлы, созданные или изменённые инструментами, под ответами.';

  @override
  String get reasoningBudgetSliderLow => 'Низкий';

  @override
  String get reasoningBudgetSliderMedium => 'Средний';

  @override
  String get reasoningBudgetSliderHigh => 'Высокий';

  @override
  String get reasoningBudgetSliderXhigh => 'Очень высокий';

  @override
  String get reasoningBudgetSliderMax => 'Максимум';

  @override
  String get defaultModelPagePerChatModelTitle => 'Модель для каждого чата';

  @override
  String get defaultModelPagePerChatModelSubtitle =>
      'Включено: выбранная в чате модель применяется только к этому чату. Выключено: она становится моделью текущего ассистента и применяется ко всем его чатам.';

  @override
  String get googleFontsTitle => 'Google Fonts';

  @override
  String get googleFontsRefresh => 'Обновить список шрифтов';

  @override
  String get googleFontsSearchHint => 'Поиск шрифтов или языков';

  @override
  String get googleFontsHint =>
      'Скачайте обычное начертание шрифта для предпросмотра и применения. Установленные шрифты работают без интернета. Каталог: Expo Google Fonts; загрузка: Google Fonts.';

  @override
  String get googleFontsNoResults => 'Подходящих шрифтов нет';

  @override
  String get googleFontsFailed =>
      'Не удалось загрузить или применить шрифт. Проверьте подключение и повторите попытку.';

  @override
  String get googleFontsDownloading => 'Загрузка шрифта…';

  @override
  String get googleFontsPreview =>
      'Съешь ещё этих мягких булок 0123456789 · Пример шрифта';

  @override
  String get googleFontsLicense => 'Лицензия шрифта';

  @override
  String get assistantEditLocationPermissionSettingsMessage =>
      'Доступ к геопозиции заблокирован. Разрешите его в системных настройках, затем включите этот инструмент снова.';

  @override
  String get healthDataSettingsCategoryReproductive =>
      'Репродуктивное здоровье';

  @override
  String get healthDataSettingsTypeMenstrualFlowTitle => 'Менструация';

  @override
  String get healthDataSettingsTypeMenstrualFlowSubtitle =>
      'Записи об интенсивности менструации и начале циклов за последние 90 дней';

  @override
  String get assistantEditGradientBackgroundTitle => 'Градиентный фон';

  @override
  String get assistantEditGradientStaticTitle => 'Статичный режим';

  @override
  String get assistantEditGradientStaticDescription =>
      'Экономит заряд при длинных чатах и потоковой генерации.';

  @override
  String get assistantEditGradientHorizontal => 'Положение по горизонтали';

  @override
  String get assistantEditGradientVertical => 'Положение по вертикали';

  @override
  String get assistantEditGradientPreview => 'Предпросмотр';

  @override
  String get assistantEditGradientNextFrame => 'Другой кадр';

  @override
  String get backgroundSettingsTitle => 'Фоновые задачи';

  @override
  String get backgroundTaskTitle => 'Задача Moru';

  @override
  String get backgroundCompleted => 'Генерация завершена';

  @override
  String get backgroundFailed =>
      'Не удалось сгенерировать ответ. Подробности — в чате.';

  @override
  String get backgroundCancelled => 'Генерация отменена';

  @override
  String get backgroundInterrupted =>
      'Фоновая генерация прервана. Откройте чат, чтобы продолжить.';

  @override
  String get backgroundRequesting => 'Подключение';

  @override
  String get backgroundGenerating => 'Генерация ответа';

  @override
  String get backgroundThinking => 'Размышление';

  @override
  String get backgroundToolRunning => 'Выполнение инструмента';

  @override
  String get backgroundRetrying => 'Ожидание повторной попытки';

  @override
  String get backgroundWorking => 'В работе';

  @override
  String get backgroundTasks => 'Задачи';

  @override
  String get backgroundStopTasks => 'Остановить задачи';

  @override
  String get backgroundOpenChat => 'Открыть чат';

  @override
  String get backgroundAndroidEnabled => 'Фоновая генерация';

  @override
  String get backgroundAndroidEnabledDetail =>
      'Продолжать текущие задачи при блокировке, в фоне и после удаления приложения из недавних. Во время работы требуется системное уведомление.';

  @override
  String get backgroundIosEnabled => 'Расширенное выполнение в фоне';

  @override
  String get backgroundIosEnabledDetail =>
      'Запрашивать время для завершения текущих задач. Для дополнительной поддержки фона отдельно включите геопозицию или беззвучное аудио.';

  @override
  String get backgroundNotifications => 'Уведомления задач';

  @override
  String get backgroundNotificationsDetail =>
      'Уведомлять о завершении и ошибках задач вне просматриваемого чата. Не управляет обязательным постоянным уведомлением Android.';

  @override
  String get backgroundPrivacy => 'Конфиденциальность статуса задач';

  @override
  String get backgroundPrivacyDetail =>
      'Скрывать названия диалогов и подробности инструментов в уведомлениях и текущем статусе. Отображаются только общий статус, число задач и прошедшее время.';

  @override
  String get backgroundLiveActivities => 'Текущие активности';

  @override
  String get backgroundLiveActivitiesDetail =>
      'Показывать текущие задачи на экране блокировки и в Dynamic Island. Доступность и отображение зависят от системы.';

  @override
  String get backgroundOverlay => 'Плавающий статус задач';

  @override
  String get backgroundOverlayDetail =>
      'Показывать перемещаемую капсулу задач поверх других приложений. Нажмите для открытия чата; закрытие скрывает только капсулу.';

  @override
  String get backgroundLiveUpdates => 'Обновляемые уведомления';

  @override
  String get backgroundLiveUpdatesDetail =>
      'Использовать Live Updates Android 16 на поддерживаемых устройствах. Уведомление повышенной заметности имеет приоритет над плавающей капсулой.';

  @override
  String get backgroundLocation => 'Поддержка фона через геопозицию';

  @override
  String get backgroundLocationDetail =>
      'Использовать обновления приблизительного местоположения во время фоновых задач. Координаты не сохраняются и не передаются ИИ-сервисам. Требуются расширенное выполнение в фоне и разрешение на геопозицию.';

  @override
  String get backgroundSilentAudio => 'Поддержка фона беззвучным аудио';

  @override
  String get backgroundSilentAudioDetail =>
      'Воспроизводить беззвучное аудио во время фоновых задач. При записи и озвучивании оно приостанавливается. Требуется расширенное выполнение в фоне; разрешение на микрофон не нужно.';

  @override
  String get backgroundSpeech => 'Озвучивание в фоне';

  @override
  String get backgroundSpeechDetail =>
      'Продолжать системное и сетевое озвучивание при блокировке и в фоне. Если отключено, переход в фон приостанавливает речь.';

  @override
  String get backgroundFinishVisibility =>
      'Длительность показа завершённого статуса';

  @override
  String get backgroundFinishImmediately => 'Скрывать сразу';

  @override
  String get backgroundFinishOneMinute => '1 минута';

  @override
  String get backgroundFinishFiveMinutes => '5 минут';

  @override
  String get backgroundFinishUntilForeground => 'До возвращения в приложение';

  @override
  String get backgroundFinishVisibilityDetail =>
      'Применяется к капсуле Android и карточке завершения на экране блокировки iOS. При возвращении в приложение завершённый статус очищается; максимум — 15 минут. При отмене он скрывается сразу.';

  @override
  String get backgroundOverlayIcon => 'Плавающий значок';

  @override
  String get backgroundIconDefault => 'Значок Moru';

  @override
  String get backgroundIconImage => 'Выбрать изображение';

  @override
  String get backgroundIconEmoji => 'Выбрать эмодзи';

  @override
  String get backgroundPermissionsTitle => 'Разрешения и системные настройки';

  @override
  String get backgroundNotificationsPermission => 'Разрешение на уведомления';

  @override
  String get backgroundBatteryOptimization => 'Оптимизация батареи';

  @override
  String get backgroundBatteryOptimizationDetail =>
      'Разрешите неограниченное использование батареи для более надёжной работы в фоне.';

  @override
  String get backgroundAutostart => 'Автозапуск и работа в фоне';

  @override
  String get backgroundAutostartDetail =>
      'Вручную проверьте автозапуск и ограничения фоновой работы устройства. Android не предоставляет надёжного способа проверить эти настройки производителя.';

  @override
  String get backgroundLocationPermission => 'Доступ к геопозиции';

  @override
  String get backgroundLocationAlways => 'Разрешить геопозицию в фоне';

  @override
  String get backgroundLocationAlwaysDetail =>
      'Можно предоставить постоянный доступ к геопозиции для работы в фоне. Разрешение запрашивается только при выборе этого действия.';

  @override
  String get backgroundSystemSettings => 'Системные настройки приложения';

  @override
  String get backgroundPermissionGranted => 'Разрешено';

  @override
  String get backgroundPermissionDenied => 'Не разрешено';

  @override
  String get backgroundPermissionLimited => 'При использовании приложения';

  @override
  String get backgroundPermissionUnknown => 'Проверить вручную';

  @override
  String get backgroundPermissionNotDetermined => 'Не запрашивалось';

  @override
  String get backgroundRuntimeTitle => 'Текущее состояние';

  @override
  String get backgroundRuntimeActive => 'Выполняется';

  @override
  String get backgroundRuntimeIdle => 'Неактивно';

  @override
  String get backgroundLocationActive => 'Геопозиция в фоне';

  @override
  String get backgroundAudioActive => 'Беззвучное аудио';

  @override
  String get backgroundActivityActive => 'Текущая активность';

  @override
  String get backgroundOverlayActive => 'Плавающее окно';

  @override
  String get backgroundLastError => 'Последнее прерывание или ошибка';

  @override
  String get backgroundNoError => 'Нет записей';

  @override
  String get backgroundUnsupported =>
      'Недоступно на устройстве или отключено в системных настройках';

  @override
  String get backgroundIosLimit =>
      'Фоновым выполнением управляет iOS. Сами по себе Live Activities не поддерживают работу приложения. Принудительное закрытие может прервать генерацию и задержать удаление статуса до следующего открытия приложения.';

  @override
  String get backgroundAndroidLimit =>
      'Если задачи останавливаются, проверьте уведомления, батарею и настройки фона производителя. Принудительная остановка и завершение процесса системой всё равно могут прервать генерацию.';

  @override
  String get backgroundStale =>
      'Статус не обновлялся. Откройте приложение для проверки.';

  @override
  String get backgroundIconError =>
      'Не удалось импортировать изображение. Выберите другое.';

  @override
  String get backgroundNotificationChannels => 'Каналы уведомлений';

  @override
  String get backgroundCompletionChannel => 'Канал уведомлений о завершении';

  @override
  String get backgroundOngoingChannel => 'Канал уведомлений о текущих задачах';

  @override
  String get backgroundOverlayAppearance => 'Внешний вид плавающего окна';

  @override
  String get backgroundOverlayAppearanceDetail =>
      'Размер, изображение, кольцо прогресса и видимое содержимое';

  @override
  String get backgroundOverlayPreviewHint =>
      'Перетащите для перемещения · Нажмите для открытия чата · Удерживайте для скрытия';

  @override
  String get backgroundOverlayCard => 'Карточка';

  @override
  String get backgroundOverlayCircle => 'Круглый значок';

  @override
  String get backgroundOverlaySize => 'Размер и форма';

  @override
  String get backgroundOverlayWidth => 'Ширина';

  @override
  String get backgroundOverlayHeight => 'Высота';

  @override
  String get backgroundOverlayCornerRadius => 'Радиус скругления';

  @override
  String get backgroundOverlayIconSize => 'Размер значка';

  @override
  String get backgroundOverlayProgressSize => 'Диаметр кольца прогресса';

  @override
  String get backgroundOverlayProgressStroke => 'Толщина кольца прогресса';

  @override
  String get backgroundOverlayContent => 'Видимое содержимое';

  @override
  String get backgroundOverlayShowProgress => 'Показывать кольцо прогресса';

  @override
  String get backgroundOverlayShowTitle => 'Показывать заголовок';

  @override
  String get backgroundOverlayShowSubtitle => 'Показывать подзаголовок';

  @override
  String get backgroundOverlayShowTime => 'Показывать прошедшее время';

  @override
  String get backgroundOverlayShowClose => 'Показывать кнопку закрытия';

  @override
  String get backgroundOverlayShowBackground => 'Показывать фон';

  @override
  String get backgroundOverlayShowBorder => 'Показывать рамку';

  @override
  String get backgroundOverlayReset => 'Восстановить исходное оформление';

  @override
  String get mcpStdioEnvironmentRequired =>
      'Установите среду рабочего пространства для использования STDIO на телефоне.';

  @override
  String get mcpArgumentsHint =>
      'Разделяйте аргументы пробелами; значения с пробелами заключайте в кавычки. Для пустого аргумента используйте \'\'.';

  @override
  String get mcpArgumentsInvalid =>
      'Проверьте незакрытые кавычки или незавершённое экранирование в конце аргументов.';

  @override
  String get mcpImportEnvironment => 'Импортировать из окружения';

  @override
  String get mcpEnvironmentEmpty =>
      'Нет переменных окружения. Добавьте их в настройках среды.';

  @override
  String get mcpEnvironmentHint =>
      'Переменные окружения наследуются. Импортируйте переменную, чтобы задать для сервера своё значение.';

  @override
  String get mcpImportJson => 'Импортировать JSON';

  @override
  String get mcpImportJsonHint =>
      'Вставьте конфигурацию MCP для Claude Desktop или Cursor. Просмотрите и добавьте серверы, не заменяя существующие.';

  @override
  String get mcpImportPaste => 'Вставить из буфера обмена';

  @override
  String get mcpImportPreview => 'Предпросмотр';

  @override
  String get mcpImportConfirm => 'Импорт';

  @override
  String get startupRecoverySnapshotTitle => 'Восстановить из снимка базы';

  @override
  String get startupRecoverySnapshotBody =>
      'Выберите снимок на устройстве, чтобы восстановить чаты и настройки, даже если база не открывается. Не удаляйте Moru: при удалении приложения эти снимки тоже исчезнут.';

  @override
  String get startupRecoverySnapshotEmpty =>
      'Снимки базы на устройстве не найдены. Экспортируйте данные, прежде чем пробовать другие способы восстановления.';

  @override
  String get startupRecoverySnapshotButton => 'Выбрать снимок';

  @override
  String startupRecoverySnapshotConfirm(String when) {
    return 'Восстановить чаты и настройки из снимка от $when? Изменения после этой даты не сохранятся. Существующие вложения и сам снимок останутся. Moru перезапустится для завершения восстановления.';
  }

  @override
  String startupRecoverySnapshotFailed(String reason) {
    return 'Не удалось подготовить восстановление снимка: $reason';
  }

  @override
  String get startupRecoverySnapshotReady =>
      'Снимок готов. Перезапустите Moru для завершения восстановления.';

  @override
  String get scheduledTasksTitle => 'Задачи по расписанию';

  @override
  String get scheduledTasksDescription =>
      'Автоматически выполняйте задачи в выбранное время: начинайте новый чат, продолжайте диалог или повторяйте вопрос.';

  @override
  String get scheduledTasksEmpty => 'Ваш день по расписанию';

  @override
  String get scheduledTasksEmptyDetail =>
      'Добавьте утреннюю сводку, ежедневный обзор или другую регулярно выполняемую задачу.';

  @override
  String get scheduledTasksAdd => 'Добавить задачу';

  @override
  String get scheduledTasksEdit => 'Изменить задачу';

  @override
  String get scheduledTasksName => 'Имя';

  @override
  String get scheduledTasksNameHint => 'Утренняя сводка';

  @override
  String get scheduledTasksPrompt => 'Промпт';

  @override
  String get scheduledTasksPromptHint => 'Что должен сделать ассистент?';

  @override
  String get scheduledTasksAssistant => 'Ассистент';

  @override
  String get scheduledTasksChooseAssistant => 'Выберите ассистента';

  @override
  String get scheduledTasksAssistantMissing => 'Ассистент недоступен';

  @override
  String get scheduledTasksTime => 'Время';

  @override
  String get scheduledTasksTimeHint => '24-часовой формат, например 08:00';

  @override
  String get scheduledTasksRepeat => 'Повтор';

  @override
  String get scheduledTasksEveryDay => 'Ежедневно';

  @override
  String get scheduledTasksWeekdays => 'Будни';

  @override
  String get scheduledTasksEnabled => 'Включено';

  @override
  String get scheduledTasksPermission => 'Будильники и напоминания';

  @override
  String get scheduledTasksPermissionDetail =>
      'Разрешите точные сигналы для запуска задач в выбранное время. Включённые задачи будут ожидать этого разрешения.';

  @override
  String get scheduledTasksPermissionAction => 'Разрешить';

  @override
  String get scheduledTasksReliability =>
      'Снимите ограничения батареи для Moru, чтобы задачи выполнялись надёжнее. Принудительная остановка приложения отменяет сигналы до следующего открытия. Пропущенные запуски не выполняются; используется часовой пояс устройства.';

  @override
  String get scheduledTasksExecutionDetail =>
      'Результаты сохраняются в чатах. Уведомление о завершении показывает начало ответа и открывает диалог по нажатию. Выполнение останавливается через 10 минут либо при необходимости ввода пользователя или подтверждения инструмента.';

  @override
  String get scheduledTasksRunNow => 'Запустить сейчас';

  @override
  String get scheduledTasksHistory => 'История запусков';

  @override
  String get scheduledTasksNoRuns => 'Запусков пока нет';

  @override
  String get scheduledTasksRunning => 'Выполняется';

  @override
  String get scheduledTasksCompleted => 'Завершено';

  @override
  String get scheduledTasksFailed => 'Ошибка';

  @override
  String get scheduledTasksInterrupted => 'Прервано';

  @override
  String get scheduledTasksPaused => 'Приостановлено';

  @override
  String get scheduledTasksWaitingPermission => 'Ожидание разрешения';

  @override
  String scheduledTasksNextRun(String time) {
    return 'Следующий запуск: $time';
  }

  @override
  String get scheduledTasksDelete => 'Удалить задачу';

  @override
  String get scheduledTasksDeleteDetail =>
      'Удалить расписание и историю его запусков? Уже созданные диалоги сохранятся.';

  @override
  String get scheduledTasksSave => 'Сохранить';

  @override
  String get scheduledTasksCancel => 'Отмена';

  @override
  String get scheduledTasksInvalid =>
      'Укажите название, промпт и ассистента; для своего расписания выберите хотя бы один день.';

  @override
  String get scheduledTasksLoading => 'Загрузка…';

  @override
  String get scheduledTasksOpenChat => 'Открыть диалог';

  @override
  String get scheduledTasksNeedsInput =>
      'Остановлено: потребовался ввод пользователя или подтверждение инструмента. Откройте диалог, чтобы продолжить.';

  @override
  String get scheduledTasksTimeout => 'Достигнут лимит времени выполнения.';

  @override
  String get scheduledTasksProcessTerminated =>
      'Android остановил предыдущий запуск.';

  @override
  String get scheduledTasksOnce => 'Один раз';

  @override
  String get scheduledTasksCustom => 'Свой вариант';

  @override
  String get scheduledTasksExecution => 'Задача';

  @override
  String get scheduledTasksMode => 'Действие';

  @override
  String get scheduledTasksNewChat => 'Новый чат';

  @override
  String get scheduledTasksFollowUp => 'Продолжить диалог';

  @override
  String get scheduledTasksRegenerate => 'Выполнить снова';

  @override
  String get scheduledTasksChat => 'Диалог';

  @override
  String get scheduledTasksChooseChat => 'Выберите диалог';

  @override
  String get scheduledTasksMessage => 'Вопрос для повторного выполнения';

  @override
  String get scheduledTasksChooseMessage => 'Выберите вопрос';

  @override
  String get scheduledTasksAttachmentMessage => 'Сообщение с вложениями';

  @override
  String get scheduledTasksModel => 'Модель';

  @override
  String get scheduledTasksChooseModel => 'Выберите модель';

  @override
  String get scheduledTasksModelDefault =>
      'Использовать модель диалога или ассистента';

  @override
  String get scheduledTasksSchedule => 'Расписание';

  @override
  String get scheduledTasksActiveWindow => 'Период действия';

  @override
  String get scheduledTasksStartDate => 'Дата начала';

  @override
  String get scheduledTasksEndDate => 'Дата окончания';

  @override
  String get scheduledTasksActiveWindowDetail =>
      'Запускать только в эти даты, включая дату окончания. Оставьте дату пустой, чтобы не ограничивать период.';

  @override
  String get scheduledTasksDate => 'Дата';

  @override
  String get scheduledTasksDateUnrestricted => 'Без лимита';

  @override
  String get scheduledTasksClear => 'Очистить';

  @override
  String get scheduledTasksSearch => 'Поиск';

  @override
  String get scheduledTasksNoTargets =>
      'У этого ассистента нет подходящих объектов';

  @override
  String get scheduledTasksFutureDate =>
      'Выберите будущие дату и время выполнения.';

  @override
  String get scheduledTasksDateRangeInvalid =>
      'Дата окончания не может быть раньше даты начала.';

  @override
  String get scheduledTasksRegenerateDetail =>
      'Создаёт другой ответ на выбранный вопрос с исходным контекстом. Существующие ответы и последующие сообщения сохраняются.';

  @override
  String get scheduledTasksSaving => 'Сохранение…';

  @override
  String get scheduledTasksFinished => 'Расписание завершено';

  @override
  String get scheduledTasksModelMissing =>
      'Выбранная модель недоступна. Измените задачу и выберите другую модель.';

  @override
  String get scheduledTasksChatMissing =>
      'Диалог недоступен или принадлежит другому ассистенту.';

  @override
  String get scheduledTasksMessageMissing =>
      'Выбранный вопрос больше недоступен.';

  @override
  String get scheduledTasksChatBusy =>
      'В этом диалоге уже генерируется ответ. Запуск по расписанию пропущен.';

  @override
  String get scheduledTasksDesktopEmpty => 'Нет задач по расписанию';

  @override
  String get scheduledTasksDesktopReliability =>
      'Задачи выполняются, только пока Moru запущено, в том числе в свёрнутом виде или системном трее. Пропущенные после выхода или сна компьютера запуски не выполняются. Moru не запускается автоматически.';

  @override
  String get scheduledTasksDesktopExecutionDetail =>
      'Результаты сохраняются в чатах. Откройте их из истории запусков задачи. Выполнение останавливается через 10 минут либо при необходимости ввода пользователя или подтверждения инструмента.';

  @override
  String get worldBookStickyLabel => 'Удержание (сообщений)';

  @override
  String get worldBookStickyHint =>
      'Сохранять запись активной в течение N сообщений после срабатывания. Повторные совпадения не продлевают период. 0 отключает этот эффект.';

  @override
  String get worldBookCooldownLabel => 'Пауза (сообщений)';

  @override
  String get worldBookCooldownHint =>
      'Запрещать повторное срабатывание на N сообщений после активации или окончания удержания. 0 отключает этот эффект.';

  @override
  String get worldBookDelayLabel => 'Задержка (сообщений)';

  @override
  String get worldBookDelayHint =>
      'Разрешать активацию, только когда в диалоге есть хотя бы N сообщений. Считаются отдельные сообщения, а не пары вопрос-ответ. 0 отключает этот эффект.';

  @override
  String get worldBookDragToReorder => 'Перетащите для изменения порядка';

  @override
  String worldBookEnabledCount(int enabled, int total) {
    return 'Включено: $enabled/$total';
  }

  @override
  String get assistantConversationSystemPromptTitle =>
      'Системный промпт для каждого диалога';

  @override
  String get assistantConversationSystemPromptHint =>
      'Разрешить каждому диалогу использовать свой системный промпт.';

  @override
  String get assistantConversationInjectionTitle =>
      'Добавляемые инструкции для каждого диалога';

  @override
  String get assistantConversationInjectionHint =>
      'Выбирать инструкции и книги мира отдельно для каждого диалога. По умолчанию ничего не выбрано.';

  @override
  String get conversationSystemPromptTitle => 'Системный промпт диалога';

  @override
  String get conversationSystemPromptHint =>
      'Применяется только к этому диалогу. Оставьте пустым для промпта ассистента.';

  @override
  String get conversationSystemPromptClear => 'Использовать промпт ассистента';

  @override
  String get conversationSystemPromptPlaceholder =>
      'Введите системный промпт для этого диалога…';

  @override
  String get conversationPromptScope => 'Этот диалог';

  @override
  String get oauthAccountsTab => 'Аккаунты';

  @override
  String get oauthLogin => 'Войти';

  @override
  String oauthLoginTo(String provider) {
    return 'Войти в $provider';
  }

  @override
  String get oauthConnected => 'Подключено';

  @override
  String get oauthNotConnected => 'Не подключено';

  @override
  String oauthWaiting(String provider) {
    return 'Ожидание авторизации $provider';
  }

  @override
  String get oauthCancel => 'Отменить авторизацию';

  @override
  String get oauthOpenBrowser => 'Открыть страницу авторизации';

  @override
  String get oauthCopyCode => 'Скопировать код';

  @override
  String get oauthCodeHint => 'Введите этот код на странице авторизации';

  @override
  String get oauthDeviceHint =>
      'Сначала включите вход по коду устройства в настройках безопасности ChatGPT или разрешениях рабочего пространства.';

  @override
  String get oauthDeviceLogin => 'Использовать код устройства';

  @override
  String get oauthDetails => 'Сведения об аккаунте';

  @override
  String get oauthConnectAnother => 'Подключить другой аккаунт';

  @override
  String get oauthRelogin => 'Войти снова';

  @override
  String get oauthNeedsLogin => 'Требуется вход';

  @override
  String oauthExpired(String provider) {
    return 'Срок входа в $provider истёк';
  }

  @override
  String get oauthLoginRestored =>
      'Вход выполнен. Нажмите повторную отправку сообщения, чтобы отправить его снова.';

  @override
  String get oauthLogout => 'Выйти';

  @override
  String get oauthLogoutDescription =>
      'Удалить сохранённые данные авторизации этого аккаунта с устройства';

  @override
  String get oauthRefreshing => 'Обновление авторизации…';

  @override
  String get oauthRefreshUsage => 'Обновить расход';

  @override
  String get oauthUsageDetails => 'Подробности расхода';

  @override
  String get oauthUsageUnavailable => 'Сведения о расходе сейчас недоступны';

  @override
  String oauthLastUpdated(String time) {
    return 'Обновлено: $time';
  }

  @override
  String get oauthSyncModels => 'Синхронизировать';

  @override
  String get oauthSyncing => 'Синхронизация моделей…';

  @override
  String get oauthModelsHint =>
      'Доступные модели синхронизируются с вашим аккаунтом.';

  @override
  String get oauthNoModels => 'Синхронизируйте модели, чтобы начать общение';

  @override
  String get oauthConnection => 'Подключение';

  @override
  String get oauthConnectionInfo => 'Сведения о подключении';

  @override
  String get oauthEndpoint => 'Адрес сервера';

  @override
  String get oauthScope => 'Область авторизации';

  @override
  String get oauthAccountId => 'ID аккаунта';

  @override
  String get oauthTokenExpiry => 'Срок действия токена';

  @override
  String get oauthName => 'Название провайдера';

  @override
  String get oauthEnabledHint => 'Показывать эти модели в списке выбора';

  @override
  String get oauthNetwork => 'Сетевой прокси';

  @override
  String get oauthFollowGlobal => 'Использовать общие настройки';

  @override
  String get oauthCustomRequest => 'Свой запрос';

  @override
  String get oauthWeekly => 'Недельный период';

  @override
  String get oauthMonthly => 'Месячный период';

  @override
  String get oauthTotal => 'Общая квота';

  @override
  String oauthHours(String count) {
    return 'Период: $count ч';
  }

  @override
  String oauthMinutes(String count) {
    return 'Период: $count мин';
  }

  @override
  String oauthDays(String count) {
    return 'Период: $count дн.';
  }

  @override
  String get oauthWindow => 'Период учёта расхода';

  @override
  String oauthResetsAt(String time) {
    return 'Сброс: $time';
  }

  @override
  String get oauthNetworkError =>
      'Не удалось подключиться. Проверьте сеть и повторите попытку.';

  @override
  String get oauthInvalidResponse =>
      'Авторизация не завершена. Повторите попытку.';

  @override
  String get oauthTimeout => 'Время авторизации истекло. Повторите попытку.';

  @override
  String get oauthDenied => 'Авторизация не разрешена. Повторите попытку.';

  @override
  String get oauthSaving => 'Подключение аккаунта…';

  @override
  String get oauthQuotaExceeded => 'У этого аккаунта нет доступной квоты.';

  @override
  String get oauthRateLimited =>
      'Слишком много запросов. Повторите попытку позже.';

  @override
  String get oauthPermissionDenied => 'У аккаунта нет доступа к этому ресурсу.';

  @override
  String get oauthRequestFailed => 'Провайдер не смог выполнить запрос.';

  @override
  String get oauthQuotaAvailable => 'Квота доступна';

  @override
  String oauthSavedResets(String count) {
    return 'Доступно сбросов лимита: $count';
  }

  @override
  String get oauthPrimaryWindow => 'Основной период';

  @override
  String get oauthSecondaryWindow => 'Дополнительный период';

  @override
  String get oauthAuthorizationCode =>
      'Код авторизации или URL обратного вызова';

  @override
  String get oauthAuthorizationCodeHint =>
      'Если браузер не вернулся автоматически, вставьте сюда итоговый URL обратного вызова или код авторизации.';

  @override
  String get oauthInvalidAuthorizationCode =>
      'Введите код или URL обратного вызова из этой попытки входа.';

  @override
  String get oauthSubmitAuthorizationCode => 'Завершить вход';

  @override
  String get oauthExtraUsage => 'Дополнительный расход';

  @override
  String get oauthPromptCachingHelp =>
      'Повторно использовать контекст между сообщениями и выбрать срок хранения кэша.';

  @override
  String get moruLanguageRussian => 'Русский';

  @override
  String get moruDeleteHeader => 'Удалить заголовок';

  @override
  String get moruDeleteEntry => 'Удалить запись';

  @override
  String get moruSearchCategory => 'Категория';

  @override
  String get moruSearchCountry => 'Страна';

  @override
  String get moruSearchIncludeDomains => 'Включить домены';

  @override
  String get moruSearchExcludeDomains => 'Исключить домены';

  @override
  String moruLogReadFailed(String error) {
    return 'Не удалось прочитать файл: $error';
  }

  @override
  String get moruChatNotificationChannel => 'Фоновая работа чата';

  @override
  String get moruChatNotificationDescription =>
      'Уведомления о состоянии генерации ответов';

  @override
  String get moruCherryImportWarning =>
      'Это экспериментальная функция.\nДля сохранности данных рекомендуется создать резервную копию перед импортом.\nПерейти к выбору файла?';

  @override
  String get moruPaletteDefault => 'Стандартная';

  @override
  String get moruPaletteBlue => 'Небесная синева';

  @override
  String get moruPaletteGreen => 'Бамбуковая зелень';

  @override
  String get moruPalettePurple => 'Аметистовый';

  @override
  String get moruPaletteYellow => 'Янтарное золото';

  @override
  String get moruPaletteSmokyRose => 'Дымчатая роза';

  @override
  String get moruPaletteTerracotta => 'Терракота';

  @override
  String get moruPaletteMonochrome => 'Морозный серый';

  @override
  String get moruPaletteDocTheme => 'Документ';
}
