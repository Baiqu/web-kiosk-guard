"""Keep the kiosk window on top of every other window (Windows-only).

pywebview's ``on_top=True`` sets the topmost flag once at creation, but other
apps can briefly raise their own topmost windows above it. A background thread
re-asserts HWND_TOPMOST on our window every ``interval`` seconds so anything
that jumps in front gets pushed back down within one tick.

Focus is deliberately NOT stolen (SWP_NOACTIVATE) — re-topmosting is enough to
satisfy "not covered" without hijacking the keyboard from the user.
"""
from __future__ import annotations

import threading
import time

try:
    import win32con
    import win32gui
except ImportError:  # Non-Windows dev machine — thread becomes a no-op.
    win32con = None
    win32gui = None


def _find_hwnd_by_title(title: str) -> int | None:
    if win32gui is None:
        return None
    match: list[int] = []

    def _cb(hwnd, _):
        if not win32gui.IsWindowVisible(hwnd):
            return
        if win32gui.GetWindowText(hwnd) == title:
            match.append(hwnd)

    win32gui.EnumWindows(_cb, None)
    return match[0] if match else None


def _reassert_topmost(hwnd: int) -> None:
    win32gui.SetWindowPos(
        hwnd,
        win32con.HWND_TOPMOST,
        0, 0, 0, 0,
        win32con.SWP_NOMOVE | win32con.SWP_NOSIZE | win32con.SWP_NOACTIVATE,
    )


def start_topmost_guard(title: str, interval: float, stop_event: threading.Event) -> threading.Thread:
    """Spawn a daemon thread that keeps the window titled ``title`` topmost."""

    def _loop():
        if win32gui is None:
            return  # Not on Windows; nothing to guard.
        while not stop_event.is_set():
            hwnd = _find_hwnd_by_title(title)
            if hwnd:
                try:
                    _reassert_topmost(hwnd)
                except Exception:
                    pass  # Window may be mid-teardown; retry next tick.
            stop_event.wait(interval)

    t = threading.Thread(target=_loop, name="topmost-guard", daemon=True)
    t.start()
    return t
