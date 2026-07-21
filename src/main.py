"""Web Kiosk Guard — entry point.

Opens a configured URL in a fullscreen WebView2 (Edge) window and guards it:
  * the window cannot be closed (X / Alt+F4 are cancelled),
  * it is continuously re-asserted as topmost so nothing covers it,
  * only a hidden hotkey (default Ctrl+Alt+Shift+Q) performs a real exit.

A thin supervisor layer restarts the app if the process itself dies unexpectedly
(crash or Task Manager kill), so the only way it stays closed is the hidden
hotkey. Run with `python src/main.py [url]`.
"""
from __future__ import annotations

import os
import subprocess
import sys
import threading
import time

# Allow running both as `python src/main.py` and as a frozen exe.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import Config, load_config  # noqa: E402

# Exit code the child returns after a legitimate (hotkey) quit. Any other exit
# code is treated by the supervisor as a crash worth restarting.
EXIT_INTENTIONAL = 0
EXIT_CRASH = 1
RESTART_DELAY_SEC = 2.0
CHILD_ENV_FLAG = "WEBKIOSK_CHILD"


# --------------------------------------------------------------------------- #
# Supervisor (parent process)
# --------------------------------------------------------------------------- #
def _child_command() -> list[str]:
    if getattr(sys, "frozen", False):
        return [sys.executable, *sys.argv[1:]]
    return [sys.executable, os.path.abspath(__file__), *sys.argv[1:]]


def run_supervisor() -> int:
    """Spawn the kiosk child and restart it until it exits intentionally."""
    cmd = _child_command()
    env = dict(os.environ, **{CHILD_ENV_FLAG: "1"})
    while True:
        result = subprocess.run(cmd, env=env)
        if result.returncode == EXIT_INTENTIONAL:
            return EXIT_INTENTIONAL
        time.sleep(RESTART_DELAY_SEC)  # brief backoff before relaunch


# --------------------------------------------------------------------------- #
# Kiosk (child process)
# --------------------------------------------------------------------------- #
def run_kiosk(cfg: Config) -> int:
    import webview  # imported here so the supervisor path needn't load it

    from guard import start_topmost_guard
    from hotkey import register_exit_hotkey

    quit_requested = threading.Event()
    stop_guard = threading.Event()

    window = webview.create_window(
        title=cfg.title,
        url=cfg.url,
        fullscreen=cfg.fullscreen,
        frameless=cfg.frameless,
        on_top=True,
    )

    def on_closing():
        # pywebview cancels the close when the handler returns False.
        # Allow it through only after the hidden hotkey requested a real exit.
        return quit_requested.is_set()

    window.events.closing += on_closing

    def request_quit():
        quit_requested.set()
        stop_guard.set()
        try:
            window.destroy()
        except Exception:
            pass

    hotkey_ok = register_exit_hotkey(cfg.exit_hotkey, request_quit)
    if not hotkey_ok:
        # Not fatal: the window still runs, but log so the operator knows the
        # escape hatch is unavailable on this machine (see README fallback).
        print(
            f"[web-kiosk-guard] WARNING: could not register exit hotkey "
            f"'{cfg.exit_hotkey}'. Exit only via Task Manager.",
            file=sys.stderr,
        )

    start_topmost_guard(cfg.title, cfg.topmost_interval_sec, stop_guard)

    # Blocks until the window is destroyed.
    webview.start()

    stop_guard.set()
    return EXIT_INTENTIONAL if quit_requested.is_set() else EXIT_CRASH


def main() -> int:
    cfg = load_config()
    is_child = os.environ.get(CHILD_ENV_FLAG) == "1"
    if cfg.auto_restart_on_crash and not is_child:
        return run_supervisor()
    return run_kiosk(cfg)


if __name__ == "__main__":
    sys.exit(main())
