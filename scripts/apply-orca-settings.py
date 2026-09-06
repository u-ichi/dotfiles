#!/usr/bin/env python3
"""管理するフォント設定だけを、終了中の Orca に反映する。"""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import tempfile


def apply_settings(config_path, allow_skip=False):
    updates = json.loads(config_path.read_text())
    if (set(updates) != {'terminalFontFamily', 'terminalFontSize'}
            or not isinstance(updates['terminalFontFamily'], str)
            or not updates['terminalFontFamily'].strip()
            or type(updates['terminalFontSize']) is not int
            or updates['terminalFontSize'] <= 0):
        raise ValueError('フォント名と正の整数のフォントサイズを指定してください')
    user_data = Path(os.environ.get('ORCA_USER_DATA_PATH',
                                   Path.home() / 'Library/Application Support/orca'))
    metadata_path = user_data / 'orca-runtime.json'
    running = False
    if metadata_path.exists():
        metadata = json.loads(metadata_path.read_text())
        try:
            os.kill(int(metadata['pid']), 0)
        except ProcessLookupError:
            pass
        else:
            running = True

    data_path = user_data / 'orca-data.json'
    index_path = user_data / 'orca-profile-index.json'
    if index_path.exists():
        index = json.loads(index_path.read_text())
        profile_id = index['activeProfileId']
        if (not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,127}', profile_id)
                or not any(p['id'] == profile_id for p in index['profiles'])):
            raise ValueError('Orca の選択中プロファイルを確認できません')
        data_path = user_data / 'profiles' / profile_id / 'orca-data.json'
    if not data_path.exists():
        print('未適用: Orca の初回起動・終了後に ./install.sh orca を実行してください', file=sys.stderr)
        return 0 if allow_skip else 1

    state = json.loads(data_path.read_text())
    settings = state['settings']
    if all(settings.get(key) == value for key, value in updates.items()):
        print('済み:     Orca のフォント設定は管理ファイルと一致しています')
        return 0
    if running:
        print('未適用: Orca を終了してから ./install.sh orca を実行してください', file=sys.stderr)
        return 0 if allow_skip else 1
    settings.update(updates)
    # 同じディレクトリで置換し、保存途中の JSON を残さない。
    descriptor, temporary_path = tempfile.mkstemp(prefix='.orca-dotfiles-', dir=data_path.parent)
    try:
        with os.fdopen(descriptor, 'w') as output:
            json.dump(state, output, ensure_ascii=False, indent=2)
            output.write('\n')
        os.replace(temporary_path, data_path)
    finally:
        Path(temporary_path).unlink(missing_ok=True)
    actual = json.loads(data_path.read_text())['settings']
    if any(actual.get(key) != value for key, value in updates.items()):
        raise RuntimeError('Orca の保存済みフォント設定が一致しません')
    print(f"適用済み: Orca {actual['terminalFontFamily']} / {actual['terminalFontSize']} px")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path)
    parser.add_argument('--allow-skip', action='store_true',
                        help='起動中・初回起動前は未適用を表示して正常終了する')
    args = parser.parse_args()
    try:
        return apply_settings(args.config, args.allow_skip)
    except (OSError, ValueError, KeyError, TypeError, RuntimeError):
        print('エラー: Orca の設定ファイルまたは終了状態を確認できませんでした', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
