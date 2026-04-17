#!/usr/bin/env bash
# Codex CLI の設定を展開する（install.sh / update.sh から読み込み）
# テンプレート: .config/codex/config.toml
#
# 方針: テンプレート全体を BEGIN/END マーカーで囲まれた「マネージドブロック」
# として ~/.codex/config.toml に書き込む。マシン依存の [projects.*] / [plugins.*]
# セクションはブロック外に保持する（Codex が TUI で trust 等を行った際に追記するため）。

CODEX_TEMPLATE="$SCRIPT_DIR/.config/codex/config.toml"
CODEX_BEGIN_RE='^# ====== BEGIN: managed by dotfiles'
CODEX_END_RE='^# ====== END: managed by dotfiles'

ensure_codex_config() {
  local config_dir="$HOME/.codex"
  local config_file="$config_dir/config.toml"

  if [ ! -f "$CODEX_TEMPLATE" ]; then
    echo "スキップ: テンプレートが見つかりません ($CODEX_TEMPLATE)"
    return
  fi

  mkdir -p "$config_dir"

  # 初回インストール: テンプレートをそのまま配置
  if [ ! -f "$config_file" ]; then
    cp "$CODEX_TEMPLATE" "$config_file"
    echo "作成:     $config_file"
    return
  fi

  local tmpfile
  tmpfile="$(mktemp)"

  if grep -qE "$CODEX_BEGIN_RE" "$config_file" \
     && grep -qE "$CODEX_END_RE" "$config_file"; then
    # マーカーあり: マネージドブロックをテンプレートで丸ごと置換
    awk -v tpl="$CODEX_TEMPLATE" \
        -v beg="$CODEX_BEGIN_RE" \
        -v end="$CODEX_END_RE" '
      BEGIN { in_block = 0 }
      $0 ~ beg {
        while ((getline line < tpl) > 0) print line
        close(tpl)
        in_block = 1
        next
      }
      $0 ~ end { in_block = 0; next }
      !in_block { print }
    ' "$config_file" > "$tmpfile"

    if diff -q "$config_file" "$tmpfile" > /dev/null 2>&1; then
      rm -f "$tmpfile"
      echo "済み:     $config_file"
    else
      mv "$tmpfile" "$config_file"
      echo "更新:     $config_file (マネージドブロック)"
    fi
    return
  fi

  # マーカー未検出: 既存ファイルから [projects.*] / [plugins.*] のみ抽出し、
  # テンプレートと連結する。初回のみバックアップ。
  local backup
  backup="$config_file.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$config_file" "$backup"

  cat "$CODEX_TEMPLATE" > "$tmpfile"
  echo "" >> "$tmpfile"
  awk '
    /^\[/ {
      keep = ($0 ~ /^\[projects\./ || $0 ~ /^\[plugins\./)
    }
    keep { print }
  ' "$config_file" >> "$tmpfile"

  mv "$tmpfile" "$config_file"
  echo "移行:     $config_file"
  echo "バックアップ: $backup"
}
