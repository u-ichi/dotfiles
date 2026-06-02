#!/usr/bin/env bash
# 設定ファイル定義とコピー同期関数（install.sh から読み込み）

# macOS APFS は NFD、readlink は NFC を返す場合があるため統一する
_normalize() { iconv -f utf-8-mac -t utf-8 2>/dev/null <<< "$1" || echo "$1"; }

DOTFILES_DIR="$(_normalize "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)")"

# copy.conf からコピー定義を読み込む
_load_copy_entries() {
  local conf="$DOTFILES_DIR/copy.conf"
  COPY_ENTRIES=()
  while IFS= read -r line; do
    # 空行・コメント行をスキップ
    [[ -z "${line// /}" || "$line" =~ ^[[:space:]]*# ]] && continue
    local src dest
    src="$(echo "${line%%:*}" | xargs)"
    dest="$(echo "${line#*:}" | xargs)"
    # シェル変数を展開
    dest="${dest//\$HOME/$HOME}"
    dest="${dest//\$DOTFILES_DIR/$DOTFILES_DIR}"
    COPY_ENTRIES+=("$src:$dest")
  done < "$conf"
}
_load_copy_entries

# コピー先の親ディレクトリが DOTFILES_DIR へのシンボリックリンクの場合、
# 実ディレクトリに変換する（ディレクトリリンク → 実ファイルコピー移行用）
ensure_real_parent() {
  local dest="$1"
  local dir
  dir="$(dirname "$dest")"

  while [ "$dir" != "/" ] && [ "$dir" != "$HOME" ]; do
    if [ -L "$dir" ]; then
      local target
      target="$(readlink "$dir")"
      # 物理パスに解決して DOTFILES_DIR と比較可能にする
      if [[ "$target" == /* ]]; then
        if [ -d "$target" ]; then
          target="$(_normalize "$(cd "$target" && pwd -P)")"
        elif [ -d "$(dirname "$target")" ]; then
          target="$(_normalize "$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")")"
        fi
      else
        target="$(_normalize "$(cd "$(dirname "$dir")" && cd "$(dirname "$target")" && pwd -P)/$(basename "$target")")"
      fi

      if [[ "$target" == "$DOTFILES_DIR"* ]]; then
        echo "移行:     $dir (ディレクトリリンク → 実ディレクトリ)"
        rm "$dir"
        mkdir -p "$dir"
        # 非管理ファイル（fish_variables, テーマ等）をリポジトリからコピー
        if [ -d "$target" ]; then
          cp -a "$target"/. "$dir/" 2>/dev/null || true
        fi
        return
      fi
    fi
    dir="$(dirname "$dir")"
  done
}

_resolve_link_target() {
  local link_path="$1"
  local target
  target="$(readlink "$link_path")"

  if [[ "$target" == /* ]]; then
    _normalize "$target"
  else
    _normalize "$(cd "$(dirname "$link_path")" && pwd -P)/$target"
  fi
}

backup_path() {
  local dest="$1"
  local backup
  backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
  echo "バックアップ: $dest → $backup"
  mv "$dest" "$backup"

  # 古いバックアップを整理（最新 3 件を残す）
  local count=0
  local old
  while IFS= read -r -d '' old; do
    count=$((count + 1))
    if [ "$count" -gt 3 ]; then
      rm -rf "$old"
    fi
  done < <(find "$(dirname "$dest")" -maxdepth 1 -name "$(basename "$dest").backup.*" -print0 | sort -zr)
}

prepare_copy_dest() {
  local src="$1"
  local dest="$2"

  # 旧 symlink 管理から実ファイルコピーへ移行する
  if [ -L "$dest" ]; then
    local target
    target="$(_resolve_link_target "$dest")"
    if [[ "$target" == "$DOTFILES_DIR"* ]]; then
      echo "移行:     $dest (リンク → コピー)"
      rm "$dest"
    else
      backup_path "$dest"
    fi
  fi

  if [ -d "$src" ]; then
    if [ -e "$dest" ] && [ ! -d "$dest" ]; then
      backup_path "$dest"
    fi
    mkdir -p "$dest"
  else
    mkdir -p "$(dirname "$dest")"
    if [ -d "$dest" ]; then
      backup_path "$dest"
    fi
  fi
}

copy_file() {
  local src="$1"
  local dest="$2"

  prepare_copy_dest "$src" "$dest"

  if [ -e "$dest" ] && cmp -s "$src" "$dest"; then
    echo "済み:     $dest"
    return
  fi

  if [ -e "$dest" ]; then
    backup_path "$dest"
  fi

  cp -p "$src" "$dest"
  echo "コピー:   $dest ← $src"
}

copy_directory() {
  local src="$1"
  local dest="$2"

  prepare_copy_dest "$src" "$dest"

  while IFS= read -r -d '' dir; do
    local rel="${dir#"$src"/}"
    [ "$rel" = "$dir" ] && continue
    mkdir -p "$dest/$rel"
  done < <(find "$src" -type d -print0)

  while IFS= read -r -d '' file; do
    local rel="${file#"$src"/}"
    local dest_file="$dest/$rel"
    copy_file "$file" "$dest_file"
  done < <(find "$src" -type f -print0)
}

copy_item() {
  local src="$DOTFILES_DIR/$1"
  local dest="$2"

  if [ ! -e "$src" ]; then
    echo "スキップ: $src が存在しません"
    return
  fi

  # 親ディレクトリが DOTFILES_DIR へのリンクなら実ディレクトリに変換
  ensure_real_parent "$dest"

  if [ -d "$src" ]; then
    copy_directory "$src" "$dest"
  else
    copy_file "$src" "$dest"
  fi
}

sync_files() {
  for entry in "${COPY_ENTRIES[@]}"; do
    local src="${entry%%:*}"
    local dest="${entry#*:}"
    copy_item "$src" "$dest"
  done
}

cleanup_legacy_git_config_symlink() {
  local legacy="$HOME/.config/git/config"
  local managed="$DOTFILES_DIR/.config/git/config"

  [ -L "$legacy" ] || return 0

  local target
  target="$(_resolve_link_target "$legacy")"

  if [[ "$target" == "$DOTFILES_DIR"* ]] || { [ -e "$target" ] && cmp -s "$managed" "$target"; }; then
    echo "移行:     $legacy (旧 Git config リンクを削除)"
    rm "$legacy"
  else
    echo "移行:     $legacy (管理外リンクをバックアップ)"
    backup_path "$legacy"
  fi
}
