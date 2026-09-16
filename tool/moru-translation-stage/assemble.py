"""One-time translation staging; removed after generated sources are reviewed."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
SOURCE_SHA256 = '897528bc4d85c39e8f23ece9ece3374bab3a41e8f73adef256151d4dbdc7681e'


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        assert key not in result, f'Duplicate JSON key: {key}'
        result[key] = value
    return result


def read(path):
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_object)


source = ROOT / 'lib/l10n/app_en.arb'
assert hashlib.sha256(source.read_bytes()).hexdigest() == SOURCE_SHA256, 'English catalog changed; do not apply indexed translations to another version'
english = read(source)
messages = {key: value for key, value in english.items() if not key.startswith('@')}
values = list(dict.fromkeys(messages.values()))
assert len(messages) == 3538 and len(values) == 2884
translations = {}
for path in sorted(Path(__file__).parent.glob('ru-*.json')):
    for key, value in read(path).items():
        index = int(key)
        assert index not in translations, f'Duplicate translation index {index}'
        assert isinstance(value, str) and value.strip(), f'Empty translation {index}'
        translations[index] = value
assert set(translations) == set(range(len(values))), f'Translation indices mismatch: missing {sorted(set(range(len(values))) - translations.keys())}'
by_value = {value: translations[index] for index, value in enumerate(values)}
ru = {'@@locale': 'ru'}
for key, value in messages.items():
    ru[key] = by_value[value]
    metadata = english.get('@' + key)
    if metadata:
        ru['@' + key] = metadata
# Same English words have different grammatical roles in a few settings.
ru['assistantSettingsCopySuffix'] = 'Копия'
assert 'assistantSettingsCopySuffix' in messages
ru['memoryEntrySourceDistilled'] = 'Сформировано'
# Avoid the unnatural "каждый 21 день"; a neutral interval label works for all counts.
ru['localSnapshotIntervalDays'] = '{days, plural, =1{Каждый день} other{Интервал: {days} дн.}}'
(ROOT / 'lib/l10n/app_ru.arb').write_text(json.dumps(ru, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
unchanged = {key: ru[key] for key, value in messages.items() if value == ru[key] and re.search(r'[A-Za-z]', value)}
report_dir = ROOT / 'moru-localization-review'
report_dir.mkdir(exist_ok=True)
(report_dir / 'unchanged-candidates.json').write_text(json.dumps(unchanged, ensure_ascii=False, indent=2) + '\n')
(report_dir / 'catalog-summary.json').write_text(json.dumps({'english_messages': len(messages), 'russian_messages': len(messages), 'distinct_translations': len(translations), 'unchanged_candidates': len(unchanged)}, indent=2) + '\n')
print(f'Assembled {len(messages)} Russian messages from {len(translations)} reviewed translations; {len(unchanged)} technical exceptions require final review.')
