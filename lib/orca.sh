#!/usr/bin/env bash
# Orca のフォント導入と、管理する設定項目だけの適用。

ensure_orca_font() {
  if ! command -v brew &>/dev/null; then
    echo "エラー: Homebrew がインストールされていません" >&2
    return 1
  fi
  local font_brewfile
  mkdir -p "$SCRIPT_DIR/tmp"
  font_brewfile="$(mktemp "$SCRIPT_DIR/tmp/orca-font.XXXXXX")"
  if ! grep -Fx "cask 'font-moralerspace-hw'" "$SCRIPT_DIR/Brewfile" > "$font_brewfile"; then
    rm -f "$font_brewfile"
    echo "エラー: Brewfile に font-moralerspace-hw が登録されていません" >&2
    return 1
  fi
  if ! brew bundle --file="$font_brewfile" --no-upgrade; then
    rm -f "$font_brewfile"
    return 1
  fi
  rm -f "$font_brewfile"
}

sync_orca_settings() {
  if ! command -v python3 &>/dev/null; then
    echo "エラー: python3 がインストールされていません" >&2
    return 1
  fi
  python3 "$SCRIPT_DIR/scripts/apply-orca-settings.py" "$SCRIPT_DIR/.config/orca/settings.json" "$@"
}
