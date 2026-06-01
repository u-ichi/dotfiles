#!/usr/bin/env python3
"""tmux copy-mode の visual wrap 改行を除去して clipboard へ送る。"""

from __future__ import annotations

import os
import subprocess
import sys
import unicodedata


def resolve_pane_width() -> int | None:
    if len(sys.argv) > 1 and sys.argv[1].isdigit():
        width = int(sys.argv[1])
        return width if width > 0 else None

    pane = os.environ.get("TMUX_PANE")
    if not pane:
        return None

    try:
        width_text = subprocess.check_output(
            ["tmux", "display-message", "-p", "-t", pane, "#{pane_width}"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.SubprocessError):
        return None

    if not width_text.isdigit():
        return None
    width = int(width_text)
    return width if width > 0 else None


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


def reflow_soft_wraps(text: str, pane_width: int | None) -> str:
    if pane_width is None:
        return text

    result: list[str] = []
    for raw_line in text.splitlines(keepends=True):
        content, eol = split_eol(raw_line)
        result.append(content)
        if not eol:
            continue

        # tmux copy-mode は soft wrap も改行として pipe する。
        # pane 幅ちょうどで終わる visual line だけを折返しとみなし、次行へ結合する。
        if cell_width(content) >= pane_width:
            continue
        result.append(eol)

    return "".join(result)


def load_tmux_buffer(text: str) -> bool:
    if not os.environ.get("TMUX"):
        return False
    try:
        subprocess.run(
            ["tmux", "load-buffer", "-w", "-"],
            input=text,
            text=True,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except OSError:
        return False
    except subprocess.CalledProcessError:
        return False


def write_clipboard(text: str) -> int:
    if os.environ.get("TMUX_COPY_REFLOW_STDOUT") == "1":
        sys.stdout.write(text)
        return 0

    tmux_clipboard_ok = load_tmux_buffer(text)
    try:
        subprocess.run(["pbcopy"], input=text, text=True, check=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        if tmux_clipboard_ok:
            return 0
        print(f"pbcopy failed: {exc}", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    text = sys.stdin.read()
    return write_clipboard(reflow_soft_wraps(text, resolve_pane_width()))


if __name__ == "__main__":
    raise SystemExit(main())
