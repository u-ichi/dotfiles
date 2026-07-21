#!/usr/bin/env bash
# macOS defaults 設定の定義と適用関数（install.sh から読み込み）

# 設定定義: "ドメイン キー 型 値 説明"
# 型: -bool, -int, -float, -string
DEFAULTS=(
  # Google Drive: フォルダ名を英語（My Drive）に固定する
  # ローカライズされた名前（マイドライブ）だと repo パスの扱いが壊れるため
  "com.google.drivefs.settings DisableLocalizedVirtualFolders -bool true"
)

SPOTLIGHT_NEVER_INDEX_RELATIVE_PATHS=(
  ".git"
  ".obsidian"
  "Daily/attachments"
)

apply_defaults() {
  for entry in "${DEFAULTS[@]}"; do
    local domain key type value
    read -r domain key type value <<< "$entry"

    local current
    current=$(defaults read "$domain" "$key" 2>/dev/null || echo "")

    # defaults read の戻り値を期待値と比較
    local expected
    case "$type" in
      -bool)
        if [ "$value" = "true" ]; then expected="1"; else expected="0"; fi
        ;;
      *)
        expected="$value"
        ;;
    esac

    if [ "$current" = "$expected" ]; then
      echo "済み:     $domain $key"
    else
      echo "設定:     $domain $key = $value"
      defaults write "$domain" "$key" "$type" "$value"
    fi
  done
}

apply_spotlight_never_index() {
  local vault relative_path target marker
  local vault_found=0

  for vault in "$HOME"/Library/CloudStorage/GoogleDrive-*/"My Drive"/Obsidian/u1memo; do
    [ -d "$vault" ] || continue
    vault_found=1

    for relative_path in "${SPOTLIGHT_NEVER_INDEX_RELATIVE_PATHS[@]}"; do
      target="$vault/$relative_path"
      if [ ! -d "$target" ]; then
        echo "スキップ: Spotlight 除外対象がありません: $target"
        continue
      fi

      marker="$target/.metadata_never_index"
      if [ -e "$marker" ]; then
        echo "済み:     $marker"
      else
        : > "$marker"
        chmod 600 "$marker"
        echo "作成:     $marker"
      fi
    done
  done

  if [ "$vault_found" -eq 0 ]; then
    echo "スキップ: Google Drive の Obsidian/u1memo がありません"
  fi
}
