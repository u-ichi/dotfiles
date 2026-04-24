#!/usr/bin/env bash
# tfenv 経由で Terraform 最新版を導入・更新する

ensure_terraform_latest() {
  if ! command -v tfenv &>/dev/null; then
    echo "スキップ: tfenv がインストールされていません"
    return 0
  fi
  tfenv install latest
  tfenv use latest
  echo "バージョン: $(terraform version | head -1)"
}
