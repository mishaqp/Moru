"""One-time, exact-source localization patch. Removed before PR merge."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))

def write_json(path, value):
    (ROOT / path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def edit(path, old, new, count=1):
    p = ROOT / path
    source = p.read_text(encoding='utf-8')
    if old not in source and new in source:
        return
    assert source.count(old) == count, (path, old[:100], source.count(old), count)
    p.write_text(source.replace(old, new), encoding='utf-8')

additions = {
    'moruLanguageRussian': ['Русский', 'Русский', 'Русский', 'Русский'],
    'moruDeleteHeader': ['Delete header', 'Удалить заголовок', '删除请求头', '刪除請求標頭'],
    'moruDeleteEntry': ['Delete entry', 'Удалить запись', '删除条目', '刪除項目'],
    'moruSearchCategory': ['Category', 'Категория', '类别', '類別'],
    'moruSearchCountry': ['Country', 'Страна', '国家', '國家'],
    'moruSearchIncludeDomains': ['Include domains', 'Включить домены', '包含域名', '包含網域'],
    'moruSearchExcludeDomains': ['Exclude domains', 'Исключить домены', '排除域名', '排除網域'],
    'moruLogReadFailed': ['Error loading file: {error}', 'Не удалось прочитать файл: {error}', '读取文件失败：{error}', '讀取檔案失敗：{error}'],
    'moruChatNotificationChannel': ['Chat Background', 'Фоновая работа чата', '聊天后台任务', '聊天背景工作'],
    'moruChatNotificationDescription': ['Notifications for chat generation status', 'Уведомления о состоянии генерации ответов', '聊天回复生成状态通知', '聊天回覆生成狀態通知'],
    'moruCherryImportWarning': [
        'This feature is experimental.\nTo keep your data safe, it is recommended to back up before importing.\nProceed to choose a file?',
        'Это экспериментальная функция.\nДля сохранности данных рекомендуется создать резервную копию перед импортом.\nПерейти к выбору файла?',
        '此功能目前仍处于实验阶段。\n目前仅能导入助手，对话内容，供应商和文件，\n一些供应商需要在baseurl后面添加/v1 or /v1beta。 \n为确保数据安全，建议在导入前先执行备份。\n是否已知晓并继续选择文件？',
        '此功能目前仍處於實驗階段。\n目前僅能匯入助手、對話內容、供應商和檔案，\n部分供應商需要在 baseurl 後面新增 /v1 或 /v1beta。\n為確保資料安全，建議在匯入前先執行備份。\n是否已知悉並繼續選擇檔案？',
    ],
}
palette_ru = {
    'default': 'Стандартная', 'blue': 'Небесная синева', 'green': 'Бамбуковая зелень',
    'purple': 'Аметистовый', 'yellow': 'Янтарное золото', 'smoky_rose': 'Дымчатая роза',
    'terracotta': 'Терракота', 'monochrome': 'Морозный серый', 'doc_theme': 'Документ',
}
palette_source = (ROOT / 'lib/theme/palettes.dart').read_text()
ids = dict(re.findall(r"static const String (\w+) = '([^']+)';", palette_source))
palette_entries = re.findall(r"id: (\w+),\s*zhName: '([^']+)',\s*enName: '([^']+)'", palette_source)
assert len(palette_entries) == 9, 'Review newly added palette names first'
palette_cases=[]
for identifier, chinese, english in palette_entries:
    key='moruPalette' + ''.join(part.title() for part in ids[identifier].split('_'))
    additions[key]=[english,palette_ru[ids[identifier]],chinese,chinese]
    palette_cases.append(f'      ThemePalettes.{identifier} => l10n.{key},')
for path in sorted((ROOT/'lib/l10n').glob('app_*.arb')):
    language=path.stem.removeprefix('app_')
    index={'en':0,'ru':1,'zh':2,'zh_Hans':2,'zh_Hant':3}[language]
    catalog=json.loads(path.read_text())
    for key, values in additions.items():
        catalog[key]=values[index]
        if key=='moruLogReadFailed':
            catalog['@'+key]={'placeholders':{'error':{'type':'String'}}}
    if language=='ru':
        catalog.update({
            'modelDetailSheetOpenrouterShellTool':'Оболочка',
            'iosLiveActivityTitle':'Текущая активность',
            'backgroundLiveActivities':'Текущие активности',
            'backgroundLiveUpdates':'Обновляемые уведомления',
            'backgroundActivityActive':'Текущая активность',
        })
    path.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')

# Default only new installations to RU; preserve explicit EN/ZH/system choices.
p='lib/core/providers/settings_provider.dart'
edit(p,"// Load app locale; default to follow system on first launch","// New Moru installations default to Russian; preserve explicit choices.")
edit(p,"if (storedAppLocale != _appLocaleTag) {\n      await prefs.setString(_appLocaleKey, 'system');", "if (storedAppLocale != _appLocaleTag) {\n      await prefs.setString(_appLocaleKey, _appLocaleTag!);")
edit(p,"String? _appLocaleTag; // 'system', 'zh_CN', 'zh_Hant', 'en_US'", "String? _appLocaleTag; // 'system', 'ru', 'zh_CN', 'zh_Hant', 'en_US'")
edit(p,"    const supportedTags = {'system', 'zh_CN', 'zh_Hant', 'en_US'};", "    if (value == null) return 'ru';\n    const supportedTags = {'system', 'ru', 'zh_CN', 'zh_Hant', 'en_US'};")
edit(p,"    final lc = l.languageCode.toLowerCase();\n    if (lc == 'zh') {", "    final lc = l.languageCode.toLowerCase();\n    if (lc == 'ru') return 'ru';\n    if (lc == 'zh') {")
edit(p,"  Locale _parseLocaleTag(String tag) {\n    switch (tag) {", "  Locale _parseLocaleTag(String tag) {\n    switch (tag) {\n      case 'ru':\n        return const Locale('ru');")
p='lib/features/settings/pages/display_settings_page.dart'
edit(p,"                  String labelFor(Locale l) {\n                    if (l.languageCode == 'zh') {", "                  String labelFor(Locale l) {\n                    if (l.languageCode == 'ru') return l10n.moruLanguageRussian;\n                    if (l.languageCode == 'zh') {")
edit(p,"                  label: l10n.settingsPageSystemMode,\n                  onTap: () => Navigator.of(ctx).pop('system'),\n                ),", "                  label: l10n.settingsPageSystemMode,\n                  onTap: () => Navigator.of(ctx).pop('system'),\n                ),\n                _sheetDividerNoIcon(ctx),\n                _sheetOption(\n                  ctx,\n                  label: l10n.moruLanguageRussian,\n                  onTap: () => Navigator.of(ctx).pop('ru'),\n                ),")
edit(p,"    switch (selected) {\n      case 'system':", "    switch (selected) {\n      case 'ru':\n        await settings.setAppLocale(const Locale('ru'));\n        break;\n      case 'system':")
edit(p,"return Localizations.localeOf(context).languageCode == 'zh'\n          ? palette.displayNameZh\n          : palette.displayNameEn;", "return palette.localizedName(l10n);")
p='lib/features/settings/pages/theme_settings_page.dart'
edit(p,"final title = Localizations.localeOf(context).languageCode == 'zh'\n      ? palette.displayNameZh\n      : palette.displayNameEn;", "final title = palette.localizedName(AppLocalizations.of(context)!);")
p='lib/theme/palettes.dart'
edit(p,"import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport '../l10n/app_localizations.dart';")
edit(p,"  String get displayNameEn => enName;", "  String get displayNameEn => enName;\n\n  String localizedName(AppLocalizations l10n) {\n    // Only presentation changes; palette IDs and saved custom names stay intact.\n    if (l10n.localeName.startsWith('zh')) return zhName;\n    if (!l10n.localeName.startsWith('ru')) return enName;\n    return switch (id) {\n"+'\n'.join(palette_cases)+"\n      _ => enName,\n    };\n  }")

# Mobile presentation hardcodes. Values sent to APIs are deliberately excluded.
p='lib/features/assistant/pages/assistant_settings_edit_basic_tab.dart'
edit(p,"'Temperature'", "l10n.assistantEditTemperatureTitle",2)
edit(p,"'Top P'", "l10n.assistantEditTopPTitle",2)
p='lib/features/home/widgets/side_drawer.dart'
edit(p,"semanticLabel: 'Edit assistant'", "semanticLabel: AppLocalizations.of(context)!.assistantTagsContextMenuEditAssistant")
p='lib/features/model/widgets/model_detail_sheet.dart'
edit(p,"semanticLabel: 'Delete header'", "semanticLabel: AppLocalizations.of(context)!.moruDeleteHeader")
edit(p,"semanticLabel: 'Delete entry'", "semanticLabel: AppLocalizations.of(context)!.moruDeleteEntry")
p='lib/features/provider/widgets/add_provider_sheet.dart'
edit(p,"label: 'API Key'", "label: l10n.multiKeyPageKey",3)
edit(p,"label: 'API Base Url'", "label: l10n.providerDetailPageApiBaseUrlLabel",3)
p='lib/features/search/pages/search_service_editor_page.dart'
for label, key, count in [
    ('Category','moruSearchCategory',1),('Country','moruSearchCountry',1),
    ('Location','providerDetailPageLocationLabel',2),('Language','asrServicesLanguageLabel',1),
    ('Include domains','moruSearchIncludeDomains',1),('Exclude domains','moruSearchExcludeDomains',1),
]: edit(p, f"label: '{label}'",f'label: l10n.{key}',count)
p='lib/features/settings/pages/log_viewer_page.dart'
edit(p,"message: 'Export failed: $e'", "message: AppLocalizations.of(context)!.storageSpaceExportFailed(e.toString())",3)
edit(p,"_content = 'Error loading file: $e';", "_content = AppLocalizations.of(context)!.moruLogReadFailed(e.toString());")
p='lib/features/backup/pages/backup_page.dart'
s=(ROOT/p).read_text()
start=s.find('    final locale = Localizations.localeOf(context);\n    final isZh = locale.languageCode.startsWith(\'zh\');')
if start>=0:
    end=s.index('\n\n    return showModalBottomSheet<bool>',start)
    old=s[start:end]
    assert 'This feature is experimental.' in old
    edit(p,old,'    final body = l10n.moruCherryImportWarning;')

# Service-owned notification labels use the same generated catalog as the UI.
p='lib/core/services/notification_service.dart'
edit(p,"import 'package:flutter_local_notifications/flutter_local_notifications.dart';", "import 'package:flutter_local_notifications/flutter_local_notifications.dart';\nimport '../../l10n/app_localizations.dart';\nimport '../../l10n/app_localizations_ru.dart';")
old="""  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'kelivo_bg_chat_v2',
    'Chat Background',
    description: 'Notifications for chat generation status',
    importance: Importance.high,
    playSound: true,
  );"""
new="""  static AppLocalizations _l10n = AppLocalizationsRu();

  static ({String title, String body, String channelName, String channelDescription})
      get completionText => (
        title: _l10n.notificationChatCompletedTitle,
        body: _l10n.notificationChatCompletedBody,
        channelName: _l10n.moruChatNotificationChannel,
        channelDescription: _l10n.moruChatNotificationDescription,
      );

  static AndroidNotificationChannel get _channel => AndroidNotificationChannel(
    'kelivo_bg_chat_v2',
    completionText.channelName,
    description: completionText.channelDescription,
    importance: Importance.high,
    playSound: true,
  );

  static Future<void> configureLocalizations(AppLocalizations l10n) async {
    final changed = _l10n.localeName != l10n.localeName;
    _l10n = l10n;
    if (changed && _inited && Platform.isAndroid) {
      await _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()?.createNotificationChannel(_channel);
    }
  }"""
edit(p,old,new)
edit(p,"title ?? 'Generation complete'", "title ?? completionText.title")
edit(p,"body ?? 'Assistant reply has been generated'", "body ?? completionText.body",2)
p='lib/core/services/mobile_background.dart'
edit(p,"    _l10n = l10n;\n    await initialize();", "    _l10n = l10n;\n    await NotificationService.configureLocalizations(l10n);\n    await initialize();")

# Flutter remains the syntax authority; only extract named ICU inputs here.
p='tool/check_moru_ru.py'
s=(ROOT/p).read_text()
if 'def icu_arguments(' not in s:
    walker='''def icu_arguments(message):
    names = set()

    def closing(start):
        depth = 1
        for index in range(start + 1, len(message)):
            if message[index] == "{":
                depth += 1
            elif message[index] == "}":
                depth -= 1
                if depth == 0:
                    return index
        raise ValueError("Unbalanced ICU braces")

    def scan(start, end):
        index = start
        while index < end:
            if message[index] != "{":
                index += 1
                continue
            stop = closing(index)
            header = re.match(r"\\{\\s*([A-Za-z][A-Za-z0-9_]*)\\s*([,}])", message[index:])
            if header is None:
                raise ValueError("Invalid ICU argument header")
            names.add(header.group(1))
            cursor = index + header.end()
            if header.group(2) == ",":
                kind = re.match(r"\\s*(plural|select|selectordinal)\\s*,", message[cursor:])
                if kind:
                    cursor += kind.end()
                    while cursor < stop:
                        branch = message.find("{", cursor, stop)
                        if branch < 0:
                            break
                        branch_end = closing(branch)
                        scan(branch + 1, branch_end)
                        cursor = branch_end + 1
            index = stop + 1

    scan(0, len(message))
    return names


'''
    s=s.replace('def validate(root):',walker+'def validate(root):',1)
    s=s.replace('    variables = re.compile(r"\\{\\s*([a-zA-Z][a-zA-Z0-9_]*)\\s*(?:[,}])")\n','')
    s=s.replace('set(variables.findall(en[key])), set(variables.findall(value))','icu_arguments(en[key]), icu_arguments(value)')
    (ROOT/p).write_text(s)

# Fixed reviewed exception keys, never an automatically accepted list of English.
exception_keys='''settingsPageMcp sponsorPageAfdianTitle sponsorPageAfdianSubtitle mcpTransportOptionStdio mcpTransportTagStdio mcpTransportTagSse mcpTransportTagHttp assistantEditPageMcpTab codeBlockDefaultFileNameStem markdownTableDefaultFileNameStem assistantEditTopPTitle backupPageWebDavTab backupProgressBytes backupProgressItems backupPageUserAgent chatSelectionExportTxt chatSelectionExportMd messageExportSheetMarkdown modelDetailSheetModelIdDisabledHint modelDetailSheetYoutubeTool providerDetailPageVertexAiTitle providersPageSiliconFlowName providersPageAliyunName providersPageZhipuName providersPageByteDanceName miniMapSearchMatchCount aboutPageVersionDetail aboutPagePlatformMacos aboutPagePlatformWindows aboutPagePlatformLinux aboutPagePlatformAndroid aboutPagePlatformIos aboutPageGithub displaySettingsPageSendShortcutEnter displaySettingsPageSendShortcutCtrlEnter asrServicesOpenAiTitle asrServicesDashScopeTitle asrServicesVolcengineTitle asrServicesMimoTitle asrServicesStepTitle ttsServicesFieldTopPLabel imageViewerPageCounter searchServiceNameDuckDuckGo searchServiceNameTavily searchServiceNameExa searchServiceNameZhipu searchServiceNameSearXNG searchServiceNameLinkUp searchServiceNameBrave searchServiceNameMetaso searchServiceNameOllama searchServiceNameJina searchServiceNamePerplexity searchServiceNameBocha searchServiceNameDoubao searchServiceNameSerper searchServiceNameQuerit searchServiceNameGrok searchServiceNameStepFun searchServiceNameFirecrawl searchServiceNameTinyFish searchServiceNameAnySearch searchServiceNameParallel searchServiceNameYou searchServicesDialogSitesHint searchServicesDialogTimeRangeHint searchServicesDialogCountriesHint searchServicesDialogLanguagesHint networkProxyTypeHttp networkProxyTypeHttps networkProxyTypeSocks5 logViewerFieldId memorySettingsInjectionMaxItemsOption memoryEntryScopeAssistantNamed migrationSourceDatabaseLabel migrationTargetDatabaseLabel workspaceToolStdout workspaceToolStderr workspaceToolCount workspaceToolMoreFiles workspaceEnvEngineUbuntu workspaceEnvEngineAlpine workspaceEnvMetaLine workspaceEnvRuntimeReason workspaceEnvMirrorFailed workspaceEnvCategoryApt workspaceEnvCategoryApk workspaceEnvCategoryPip workspaceEnvCategoryNpm skillsImportPasteLabel workspaceEnvArchVersion workspaceEnvDownloadLine workspaceEnvMirrorNameTuna workspaceEnvMirrorNameAlibaba workspaceEnvMirrorNameUstc workspaceEnvMirrorNameHuawei workspaceEnvMirrorNameTencent workspaceEnvMirrorNameNetease workspaceEnvMirrorNameNpmmirror workspaceEnvSelectionNamed workspaceEnvDownloadCustomHint googleFontsTitle'''.split()
en=read('lib/l10n/app_en.arb');ru=read('lib/l10n/app_ru.arb')
exceptions={}
for key in exception_keys:
    assert key in en and en[key]==ru[key],key
    value=en[key]
    reason='Название сервиса, платформы, протокола или технического формата; перевод не требуется.'
    if '{' in value:
        reason='Подстановочные значения и формат вывода; идентификаторы переменных и данные не переводятся.'
    elif key.endswith('Hint') or 'FileName' in key or key=='sponsorPageAfdianSubtitle':
        reason='Технический пример ввода, URL или имя файла; сохранить без перевода.'
    elif 'Shortcut' in key:
        reason='Обозначение клавиши или сочетания клавиш.'
    elif 'TopP' in key:
        reason='Стандартное обозначение параметра сэмплирования модели.'
    exceptions[key]=reason
write_json('tool/moru_ru_technical_allowlist.json',exceptions)
print('Applied Russian locale, catalog, mobile labels, palettes, notifications and ICU validator.')
