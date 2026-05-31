#!/usr/bin/env bash
# ファイル権限の修復
# Google Drive 同期で実行権限が落ちることがあるため復元する
# SCRIPT_DIR は呼び出し側が設定している前提

fix_permissions() {
  chmod 755 "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/lib/*.sh
  chmod +x "$SCRIPT_DIR/.config/tmux"/*.sh "$SCRIPT_DIR/hooks/pre-commit"
}
