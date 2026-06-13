#!/usr/bin/env bash
# Docker Desktop 設定の適用関数

# Docker Desktop の AutoStart を有効化する
# 設定ファイル: ~/Library/Group Containers/group.com.docker/settings-store.json
ensure_docker_autostart() {
  local settings_file="$HOME/Library/Group Containers/group.com.docker/settings-store.json"

  if [ ! -f "$settings_file" ]; then
    echo "スキップ: Docker Desktop がインストールされていません"
    return 0
  fi

  local current
  current=$(python3 -c "import json; print(json.load(open('$settings_file')).get('AutoStart', False))")

  if [ "$current" = "True" ]; then
    echo "済み:     Docker Desktop AutoStart"
  else
    echo "設定:     Docker Desktop AutoStart = true"
    python3 -c "
import json, pathlib
p = pathlib.Path('$settings_file')
d = json.loads(p.read_text())
d['AutoStart'] = True
p.write_text(json.dumps(d, indent=2) + '\n')
"
  fi
}

install_docker_disk_maintenance() {
  local script_dest="$HOME/.local/bin/docker-disk-maintenance"
  local plist_src="$DOTFILES_DIR/.config/launchd/com.u-kt.docker-disk-maintenance.plist"
  local plist_dest="$HOME/Library/LaunchAgents/com.u-kt.docker-disk-maintenance.plist"
  local service
  service="gui/$(id -u)/com.u-kt.docker-disk-maintenance"

  copy_item "scripts/docker-disk-maintenance.sh" "$script_dest"
  chmod 755 "$script_dest"

  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/dotfiles"

  local rendered
  rendered="$(mktemp)"
  sed "s|@@HOME@@|$HOME|g" "$plist_src" > "$rendered"
  plutil -lint "$rendered" >/dev/null

  if [ -f "$plist_dest" ] && cmp -s "$rendered" "$plist_dest"; then
    echo "済み:     $plist_dest"
  else
    cp "$rendered" "$plist_dest"
    echo "コピー:   $plist_dest ← $plist_src"
  fi
  rm -f "$rendered"

  if command -v launchctl &>/dev/null; then
    launchctl bootout "gui/$(id -u)" "$plist_dest" 2>/dev/null || true
    if launchctl bootstrap "gui/$(id -u)" "$plist_dest" 2>/dev/null; then
      launchctl enable "$service" 2>/dev/null || true
      echo "読込:     $service"
    else
      echo "警告:     Docker disk maintenance LaunchAgent の読込に失敗"
      echo "          手動確認: launchctl bootstrap gui/$(id -u) $plist_dest"
    fi
  fi
}
