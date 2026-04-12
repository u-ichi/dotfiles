#!/usr/bin/env bash
# Codex CLI の設定を展開する（install.sh から読み込み）

# ~/.codex/config.toml に注入するグローバル設定
# プロジェクト固有の [projects.*] や [plugins.*] はマシン依存のため管理外
CODEX_GLOBAL_SETTINGS=(
  "tool_output_token_limit = 25000"
  "model_auto_compact_token_limit = 128000"
)

ensure_codex_config() {
  local config_dir="$HOME/.codex"
  local config_file="$config_dir/config.toml"

  mkdir -p "$config_dir"

  if [ ! -f "$config_file" ]; then
    # config.toml が存在しない → 新規作成
    echo "作成:     $config_file"
    for line in "${CODEX_GLOBAL_SETTINGS[@]}"; do
      echo "$line" >> "$config_file"
    done
    echo "" >> "$config_file"
    return
  fi

  # config.toml が存在する → 不足している設定を先頭に追加
  local missing=()
  for line in "${CODEX_GLOBAL_SETTINGS[@]}"; do
    local key="${line%% =*}"
    if ! grep -q "^${key} " "$config_file"; then
      missing+=("$line")
    else
      echo "済み:     $key"
    fi
  done

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
