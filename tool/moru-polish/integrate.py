"""Temporary GitHub-only integration; removed from the final commit."""
from pathlib import Path
import json
import subprocess

root = Path.cwd()
def git(*args, check=True):
    return subprocess.run(['git', *args], check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def read_stage(stage, path):
    result = git('show', f':{stage}:{path}', check=False)
    return json.loads(result.stdout) if result.returncode == 0 else {}

def merge_reviewed(sha):
    result = git('merge', '--no-ff', '--no-commit', sha, check=False)
    conflicts = git('diff', '--name-only', '--diff-filter=U').stdout.splitlines()
    if result.returncode and not conflicts:
        raise RuntimeError(result.stdout + result.stderr)
    for path in conflicts:
        assert path.startswith('lib/l10n/') and path.endswith(('.arb', '.dart')), f'Unexpected source conflict: {path}'
        if path.endswith('.arb'):
            base, ours, theirs = [read_stage(stage, path) for stage in (1, 2, 3)]
            absent = object()
            merged = {}
            for key in dict.fromkeys([*ours, *theirs]):
                b, o, t = [value.get(key, absent) for value in (base, ours, theirs)]
                if o == t:
                    value = o
                elif o == b:
                    value = t
                elif t == b:
                    value = o
                else:
                    raise AssertionError(f'Conflicting translation requires review: {path}: {key}')
                if value is not absent:
                    merged[key] = value
            Path(path).write_text(json.dumps(merged, ensure_ascii=False, indent=2) + '\n')
        else:
            # Generated getters are regenerated immediately from the merged ARBs.
            git('checkout', '--ours', '--', path)
        git('add', path)
    if (root / '.git/MERGE_HEAD').exists():
        subprocess.run(['flutter', 'gen-l10n'], check=True)
        git('add', 'lib/l10n')
        git('diff', '--check')
        git('commit', '-m', 'merge: preserve reviewed localization and Android-only work')

# Both source commits were read and reviewed before selecting them here.
merge_reviewed('8219ccd630007ee537b8c77d83245f14157808f6')
merge_reviewed('63aa1f33bf90d1d9d986ccb52e2f07dcfd2e1028')

workflow = Path('.github/workflows/pr-check.yml')
text = workflow.read_text()
anchor = '      - name: Dart format (changed files only)\n'
addition = '''      - name: Validate complete Russian catalog and validator regressions
        run: |
          python3 tool/test_check_moru_ru.py
          python3 tool/check_moru_ru.py

'''
assert text.count(anchor) == 1
if addition not in text:
    workflow.write_text(text.replace(anchor, addition + anchor, 1))

catalog = json.loads(Path('lib/l10n/app_ru.arb').read_text())
count = sum(not key.startswith('@') for key in catalog)
Path('docs/MORU_RUSSIAN_LOCALIZATION.md').write_text(f'''# Moru: Russian Android presentation

The Russian catalog contains {count} messages and uses Flutter ARB/gen-l10n, not runtime string replacement. English and Chinese remain available. New installations default to Russian; an explicitly saved language or system-language choice is preserved.

## Scope

The catalog covers chat, settings, assistants, providers/OAuth, models, MCP, workspace/terminal, skills, memory, search, backups, diagnostics presentation, tooltips and accessibility labels. Confirmed hardcoded mobile strings have been connected to the same generated catalog, including notification channels, search-service fields, provider notices, local speech-model descriptions, palette names and code-block fallback labels.

Model IDs, download URLs, language identifiers in code fences, tool/protocol schemas, raw server diagnostics, user content and model-facing source prompts are not translated. A user-created theme or assistant name remains user data. Android notification and overlay labels continue to come from the Flutter localization path.

## Verification

The PR gate checks exact EN/RU message parity, duplicate keys, nonempty values, ICU argument/placeholder preservation and explicitly documented technical-English exceptions. The validator has mutation tests. Flutter generates the Dart getters; generated output must match committed ARB files.

Runtime/widget tests cover Russian plurals, default/saved/system language, RU-to-EN switching, settings search and Android back navigation, notifications, palette IDs, code-fence language preservation and speech-model metadata preservation. The last three presentation gaps were reproduced before their fixes in Actions run 35096372942 (three failures; the existing English code-fence case passed).

The final PR must also pass the full analyzer and Flutter suite, Android JVM tests and the real single-arm64 APK verification. Test-source presence is not a claim that all tests passed; read the final-head Actions results. No physical-device test is claimed here.

## Android-only distribution

PR #1's Android-only configuration is preserved. Only one arm64-v8a APK is produced; no iOS, desktop or Nightly build. The Linux environment inside Android, PRoot, PTY and STDIO MCP remain functional features, not separate desktop products. Package identity, release certificate and persisted data are unchanged by this localization patch.

A debug CI artifact is not a signed stable release. Stable publication still requires the existing permanent signing configuration and public certificate pin; no rotating debug key is substituted for it.
''')

for path in ('tool/moru-translation-stage', 'tool/moru-polish', '.github/workflows/moru-l10n-development.yml', '.github/workflows/moru-polish-development.yml'):
    if Path(path).exists():
        git('rm', '-r', '--', path)
print(f'Integrated reviewed branches; {count} RU messages; temporary generators removed.')
