#!/usr/bin/env bash
# Codex CLI の設定を展開する（install.sh / update.sh から読み込み）
# テンプレート: .config/codex/config.toml

CODEX_TEMPLATE="$SCRIPT_DIR/.config/codex/config.toml"

ensure_codex_config() {
  local config_dir="$HOME/.codex"
  local config_file="$config_dir/config.toml"

  if [ ! -f "$CODEX_TEMPLATE" ]; then
    echo "スキップ: テンプレートが見つかりません ($CODEX_TEMPLATE)"
    return
  fi

  mkdir -p "$config_dir"

  if [ ! -f "$config_file" ]; then
    echo "作成:     $config_file"
    cp "$CODEX_TEMPLATE" "$config_file"
    return
  fi

  # 既存の config.toml にテンプレートの設定を補完する
  local missing=()
  while IFS= read -r line; do
    # コメント行・空行はスキップ
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    local key="${line%% =*}"
    if ! grep -q "^${key} " "$config_file"; then
      missing+=("$line")
    else
      echo "済み:     $key"
    fi
  done < "$CODEX_TEMPLATE"

  if [ ${#missing[@]} -eq 0 ]; then
    return
  fi

  # 不足分を先頭に挿入
  local tmpfile
  tmpfile="$(mktemp)"
  for line in "${missing[@]}"; do
    echo "追加:     $line"
    echo "$line" >> "$tmpfile"
  done
  echo "" >> "$tmpfile"
  cat "$config_file" >> "$tmpfile"
  mv "$tmpfile" "$config_file"
}
