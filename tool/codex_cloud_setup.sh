#!/usr/bin/env bash
# Prepares a cloud coding container (no preinstalled Flutter, no root) to run
# the pre-commit checklist from AGENTS.md. Installs the exact Flutter version
# CI uses, verified against the official release manifest, outside the
# repository, then resolves packages the same way CI does.
#
#   bash tool/codex_cloud_setup.sh
#   source "${MORU_TOOLCHAINS:-$HOME/.moru-toolchains}/activate.sh"
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n "s/^ *FLUTTER_VERSION: *'\([0-9.]*\)'.*/\1/p" \
  "$repo/.github/workflows/pr-check.yml")
[ -n "$version" ] || { echo 'FLUTTER_VERSION not found in pr-check.yml' >&2; exit 1; }

toolchains=${MORU_TOOLCHAINS:-$HOME/.moru-toolchains}
flutter_home="$toolchains/flutter-$version"
case "$flutter_home/" in
  "$repo"/*) echo "MORU_TOOLCHAINS must be outside the repository" >&2; exit 1 ;;
esac
mkdir -p "$toolchains"

if [ ! -x "$flutter_home/bin/flutter" ]; then
  base=https://storage.googleapis.com/flutter_infra_release/releases
  archive="stable/linux/flutter_linux_$version-stable.tar.xz"
  download=$(mktemp -d "$toolchains/download.XXXXXX")
  trap 'rm -rf "$download"' EXIT
  curl -fLsS "$base/releases_linux.json" -o "$download/releases.json"
  curl -fLsS "$base/$archive" -o "$download/flutter.tar.xz"
  python3 - "$download" "$version" "$archive" <<'PY'
import hashlib, json, sys
download, version, archive = sys.argv[1:]
manifest = json.load(open(f'{download}/releases.json'))
release = next(r for r in manifest['releases']
               if r['version'] == version and r['channel'] == 'stable')
assert release['archive'] == archive, release['archive']
with open(f'{download}/flutter.tar.xz', 'rb') as file:
    actual = hashlib.file_digest(file, 'sha256').hexdigest()
assert actual == release['sha256'], 'Flutter archive SHA-256 mismatch'
PY
  tar -xJf "$download/flutter.tar.xz" -C "$download"
  rm -rf "$flutter_home"
  mv "$download/flutter" "$flutter_home"
fi

cat > "$toolchains/activate.sh" <<EOF
export PATH="$flutter_home/bin:\$PATH"
EOF
# shellcheck source=/dev/null
source "$toolchains/activate.sh"
git config --global --add safe.directory "$flutter_home"
flutter config --no-analytics >/dev/null
flutter --version

cd "$repo"
flutter pub get
