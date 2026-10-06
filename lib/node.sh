#!/usr/bin/env bash
# nodenv 経由で Nodefile に列挙した Node.js の版を導入する
#
# プロジェクトの .node-version が要求する版を揃えるためのもので、既定の版 (nodenv global)
# は変えない。.node-version の無い場所では nodenv の system 解決で従来の node が使われる。

ensure_node_versions() {
  local nodefile="$SCRIPT_DIR/Nodefile"

  if [ ! -f "$nodefile" ]; then
    return 0
  fi

  if ! command -v nodenv &>/dev/null; then
    echo "スキップ: nodenv がインストールされていません"
    return 0
  fi

  echo "--- Node.js (nodenv) ---"
  while IFS= read -r version || [ -n "$version" ]; do
    [[ -z "$version" || "$version" =~ ^# ]] && continue
    echo "導入:     node $version"
    nodenv install --skip-existing "$version"
  done < "$nodefile"
  echo "導入済み: $(nodenv versions --bare | tr '\n' ' ')"
  echo ""
}
