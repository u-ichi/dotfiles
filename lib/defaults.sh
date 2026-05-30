#!/usr/bin/env bash
# macOS defaults 設定の定義と適用関数（install.sh から読み込み）

# 設定定義: "ドメイン キー 型 値 説明"
# 型: -bool, -int, -float, -string
DEFAULTS=(
  # Google Drive: フォルダ名を英語（My Drive）に固定する
  # ローカライズされた名前（マイドライブ）だと repo パスの扱いが壊れるため
  "com.google.drivefs.settings DisableLocalizedVirtualFolders -bool true"
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
