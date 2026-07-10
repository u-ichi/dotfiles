#!/usr/bin/env python3
"""herdr 内の TUI 表示幅で混入した改行を clipboard 上で除去する。"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import unicodedata
from typing import Any


TUI_HORIZONTAL_CHROME_WIDTH = 4
CONTINUATION_MARGIN_WIDTH = 2


def cell_width(text: str) -> int:
    width = 0
    for char in text:
        if char == "\t":
            width += 8 - (width % 8)
            continue
        if unicodedata.combining(char):
            continue
        if unicodedata.category(char).startswith("C"):
            continue
        width += 2 if unicodedata.east_asian_width(char) in {"F", "W"} else 1
    return width


def split_eol(line: str) -> tuple[str, str]:
    if line.endswith("\r\n"):
        return line[:-2], "\r\n"
    if line.endswith("\n") or line.endswith("\r"):
        return line[:-1], line[-1]
    return line, ""


def strip_continuation_margin(line: str) -> str:
    removable = min(len(line) - len(line.lstrip(" ")), CONTINUATION_MARGIN_WIDTH)
    return line[removable:]


def reflow_visual_wraps(text: str, pane_rect_width: int | None) -> str:
    if pane_rect_width is None or pane_rect_width <= TUI_HORIZONTAL_CHROME_WIDTH:
        return text

    wrap_width = pane_rect_width - TUI_HORIZONTAL_CHROME_WIDTH
    lines = text.splitlines(keepends=True)
    result: list[str] = []
    strip_next_margin = False

    for raw_line in lines:
        content, eol = split_eol(raw_line)
        visual_width = cell_width(content)
        if strip_next_margin:
            content = strip_continuation_margin(content)
            strip_next_margin = False

        result.append(content)
        if not eol:
            continue

        # Codex などの TUI は pane 内側に左右 1 セルずつ余白を持ち、表示幅で
        # 明示改行する。その幅まで埋まった行だけを visual wrap とみなす。
        if visual_width >= wrap_width:
            strip_next_margin = True
            continue
        result.append(eol)

    return "".join(result)


def pane_rect_width(payload: dict[str, Any], pane_id: str) -> int | None:
    panes = payload.get("result", {}).get("layout", {}).get("panes", [])
    for pane in panes:
        if pane.get("pane_id") != pane_id:
            continue
        width = pane.get("rect", {}).get("width")
        return width if isinstance(width, int) and width > 0 else None
    return None


def resolve_pane_rect_width() -> int | None:
    pane_id = os.environ.get("HERDR_ACTIVE_PANE_ID")
    if not pane_id:
        return None

    herdr = os.environ.get("HERDR_BIN_PATH", "herdr")
    try:
        completed = subprocess.run(
            [herdr, "pane", "layout", "--pane", pane_id],
            check=True,
            capture_output=True,
            text=True,
        )
        payload = json.loads(completed.stdout)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        return None
    return pane_rect_width(payload, pane_id)


def main() -> int:
    try:
        clipboard = subprocess.run(
            ["pbpaste"], check=True, capture_output=True, text=True
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"pbpaste failed: {exc}", file=sys.stderr)
        return 1

    rect_width = resolve_pane_rect_width()
    if rect_width is None:
        print("active herdr pane width is unavailable", file=sys.stderr)
        return 1

    reflowed = reflow_visual_wraps(clipboard, rect_width)
    try:
        subprocess.run(["pbcopy"], input=reflowed, check=True, text=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"pbcopy failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
