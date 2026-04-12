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
