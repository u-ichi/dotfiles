#!/usr/bin/env bash
# symlink 定義と作成関数（install.sh / update.sh 共通）

# macOS APFS は NFD、readlink は NFC を返す場合があるため統一する
_normalize() { iconv -f utf-8-mac -t utf-8 2>/dev/null <<< "$1" || echo "$1"; }

DOTFILES_DIR="$(_normalize "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)")"

# links.conf からリンク定義を読み込む
_load_links() {
  local conf="$DOTFILES_DIR/links.conf"
  LINKS=()
  while IFS= read -r line; do
    # 空行・コメント行をスキップ
    [[ -z "${line// /}" || "$line" =~ ^[[:space:]]*# ]] && continue
    local src dest
    src="$(echo "${line%%:*}" | xargs)"
    dest="$(echo "${line#*:}" | xargs)"
    # シェル変数を展開
    dest="${dest//\$HOME/$HOME}"
    dest="${dest//\$DOTFILES_DIR/$DOTFILES_DIR}"
    LINKS+=("$src:$dest")
  done < "$conf"
}
_load_links

# リンク先の親ディレクトリが DOTFILES_DIR へのシンボリックリンクの場合、
# 実ディレクトリに変換する（ディレクトリリンク → 個別ファイルリンク移行用）
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

create_link() {
  local src="$DOTFILES_DIR/$1"
  local dest="$2"

  if [ ! -e "$src" ]; then
    echo "スキップ: $src が存在しません"
    return
  fi

  # 親ディレクトリが DOTFILES_DIR へのリンクなら実ディレクトリに変換
  ensure_real_parent "$dest"

  # リンク先の親ディレクトリを作成
  mkdir -p "$(dirname "$dest")"

  if [ -L "$dest" ]; then
    # 既にリンク済みか確認（パス比較 + inode フォールバック）
    local resolved_dest
    resolved_dest="$(readlink "$dest")"
    if [ "$resolved_dest" = "$src" ]; then
      echo "済み:     $dest"
      return
    fi
    # パスが異なっても同じファイルを指していればリンク済みとみなす
    if [ -e "$dest" ] && [ "$(stat -f '%i' "$src")" = "$(stat -f '%i' "$dest")" ]; then
      echo "済み:     $dest"
      return
    fi
  elif [ -e "$dest" ] && [ "$(stat -f '%i' "$src" 2>/dev/null)" = "$(stat -f '%i' "$dest" 2>/dev/null)" ]; then
    # 宛先が通常ファイルでソースと同一 inode → ディレクトリリンク経由で
    # リポジトリ内のファイルを直接参照している（ln -sf すると破壊される）
    echo "エラー:   $dest がリポジトリのファイルと同一です（親ディレクトリの symlink 解除が必要）"
    return 1
  fi

  # 既存ファイル/ディレクトリがある場合はバックアップ
  if [ -e "$dest" ] || [ -L "$dest" ]; then
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
  fi

  ln -sf "$src" "$dest"
  echo "作成:     $dest → $src"
}

sync_links() {
  for entry in "${LINKS[@]}"; do
    local src="${entry%%:*}"
    local dest="${entry#*:}"
    create_link "$src" "$dest"
  done
}
