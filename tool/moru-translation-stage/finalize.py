"""Final reviewed presentation edits; temporary generator, removed before merge."""
from pathlib import Path
import json
import runpy

ROOT = Path(__file__).resolve().parents[2]
runpy.run_path(str(Path(__file__).with_name('apply.py')))

notices = {
    'moruProviderTensdaqNotice': [
        'A bidding-based AI MaaS platform with prices determined by market supply and demand instead of fixed pricing.',
        'Платформа AI MaaS с аукционным ценообразованием: цены определяются рыночным спросом и предложением вместо фиксированных тарифов.',
        '革命性竞价 AI MaaS 平台，价格由市场供需决定，告别高成本固定定价。',
        '革命性的競價 AI MaaS 平台，價格由市場供需決定，告別高成本固定定價。',
    ],
    'moruProviderSiliconFlowNotice': [
        'Free SiliconFlow models are included and need no API key. For more capable models, obtain your own API key and configure it here.',
        'Бесплатные модели SiliconFlow уже доступны без ключа API. Для более мощных моделей получите собственный ключ API и укажите его здесь.',
        '已内置硅基流动的免费模型，无需 API Key。若需更强大的模型，请申请并在此配置你自己的 API Key。',
        '已內建 SiliconFlow 的免費模型，無需 API Key。若需要更強大的模型，請申請並在此設定自己的 API Key。',
    ],
    'moruProviderSuixiangNotice': [
        'An API relay for Claude, Codex, Gemini and other services. It advertises privacy, no data resale or model substitution, 1:1 credits and usage-based billing, with redundant routes, cross-region recovery, automatic failover and persistent SSE connections.',
        'API-посредник для Claude, Codex, Gemini и других сервисов. Заявлены конфиденциальность, отсутствие перепродажи данных и подмены моделей, пополнение 1:1 и оплата по использованию, резервные маршруты, межрегиональное восстановление, автоматическое переключение при сбоях и непрерывные соединения SSE.',
        '可靠高效的 API 中继服务，提供 Claude、Codex、Gemini 等中继服务。注重隐私·无数据倒卖·无模型掺水，充值额度 1:1，按量付费。多线路冗余、跨区域容灾、自动故障切换，长链路 SSE 不中断。',
        '可靠高效的 API 中繼服務，提供 Claude、Codex、Gemini 等服務。注重隱私，不轉售資料、不替換模型，儲值額度 1:1，按量付費。多線路備援、跨區域復原、自動容錯切換，長連線 SSE 不中斷。',
    ],
    'moruProviderMaruCodeNotice': [
        'An independently operated API relay with its own account pool for Codex, Claude Code, GPT Image and other models. WebSocket support; advertised rates: Codex 0.25x, CC 1.5x, transparent 1:1 conversion and $2 registration credit for new users.',
        'Независимый API-посредник с собственным пулом аккаунтов для Codex, Claude Code, GPT Image и других моделей. Поддерживает WebSocket; заявленные тарифы: Codex 0.25x, CC 1.5x, прозрачный курс 1:1 и бонус $2 новым пользователям при регистрации.',
        '偶尔做做慈善的小破站 API，自营号池，主要提供 Codex、Claude Code、GPT Image 等主流模型。支持 Websocket 协议，明码标价(Codex 0.25x, CC 1.5x)，透明汇率(1:1)，新用户注册送 2 刀。',
        '不時回饋使用者的小型 API 服務，使用自營帳號池，主要提供 Codex、Claude Code、GPT Image 等模型。支援 WebSocket，明確標價（Codex 0.25x、CC 1.5x），透明匯率（1:1），新使用者註冊贈送 2 美元。',
    ],
}
extra = {
    **notices,
    'moruProviderWebsitePrefix': ['Website: ', 'Сайт: ', '官网：', '官網：'],
    'moruSecondsShort': ['{seconds}s', '{seconds} с', '{seconds}秒', '{seconds}秒'],
    'moruConsoleSource': ['Source: {source}', 'Источник: {source}', '来源：{source}', '來源：{source}'],
}
for path in (ROOT/'lib/l10n').glob('app_*.arb'):
    locale=path.stem.removeprefix('app_')
    index={'en':0,'ru':1,'zh':2,'zh_Hans':2,'zh_Hant':3}[locale]
    catalog=json.loads(path.read_text())
    for key,translations in extra.items():
        catalog[key]=translations[index]
    catalog['@moruSecondsShort']={'placeholders':{'seconds':{'type':'int'}}}
    catalog['@moruConsoleSource']={'placeholders':{'source':{'type':'String'}}}
    path.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')

def edit(path,old,new,count=1):
    p=ROOT/path
    text=p.read_text()
    if old not in text and new in text:return
    assert text.count(old)==count,(path,old[:70],text.count(old))
    p.write_text(text.replace(old,new))

for key,translations in notices.items():
    edit('lib/features/provider/pages/provider_detail_page.dart',"'"+translations[2]+"'",'l10n.'+key)
edit('lib/features/provider/pages/provider_detail_page.dart',"text: '官网：'",'text: l10n.moruProviderWebsitePrefix',4)
edit('lib/features/settings/pages/display_settings_page.dart',"'${seconds.round()}s'",'AppLocalizations.of(context)!.moruSecondsShort(seconds.round())',2)
edit('lib/features/settings/pages/display_settings_page.dart',"'2s'",'AppLocalizations.of(context)!.moruSecondsShort(2)')
edit('lib/shared/pages/webview_page.dart',
     "'${m.level}: ${m.message}\\nSource: ${m.source ?? ''}${m.line != null ? ':${m.line}' : ''}'",
     "'${m.level}: ${m.message}\\n${l10n.moruConsoleSource('${m.source ?? ''}${m.line != null ? ':${m.line}' : ''}')}'")
print('Localized four provider notices, website prefixes, seconds and console source labels; URLs/IDs unchanged.')
