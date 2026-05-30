#!/usr/bin/env bash
# Python automation dependencies managed by uv

ensure_python_tools() {
  local pythonfile="$SCRIPT_DIR/Pythonfile"
  local venv_dir="${DOTFILES_PYTHON_VENV:-$HOME/.local/share/dotfiles/python-tools}"
  local bin_dir="$HOME/.local/bin"

  if [ ! -f "$pythonfile" ]; then
    return 0
  fi

  if ! command -v uv &>/dev/null; then
    echo "エラー: uv が見つかりません。Brewfile を反映してから再実行してください"
    return 1
  fi

  echo "=== Python automation packages ==="
  mkdir -p "$bin_dir"
  uv venv --allow-existing "$venv_dir"
  uv pip install --python "$venv_dir/bin/python" -r "$pythonfile"
  rm -f "$bin_dir/dotfiles-python"
  cat > "$bin_dir/dotfiles-python" <<EOF
#!/usr/bin/env bash
exec "$venv_dir/bin/python" "\$@"
EOF
  chmod +x "$bin_dir/dotfiles-python"
  echo "済み:     $bin_dir/dotfiles-python"
  echo ""
}
