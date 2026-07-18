#!/usr/bin/env bash
# Herdr 本体と GitHub plugin の明示導入・同期補助

HERDR_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERDR_PLUGIN_FILE="${HERDR_PLUGIN_FILE:-$HERDR_MODULE_DIR/Herdrfile}"

ensure_herdr() {
  # Homebrew formula は `herdr update --handoff` (プロセスを生かしたまま server を
  # 差し替える live handoff 更新) の対象外のため、公式 installer 管理に切り替えた。
  # installer はバイナリを ~/.local/bin/herdr に置くだけで shell rc は書き換えない。
  # 以後の更新は `herdr update` が自己管理する。
  if [ -x "$HOME/.local/bin/herdr" ]; then
    echo "済み:     herdr ($("$HOME/.local/bin/herdr" --version 2>/dev/null || echo '不明'))"
  else
    echo "インストール: Herdr"
    local tmpfile
    tmpfile="$(mktemp)"
    curl -fsSL https://herdr.dev/install.sh -o "$tmpfile"
    echo "ダウンロード完了: $tmpfile"
    sh "$tmpfile"
    rm -f "$tmpfile"
  fi

  # installer は shell rc を変更しないため、新規導入直後の同一 process でも
  # plugin 同期が公式配置先の herdr を使えるようにする。
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac

  # 旧 Homebrew 版が残っていると PATH 順 (/opt/homebrew/bin が ~/.local/bin より先) で
  # brew 版が優先されるため、残骸を検知したら警告する。
  if brew list herdr &>/dev/null; then
    echo "  警告: Homebrew 版 herdr が残っています。~/.local/bin 版を有効にするには"
    echo "        brew uninstall herdr を実行してください"
  fi
}

_herdr_plugin_snapshot() {
  local plugin_id="$1"

  python3 -c '
import json
import sys

plugin_id = sys.argv[1]
data = json.load(sys.stdin)
result = data.get("result")
if not isinstance(result, dict) or not isinstance(result.get("plugins"), list):
    raise SystemExit("Herdr plugin list response has no result.plugins array")

for plugin in result["plugins"]:
    if plugin.get("plugin_id") != plugin_id:
        continue
    source = plugin.get("source") or {}
    values = (
        plugin.get("version") or "",
        source.get("requested_ref") or "",
        source.get("resolved_commit") or "",
        source.get("owner") or "",
        source.get("repo") or "",
    )
    print("\t".join(values))
    break
' "$plugin_id"
}

_herdr_plugin_list() {
  local plugin_id="$1"
  herdr plugin list --plugin "$plugin_id" --json
}

sync_herdr_plugins() {
  if ! command -v herdr &>/dev/null; then
    echo "エラー: herdr が PATH 上にありません" >&2
    return 1
  fi
  if ! command -v python3 &>/dev/null; then
    echo "エラー: plugin 一覧の JSON 解析に python3 が必要です" >&2
    return 1
  fi
  if [ ! -f "$HERDR_PLUGIN_FILE" ]; then
    echo "エラー: Herdr plugin 固定一覧がありません: $HERDR_PLUGIN_FILE" >&2
    return 1
  fi

  echo "--- Herdr plugins ---"
  local sync_status=0
  local line plugin_id source expected_version expected_ref extra
  local json snapshot installed_version installed_ref installed_commit installed_owner installed_repo
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue

    IFS='|' read -r plugin_id source expected_version expected_ref extra <<< "$line"
    if [ -n "${extra:-}" ] || [ -z "$plugin_id" ] || [ -z "$source" ] || [ -z "$expected_version" ] || [ -z "$expected_ref" ]; then
      echo "エラー: Herdrfile の行が不正です: $line" >&2
      sync_status=1
      continue
    fi

    if ! json="$(_herdr_plugin_list "$plugin_id" 2>/dev/null)"; then
      echo "エラー: $plugin_id の Herdr plugin 一覧を取得できません" >&2
      sync_status=1
      continue
    fi
    if ! snapshot="$(printf '%s\n' "$json" | _herdr_plugin_snapshot "$plugin_id" 2>&1)"; then
      echo "エラー: $plugin_id の Herdr plugin 一覧を解析できません: $snapshot" >&2
      sync_status=1
      continue
    fi

    if [ -z "$snapshot" ]; then
      echo "導入:     $plugin_id ($expected_version, ref=$expected_ref)"
      if ! CDPATH='' herdr plugin install "$source" --ref "$expected_ref" --yes; then
        echo "エラー:   $plugin_id のインストール失敗" >&2
        sync_status=1
        continue
      fi
      if ! json="$(_herdr_plugin_list "$plugin_id" 2>/dev/null)" || ! snapshot="$(printf '%s\n' "$json" | _herdr_plugin_snapshot "$plugin_id" 2>&1)"; then
        echo "エラー:   $plugin_id のインストール後 read-back に失敗しました" >&2
        sync_status=1
        continue
      fi
    fi

    installed_version=""
    installed_ref=""
    installed_commit=""
    installed_owner=""
    installed_repo=""
    if [ -n "$snapshot" ]; then
      IFS=$'\t' read -r installed_version installed_ref installed_commit installed_owner installed_repo <<< "$snapshot"
    fi

    if [ "$installed_version" = "$expected_version" ] \
      && [ "$installed_ref" = "$expected_ref" ] \
      && [ "$installed_commit" = "$expected_ref" ] \
      && [ "$installed_owner/$installed_repo" = "$source" ]; then
      echo "済み:     $plugin_id ($installed_version, commit=$installed_commit)"
    else
      echo "差異:     $plugin_id"
      echo "  期待:   version=$expected_version source=$source ref=$expected_ref"
      echo "  実際:   version=${installed_version:-未確認} source=${installed_owner:-未確認}/${installed_repo:-未確認} requested_ref=${installed_ref:-未確認} resolved_commit=${installed_commit:-未確認}"
      echo "  自動削除・再導入はしません。既存 plugin を確認してから手動で判断してください" >&2
      sync_status=1
    fi
  done < "$HERDR_PLUGIN_FILE"

  return "$sync_status"
}

# all は他の dotfiles 同期を止めない。専用 mode は sync_herdr_plugins の非0をそのまま返す。
sync_herdr_plugins_for_all() {
  if sync_herdr_plugins; then
    return 0
  fi

  echo "警告:     Herdr plugin 同期に失敗しました。通常導入の残りは継続します" >&2
  return 0
}

sync_herdr_files() {
  echo "--- Herdr 設定ファイルコピー ---"
  local entry src dest
  for entry in "${COPY_ENTRIES[@]}"; do
    src="${entry%%:*}"
    dest="${entry#*:}"
    if [[ "$src" == .config/herdr/* ]]; then
      copy_item "$src" "$dest"
    fi
  done
  echo ""
}
