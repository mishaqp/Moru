"""Temporary, exact presentation edits. Removed before the localization PR merge."""
from pathlib import Path
import json
import runpy

root = Path(__file__).resolve().parents[2]
runpy.run_path(str(root / 'tool/moru-translation-stage/finalize.py'))

messages = {
    'moruCodeBlockLabel': ['Code', 'Код', '代码', '程式碼'],
    'moruAsrParaformerName': ['Paraformer small Chinese model', 'Paraformer — малая китайская модель', 'Paraformer 中文小模型', 'Paraformer 中文小模型'],
    'moruAsrParaformerDescription': ['Primarily Chinese, with basic English support. Download: about 78 MB.', 'В основном для китайского языка, с поддержкой простого английского. Загрузка: около 78 МБ.', '中文优先，兼顾简单英文，下载约 78 MB', '以中文為主，兼顧簡單英文，下載約 78 MB'],
    'moruAsrSenseVoiceName': ['SenseVoice int8 multilingual model', 'SenseVoice int8 — многоязычная модель', 'SenseVoice int8 多语模型', 'SenseVoice int8 多語模型'],
    'moruAsrSenseVoiceDescription': ['Chinese, English, Cantonese, Japanese and Korean. Download: about 166 MB.', 'Китайский, английский, кантонский, японский и корейский языки. Загрузка: около 166 МБ.', '支持中文、英文、粤语、日语和韩语，下载约 166 MB', '支援中文、英文、粵語、日語和韓語，下載約 166 MB'],
    'moruAsrZipformerName': ['Zipformer Chinese/English Mobile', 'Zipformer — китайский и английский, Mobile', 'Zipformer 中英 Mobile', 'Zipformer 中英 Mobile'],
    'moruAsrZipformerDescription': ['Streaming Chinese and English recognition. Download: about 347 MB.', 'Потоковое распознавание китайской и английской речи. Загрузка: около 347 МБ.', '中英双语流式识别，下载约 347 MB', '中英雙語串流辨識，下載約 347 MB'],
}
for path in (root / 'lib/l10n').glob('app_*.arb'):
    index = {'en': 0, 'ru': 1, 'zh': 2, 'zh_Hans': 2, 'zh_Hant': 3}[path.stem.removeprefix('app_')]
    data = json.loads(path.read_text())
    for key, translations in messages.items():
        data[key] = translations[index]
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')

def edit(path, old, new, count=1):
    p = root / path
    text = p.read_text()
    if old not in text and new in text:
        return
    assert text.count(old) == count, (path, old, text.count(old))
    p.write_text(text.replace(old, new))

edit('lib/shared/widgets/markdown_with_highlight.dart',
     "  return zh ? '代码' : 'Code';",
     "  return AppLocalizations.of(context)?.moruCodeBlockLabel ??\n      (zh ? '代码' : 'Code');")
edit('lib/features/settings/widgets/asr_services_section.dart',
     "import 'voice_service_widgets.dart';",
     "import 'voice_service_widgets.dart';\nimport '../utils/sherpa_model_l10n.dart';")
edit('lib/features/settings/widgets/asr_services_section.dart',
     '                  model.name,',
     '                  model.localizedName(l10n),')
edit('lib/features/settings/widgets/asr_services_section.dart',
     '            model.description,',
     '            model.localizedDescription(l10n),')
print('Translated code-fence fallback and all three speech-model display entries; model definitions untouched.')
