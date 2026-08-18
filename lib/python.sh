#!/usr/bin/env bash
# Python automation dependencies managed by uv
#
# 配置先は dotfiles 専用 dir (`~/.local/share/dotfiles/python-site/<X.Y>`) と、
# それを sys.path へ足す .pth を既定 python3 の user site へ置く形。
# 専用 venv に隔離すると、venv を知らない呼び出し側 (別プロジェクトの agent 等) が
# `python3 -c "import docx"` で「ライブラリの無い環境」と判断して自作に走るため、
# 素の python3 から見える場所に置く。
# Homebrew の site-packages 本体には書き込まないので brew 管理の python は壊さない。
# 導入物を dotfiles 専用 dir に閉じ込めるのは、python の version 更新時に
# 「dotfiles が入れたものだけ」を安全に捨てて入れ直せるようにするため。

# 前回の導入先を state から読み、python の minor (series) が変わっていたら
# 旧 series の導入物を捨てる。
# lxml / pillow / PyMuPDF は拡張モジュールを持ち、python の minor が変わると
# ABI 不一致で import できない。よって `brew upgrade` で python が上がった後は
# 新しい series へ入れ直す必要があり、旧 series の導入物は残しても使えない。
# 削除対象は dotfiles が作った path (専用 dir 配下 / 専用 .pth) だけに限定する。
_dotfiles_python_migrate() {
  local state_file="$1" py_series="$2" site_root="$3"

  [ -f "$state_file" ] || return 0

  local previous_series="" previous_target="" previous_pth="" line
  while IFS= read -r line; do
    case "$line" in
    series=*) previous_series="${line#series=}" ;;
    target=*) previous_target="${line#target=}" ;;
    pth=*) previous_pth="${line#pth=}" ;;
    esac
  done <"$state_file"

  if [ -z "$previous_series" ] || [ "$previous_series" = "$py_series" ]; then
    return 0
  fi

  echo "検出:     python $previous_series → $py_series (導入し直します)"

  case "$previous_target" in
  "$site_root"/*)
    if [ -d "$previous_target" ]; then
      rm -rf "$previous_target"
      echo "掃除:     $previous_target"
    fi
    ;;
  esac

  case "$previous_pth" in
  */dotfiles-python-tools.pth)
    if [ -f "$previous_pth" ]; then
      rm -f "$previous_pth"
      echo "掃除:     $previous_pth"
    fi
    ;;
  esac
}

ensure_python_tools() {
  local pythonfile="$SCRIPT_DIR/Pythonfile"

  if [ ! -f "$pythonfile" ]; then
    return 0
  fi

  if ! command -v uv &>/dev/null; then
    echo "エラー: uv が見つかりません。Brewfile を反映してから再実行してください"
    return 1
  fi

  local python_bin
  python_bin="$(command -v python3 || true)"
  if [ -z "$python_bin" ]; then
    echo "エラー: python3 が見つかりません。Brewfile を反映してから再実行してください"
    return 1
  fi

  local py_series full_version user_site
  py_series="$("$python_bin" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
  full_version="$("$python_bin" -c 'import platform; print(platform.python_version())')"
  # user site の path は python の minor を含む (例: ~/Library/Python/3.14/...)。
  # 実行時に python 自身へ問い合わせるので、brew が python を上げた後の
  # install.sh 実行で新しい path へ自動的に追随する。
  user_site="$("$python_bin" -c 'import site; print(site.getusersitepackages())')"

  local site_root="${DOTFILES_PYTHON_SITE_ROOT:-$HOME/.local/share/dotfiles/python-site}"
  local target="$site_root/$py_series"
  local state_file="$site_root/state"
  local pth_file="$user_site/dotfiles-python-tools.pth"

  echo "=== Python automation packages ==="
  echo "対象:     $python_bin ($full_version)"

  mkdir -p "$site_root"
  _dotfiles_python_migrate "$state_file" "$py_series" "$site_root"

  mkdir -p "$target" "$user_site"
  uv pip install --python "$python_bin" --target "$target" -r "$pythonfile" || return 1

  printf '%s\n' "$target" >"$pth_file"
  printf 'series=%s\ntarget=%s\npth=%s\n' "$py_series" "$target" "$pth_file" >"$state_file"

  # 旧方式 (専用 venv + dotfiles-python wrapper) の残骸を掃除する。
  # wrapper が残ると古い venv の python を指し続けるため削除する。
  rm -f "$HOME/.local/bin/dotfiles-python"

  echo "済み:     $target"
  echo "          $pth_file 経由で $python_bin から import 可能"
  echo ""
}
