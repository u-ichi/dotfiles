#!/usr/bin/env bash
# dotfiles 日次メンテナンス LaunchAgent の同期関数

install_dotfiles_daily_maintenance() {
  local daily_dest="$HOME/.local/bin/dotfiles-daily-maintenance"
  local cleanup_dest="$HOME/.local/bin/dotfiles-cleanup-local-disk"
  local env_file="$HOME/.config/dotfiles-maintenance/env"
  local plist_src="$DOTFILES_DIR/.config/launchd/com.u-kt.dotfiles-daily-maintenance.plist"
  local plist_dest="$HOME/Library/LaunchAgents/com.u-kt.dotfiles-daily-maintenance.plist"
  local service
  service="gui/$(id -u)/com.u-kt.dotfiles-daily-maintenance"
  local launchctl_bin="${DOTFILES_MAINTENANCE_LAUNCHCTL_BIN:-launchctl}"

  copy_item "scripts/daily-maintenance.sh" "$daily_dest"
  copy_item "scripts/cleanup-local-disk.sh" "$cleanup_dest"
  chmod 755 "$daily_dest" "$cleanup_dest"

  mkdir -p "$HOME/.config/dotfiles-maintenance" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/dotfiles"
  if [ ! -f "$env_file" ]; then
    cat > "$env_file" <<'EOF'
SLACK_BOT_TOKEN=
SLACK_CHANNEL_ID=
DOTFILES_MAINTENANCE_CODEX_PROFILE=routine
DOTFILES_MAINTENANCE_SKIP_SLACK=0
EOF
    chmod 600 "$env_file"
    echo "作成:     $env_file"
  else
    chmod 600 "$env_file" 2>/dev/null || true
    echo "済み:     $env_file"
  fi

  local rendered
  rendered="$(mktemp)"
  sed -e "s|@@HOME@@|$HOME|g" -e "s|@@DOTFILES_DIR@@|$DOTFILES_DIR|g" "$plist_src" > "$rendered"
  plutil -lint "$rendered" >/dev/null

  if [ -f "$plist_dest" ] && cmp -s "$rendered" "$plist_dest"; then
    echo "済み:     $plist_dest"
  else
    cp "$rendered" "$plist_dest"
    echo "コピー:   $plist_dest ← $plist_src"
  fi
  rm -f "$rendered"

  if command -v "$launchctl_bin" &>/dev/null; then
    "$launchctl_bin" bootout "gui/$(id -u)" "$plist_dest" 2>/dev/null || true
    if "$launchctl_bin" bootstrap "gui/$(id -u)" "$plist_dest" 2>/dev/null; then
      "$launchctl_bin" enable "$service" 2>/dev/null || true
      echo "読込:     $service"
    else
      echo "警告:     dotfiles daily maintenance LaunchAgent の読込に失敗"
      echo "          手動確認: $launchctl_bin bootstrap gui/$(id -u) $plist_dest"
    fi
  fi
}
