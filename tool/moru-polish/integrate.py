"""Diagnostic-only formatter export using the existing Flutter runner.

Do not merge this branch. No workflow, permissions, signing, package identity or
production branch changes are attempted. The existing always-upload step exports
review/lib and review/tests after this deliberately stopped diagnostic step.
"""
from pathlib import Path
import os
import subprocess

assert os.environ.get('GITHUB_REF_NAME') == 'feat/ru-android-polish'
source = '6f7725e72153f3e5217f8461645b31f2ca898191'
files = [
    'lib/features/settings/utils/sherpa_model_l10n.dart',
    'test/l10n/moru_android_remaining_test.dart',
    'test/l10n/moru_mobile_labels_test.dart',
    'test/l10n/moru_presentation_test.dart',
    'test/l10n/moru_russian_test.dart',
]
for path in files:
    content = subprocess.check_output(['git', 'show', f'{source}:{path}'])
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)
version = subprocess.check_output(['dart', '--version'], stderr=subprocess.STDOUT, text=True)
result = subprocess.run(['dart', 'format', *files], check=True, text=True, capture_output=True)
verification = subprocess.run(['dart', 'format', '--output=none', '--set-exit-if-changed', *files], check=True, text=True, capture_output=True)
Path('review').mkdir(exist_ok=True)
Path('review/formatter-result.txt').write_text(version + result.stdout + verification.stdout)
print(version + result.stdout + verification.stdout)
print(subprocess.check_output(['git', 'diff', '--', *files], text=True))
raise SystemExit('FORMAT_EXPORT_ONLY: stop before integration/tests/push; collect the always-upload artifact. This diagnostic run is not a green product check.')
