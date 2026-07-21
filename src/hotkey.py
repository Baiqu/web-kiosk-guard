"""Global hidden hotkey that triggers a legitimate exit.

Uses the ``keyboard`` library so the combo fires even when the kiosk window does
not have focus. If a locked-down environment blocks its low-level hook, see the
RegisterHotKey fallback note in README.md.
"""
from __future__ import annotations

from typing import Callable

try:
    import keyboard
except ImportError:  # Non-Windows dev machine.
    keyboard = None


def register_exit_hotkey(combo: str, on_trigger: Callable[[], None]) -> bool:
    """Register ``combo`` (e.g. 'ctrl+alt+shift+q') to call ``on_trigger``.

    Returns True if the hotkey was registered, False if unavailable (e.g. the
    ``keyboard`` module is missing or the hook was refused).
    """
    if keyboard is None:
        return False
    try:
        keyboard.add_hotkey(combo, on_trigger)
        return True
    except Exception:
        return False
