#!/bin/bash
# 内蔵データ領域の Spotlight 索引を停止し、read-back で確認する管理元。
# 対象: ルート (/) と /System/Volumes/Data。
# Data 直下に mds 認識済みの .metadata_never_index を置き、mdutil -i off の復帰差を縮める。
# RAM ボリューム・索引データ削除・mds launchd 無効化は行わない。

set -euo pipefail

MDUTIL="${SPOTLIGHT_MDUTIL:-/usr/bin/mdutil}"
UNAME_BIN="${SPOTLIGHT_UNAME:-/usr/bin/uname}"
# テスト用: SPOTLIGHT_EUID で root 判定を差し替えられる
EFFECTIVE_UID="${SPOTLIGHT_EUID:-$EUID}"
# Data ボリューム直下の永続除外マーカー（テストは SPOTLIGHT_MARKER で差し替え）
MARKER="${SPOTLIGHT_MARKER:-/System/Volumes/Data/.metadata_never_index}"

# APFS の system と Data を明示対象にする（マシン固有 path は書かない）
TARGET_VOLUMES=(
  "/"
  "/System/Volumes/Data"
)

usage() {
  cat <<'EOF'
Usage: disable-spotlight-indexing.sh [--dry-run] <apply|status|verify|help>

  apply   管理者権限で Data の .metadata_never_index を作成したあと、
          対象ボリュームに mdutil -i off を適用し、disabled と marker を read-back する
  status  対象ボリュームの索引状態と marker 有無を表示する（権限不要）
  verify  全対象が Indexing disabled かつ marker が存在するなら 0
  help    このヘルプ

環境変数:
  SPOTLIGHT_MDUTIL  mdutil 実行ファイル（既定: /usr/bin/mdutil）
  SPOTLIGHT_UNAME   uname 実行ファイル（既定: /usr/bin/uname）
  SPOTLIGHT_EUID    root 判定に使う UID（テスト用。既定: $EUID）
  SPOTLIGHT_MARKER  .metadata_never_index の path（既定: /System/Volumes/Data/.metadata_never_index）

対象ボリューム: / と /System/Volumes/Data
EOF
}

require_darwin() {
  local os
  os="$("$UNAME_BIN" 2>/dev/null || true)"
  if [[ "$os" != "Darwin" ]]; then
    echo "macOS 専用です (uname=$os)" >&2
    return 1
  fi
}

require_root_for_apply() {
  if [[ "$EFFECTIVE_UID" -ne 0 ]]; then
    echo "管理者権限で実行してください (uid=$EFFECTIVE_UID)。部分適用は行いません。" >&2
    return 1
  fi
}

# mdutil -s の1ボリューム分出力から「索引が disabled」かどうかを判定する。
# 成功（mdutil バイナリ / 実測に基づく）:
#   - "Indexing disabled."
#   - "Indexing and searching disabled."
#   - "Indexing and searching disabled because of .metadata_never_index file at root of volume."
# 拒否: "Spotlight server is disabled."（別文言・偽陽性）
volume_is_disabled() {
  local status_text="$1"
  if printf '%s\n' "$status_text" | grep -Eiq \
    'Indexing and searching disabled|Indexing disabled|索引(作成)?が?無効|無効になって'; then
    return 0
  fi
  return 1
}

volume_is_enabled() {
  local status_text="$1"
  if printf '%s\n' "$status_text" | grep -Eiq 'Indexing enabled|索引(作成)?が?有効|有効になって'; then
    return 0
  fi
  return 1
}

marker_present() {
  [[ -e "$MARKER" ]]
}

# root 確認後に呼ぶ。失敗時は mdutil を始めない。
create_marker() {
  local parent
  parent="$(dirname "$MARKER")"
  if [[ ! -d "$parent" ]]; then
    echo "FAIL: marker 親ディレクトリがありません: $parent" >&2
    return 1
  fi
  if ! : >"$MARKER" 2>/dev/null; then
    echo "FAIL: .metadata_never_index を作成できません: $MARKER" >&2
    return 1
  fi
  if ! marker_present; then
    echo "FAIL: marker 作成後も存在しません: $MARKER" >&2
    return 1
  fi
  echo "marker created: $MARKER"
}

