#!/usr/bin/env bash
# Antigravity CLI の導入と、追加クレジット消費の設定。

ensure_antigravity() {
  local antigravity_brewfile
  mkdir -p "$SCRIPT_DIR/tmp"
  antigravity_brewfile="$(mktemp "$SCRIPT_DIR/tmp/antigravity.XXXXXX")"
  if ! grep -Fx "cask 'antigravity-cli'" "$SCRIPT_DIR/Brewfile" > "$antigravity_brewfile"; then
    rm -f "$antigravity_brewfile"
    echo "エラー: Brewfile に antigravity-cli が登録されていません" >&2
    return 1
  fi
  if ! brew bundle --file="$antigravity_brewfile" --no-upgrade; then
    rm -f "$antigravity_brewfile"
    return 1
  fi
  rm -f "$antigravity_brewfile"
}

sync_antigravity_settings() {
  python3 - "$SCRIPT_DIR/.config/antigravity/settings.json" "$HOME/.gemini/antigravity-cli/settings.json" <<'PYTHON'
import json
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
managed = json.loads(source.read_text())
settings = json.loads(destination.read_text()) if destination.exists() else {}
settings.update(managed)
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(settings, indent=2, ensure_ascii=False) + "\n")
assert all(json.loads(destination.read_text())[key] == value for key, value in managed.items())
print("Antigravity CLI: 管理する設定を適用しました (useG1Credits=false)")
PYTHON
}
