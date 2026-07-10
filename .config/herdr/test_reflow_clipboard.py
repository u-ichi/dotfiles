#!/usr/bin/env python3

from __future__ import annotations

import unittest

from reflow_clipboard import cell_width, pane_rect_width, reflow_visual_wraps


class ReflowVisualWrapsTest(unittest.TestCase):
    def test_joins_codex_cjk_wraps_and_removes_visual_margin(self) -> None:
        first = (
            "• 意図的ではありません。現時点の verifier pane は Codex を verifier profile "
            "で起動しただけで、role 割り当て通知をま"
        )
        second = (
            "  だ送っていないため、表示名が汎用の codex のままです。ただし「profile を選んだら "
            "pane title も verifier になるべき"
        )
        third = "  か」は実装状態を直接確認します。"
        self.assertEqual(cell_width(first), 115)
        self.assertEqual(cell_width(second), 115)

        actual = reflow_visual_wraps("\n".join((first, second, third)), 119)

        self.assertEqual(actual, first + second[2:] + third[2:])

    def test_preserves_short_intentional_newlines(self) -> None:
        text = "first paragraph\nsecond paragraph\n"
        self.assertEqual(reflow_visual_wraps(text, 119), text)

    def test_removes_only_tui_margin_from_nested_indent(self) -> None:
        first = "x" * 115
        self.assertEqual(
            reflow_visual_wraps(first + "\n    nested", 119),
            first + "  nested",
        )

    def test_preserves_crlf_on_non_wrapped_lines(self) -> None:
        text = "short\r\nnext\r\n"
        self.assertEqual(reflow_visual_wraps(text, 119), text)

    def test_returns_input_when_pane_width_is_unavailable(self) -> None:
        text = "x" * 115 + "\n  y"
        self.assertEqual(reflow_visual_wraps(text, None), text)

    def test_reads_matching_pane_width_from_layout_payload(self) -> None:
        payload = {
            "result": {
                "layout": {
                    "panes": [
                        {"pane_id": "w1:p1", "rect": {"width": 80}},
                        {"pane_id": "w1:p2", "rect": {"width": 119}},
                    ]
                }
            }
        }
        self.assertEqual(pane_rect_width(payload, "w1:p2"), 119)
        self.assertIsNone(pane_rect_width(payload, "w1:p3"))


if __name__ == "__main__":
    unittest.main()