require_marker() {
  if marker_present; then
    echo "marker present: $MARKER"
    return 0
  fi
  echo "FAIL: marker がありません: $MARKER (.metadata_never_index)" >&2
  return 1
}

read_volume_status() {
  local volume="$1"
  # -s は非 root でも状態表示できることが多い
  "$MDUTIL" -s "$volume" 2>&1
}

print_status() {
  local volume status_text
  for volume in "${TARGET_VOLUMES[@]}"; do
    status_text="$(read_volume_status "$volume")"
    printf '%s\n' "$status_text"
  done
  if marker_present; then
    echo "marker present: $MARKER"
  else
    echo "marker absent: $MARKER"
  fi
}

verify_all_disabled() {
  local volume status_text failed=0
  for volume in "${TARGET_VOLUMES[@]}"; do
    status_text="$(read_volume_status "$volume")"
    printf '%s\n' "$status_text"
    if volume_is_disabled "$status_text"; then
      continue
    fi
    if volume_is_enabled "$status_text"; then
      echo "FAIL: $volume は Indexing enabled のままです" >&2
      failed=1
      continue
    fi
    echo "FAIL: $volume の索引状態を判定できません:" >&2
    echo "$status_text" >&2
    failed=1
  done
  if ! require_marker; then
    failed=1
  fi
  return "$failed"
}

apply_indexing_off() {
  local volume
  local -a failures=()
  local status_text

  # marker 作成に失敗したら mdutil -i off を始めない
  create_marker || return 1

  for volume in "${TARGET_VOLUMES[@]}"; do
    if ! "$MDUTIL" -i off "$volume"; then
      failures+=("$volume: mdutil -i off が非ゼロ終了")
      continue
    fi
  done

  if ((${#failures[@]} > 0)); then
    echo "適用中に失敗しました。部分成功を成功扱いしません:" >&2
    printf '  %s\n' "${failures[@]}" >&2
    return 1
  fi

  # read-back: 全対象が disabled でなければ失敗
  local failed=0
  for volume in "${TARGET_VOLUMES[@]}"; do
    status_text="$(read_volume_status "$volume")"
    printf '%s\n' "$status_text"
    if ! volume_is_disabled "$status_text"; then
      echo "FAIL: $volume の read-back が Indexing disabled ではありません" >&2
      failed=1
    fi
  done
  if ! require_marker; then
    failed=1
  fi
  if [[ "$failed" -ne 0 ]]; then
    echo "全対象の Indexing disabled と marker を確認できませんでした。成功扱いしません。" >&2
    return 1
  fi
  echo "Spotlight indexing disabled: ${TARGET_VOLUMES[*]}"
  echo "marker: $MARKER"
}

dry_run_apply() {
  local volume
  echo "[dry-run] marker を作成する予定: $MARKER"
  echo "[dry-run] (.metadata_never_index — mds 認識済み永続除外)"
  echo "[dry-run] 次のボリュームに mdutil -i off を適用する予定です:"
  for volume in "${TARGET_VOLUMES[@]}"; do
    echo "[dry-run] $MDUTIL -i off $volume"
  done
  echo "[dry-run] 適用後に全対象の Indexing disabled と marker 存在を read-back する"
  echo "[dry-run] 副作用なし（marker 作成も mdutil -i も実行しない）"
}

main() {
  local dry_run=0
  local cmd=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        dry_run=1
        shift
        ;;
      -h|--help|help)
        usage
        return 0
        ;;
      apply|status|verify)
        cmd="$1"
        shift
        ;;
      *)
        echo "不明な引数: $1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  if [[ -z "$cmd" ]]; then
    cmd="apply"
  fi

  require_darwin || return 1

  case "$cmd" in
    status)
      print_status
      ;;
    verify)
      verify_all_disabled
      ;;
    apply)
      if [[ "$dry_run" -eq 1 ]]; then
        dry_run_apply
        return 0
      fi
      require_root_for_apply || return 1
      apply_indexing_off
      ;;
  esac
}

main "$@"
