"""Load and validate runtime settings from config.json (with CLI url override)."""
from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass

DEFAULTS = {
    "url": "https://example.com",
    "title": "Web Kiosk Guard",
    "fullscreen": True,
    "frameless": True,
    "exit_hotkey": "ctrl+alt+shift+q",
    "topmost_interval_sec": 1.0,
    "auto_restart_on_crash": True,
}


@dataclass
class Config:
    url: str
    title: str
    fullscreen: bool
    frameless: bool
    exit_hotkey: str
    topmost_interval_sec: float
    auto_restart_on_crash: bool


def _base_dir() -> str:
    """Directory to look for config.json in.

    When frozen by PyInstaller, config.json lives next to the .exe; otherwise
    it lives at the project root (one level above this src/ file).
    """
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def config_path() -> str:
    return os.path.join(_base_dir(), "config.json")


def load_config(argv: list[str] | None = None) -> Config:
    argv = sys.argv[1:] if argv is None else argv

    data = dict(DEFAULTS)
    path = config_path()
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            file_data = json.load(f)
        if not isinstance(file_data, dict):
            raise ValueError("config.json must contain a JSON object")
        data.update({k: v for k, v in file_data.items() if k in DEFAULTS})

    # CLI: first positional arg overrides the url (handy for ad-hoc changes).
    positional = [a for a in argv if not a.startswith("-")]
    if positional:
        data["url"] = positional[0]

    cfg = Config(
        url=str(data["url"]),
        title=str(data["title"]),
        fullscreen=bool(data["fullscreen"]),
        frameless=bool(data["frameless"]),
        exit_hotkey=str(data["exit_hotkey"]),
        topmost_interval_sec=float(data["topmost_interval_sec"]),
        auto_restart_on_crash=bool(data["auto_restart_on_crash"]),
    )

    if not cfg.url:
        raise ValueError("A url must be provided via config.json or the command line")
    if cfg.topmost_interval_sec <= 0:
        raise ValueError("topmost_interval_sec must be > 0")
    return cfg
