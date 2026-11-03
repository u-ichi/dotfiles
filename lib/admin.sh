#!/usr/bin/env bash
# 管理者権限 (sudo) が要る導入処理
# 引数なしの install.sh では実行せず、パスワードを入力できる時に ./install.sh sudo で実行する。

# Brewfile の tap を登録する（未登録の tap の cask は brew info で引けないため）
tap_brewfile_taps() {
  local tap
  while IFS= read -r tap; do
    brew tap "$tap"
  done < <(sed -n "s/^tap '\([^']*\)'$/\1/p" "$1")
}

# path の置き先 (存在する最も近い親 directory) に今のユーザーで書き込めるかを確かめる
target_writable() {
  local dir="${1/#\~/$HOME}"
  dir="$(dirname "$dir")"
  while [ ! -e "$dir" ]; do
    dir="$(dirname "$dir")"
  done
  [ -w "$dir" ]
}

# Brewfile の cask のうち、導入・更新で sudo を求めるものを出力する。
# 対象は、インストーラ (pkg / installer) で入るものと、置き先に書き込めない場所を含むもの
# (例: Docker Desktop の /usr/local/bin)。通常の brew bundle から外す。
list_admin_casks() {
  local brewfile="$1"
  local casks=()
  local cask
  while IFS= read -r cask; do
    casks+=("$cask")
  done < <(sed -n "s/^cask '\([^']*\)'$/\1/p" "$brewfile")
  [ "${#casks[@]}" -eq 0 ] && return 0
  # インストーラ形式は置き先を空で、それ以外は置き先を 1 行ずつ「cask<TAB>置き先」で出す
  brew info --cask --json=v2 "${casks[@]}" \
    | jq -r '.casks[] | .full_token as $token
        | if ([.artifacts[] | objects | keys[]] | any(. == "pkg" or . == "installer")) then "\($token)\t"
          else ([.artifacts[] | .. | objects | .target? | if type == "object" then .path? else . end | strings] | unique | .[] | "\($token)\t\(.)")
          end' \
    | while IFS=$'\t' read -r cask target; do
        if [ -z "$target" ] || ! target_writable "$target"; then
          echo "$cask"
        fi
      done \
    | uniq
}

# Brewfile から指定した cask の行を除いて書き出す
write_brewfile_without_casks() {
  local brewfile="$1" dest="$2"
  shift 2
  local patterns=()
  local cask
  for cask in "$@"; do
    patterns+=(-e "cask '$cask'")
  done
  if [ "${#patterns[@]}" -eq 0 ]; then
    cp "$brewfile" "$dest"
  else
    grep -v -Fx "${patterns[@]}" "$brewfile" > "$dest"
  fi
}

# Brewfile の cask_args・tap と、指定した cask の行だけを書き出す
write_brewfile_with_casks() {
  local brewfile="$1" dest="$2"
  shift 2
  grep -E '^(cask_args|tap) ' "$brewfile" > "$dest" || true
  local cask
  for cask in "$@"; do
    grep -Fx "cask '$cask'" "$brewfile" >> "$dest"
  done
}

# 管理者権限が要る cask のうち未導入のものを案内する
report_missing_admin_casks() {
  local installed
  local missing=()
  local cask
  installed="$(brew list --cask -1 2>/dev/null)"
  for cask in "$@"; do
    grep -Fqx "${cask##*/}" <<< "$installed" || missing+=("$cask")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    echo "済み:     管理者権限が要る cask ($#件) は導入済み。更新は ./install.sh sudo で行う"
  else
    echo "スキップ: 管理者権限が要るため未導入: ${missing[*]}"
    echo "          パスワードを入力できる時に ./install.sh sudo で導入する"
  fi
}

# mkcert のローカル CA がシステムに登録済みかを、パスワードなしで確認する
mkcert_ca_installed() {
  security find-certificate -c "mkcert" /Library/Keychains/System.keychain &>/dev/null
}

# 管理者権限が要る処理をまとめて実行する。パスワードは最初の 1 回だけ求める。
run_admin_tasks() {
  local brewfile="$1"

  echo "--- 管理者権限が要る導入 ---"
  sudo -v
  # 実行中は sudo の認証を延長し、途中でパスワードを再び求めないようにする
  while sudo -n true 2>/dev/null; do sleep 50; done &
  local keepalive=$!
  # shellcheck disable=SC2064 # keepalive の PID を trap 設定時に確定させる
  trap "kill $keepalive 2>/dev/null || true" EXIT

  tap_brewfile_taps "$brewfile"
  local casks=()
  local cask
  while IFS= read -r cask; do
    casks+=("$cask")
  done < <(list_admin_casks "$brewfile")

  if [ "${#casks[@]}" -gt 0 ]; then
    echo "対象:     ${casks[*]}"
    mkdir -p "$SCRIPT_DIR/tmp"
    local admin_brewfile
    admin_brewfile="$(mktemp "$SCRIPT_DIR/tmp/brew-admin.XXXXXX")"
    write_brewfile_with_casks "$brewfile" "$admin_brewfile" "${casks[@]}"
    brew bundle --file="$admin_brewfile"
    rm -f "$admin_brewfile"
  fi

  echo "--- mkcert ローカル CA ---"
  mkcert -install
  echo ""
}
