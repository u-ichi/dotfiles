#!/usr/bin/env bash
# mise 経由で Nodefile に列挙した Node.js の版を導入する
#
# プロジェクトの .node-version / .nvmrc が要求する版を揃えるためのもので、mise の global tool
# には登録しない。版指定の無い場所では mise の shims が PATH 上の次の node (Homebrew) へ fallback する。

ensure_node_versions() {
  local nodefile="$SCRIPT_DIR/Nodefile"

  if [ ! -f "$nodefile" ]; then
    return 0
  fi

  if ! command -v mise &>/dev/null; then
    echo "スキップ: mise がインストールされていません"
    return 0
  fi

  echo "--- Node.js (mise) ---"
  while IFS= read -r version || [ -n "$version" ]; do
    [[ -z "$version" || "$version" =~ ^# ]] && continue
    echo "導入:     node@$version"
    mise install "node@$version"
  done < "$nodefile"
  echo "導入済み:"
  mise ls --installed node
  echo ""
}
