# Web Kiosk Guard

A small **Windows** Python app that opens a specified URL in a fullscreen browser
window (Edge **WebView2** engine) and **guards** it:

- **Can't be closed** — clicking ✕ or pressing `Alt+F4` is intercepted and cancelled.
- **Can't be covered** — the window is continuously re-asserted as *always-on-top*,
  so anything that pops in front is pushed back down within ~1 second.
- **Self-healing** — if the process itself crashes or is force-killed, a built-in
  supervisor relaunches it automatically.
- **Exit only via a hidden hotkey** — default `Ctrl+Alt+Shift+Q`.

> Designed for signage / dashboards / kiosk terminals where a web page must stay
> up and in front no matter what the user does.

---

## ⬇️ Download (Windows, no install)

**[Download the latest WebKioskGuard.exe →](https://github.com/Baiqu/web-kiosk-guard/releases/latest)**

Open that page on the Windows machine, download `WebKioskGuard.exe`, and
**double-click it** — no Python, no installer. To point it at your own page,
put `config.json` (also on the release) in the same folder and edit its `url`.

---

## Requirements

- Windows 10 (updated) or Windows 11.
- **Microsoft Edge WebView2 Runtime** — preinstalled on Win11 and updated Win10.
  If missing, install the *Evergreen Bootstrapper* from
  <https://developer.microsoft.com/microsoft-edge/webview2/>.
- Python 3.9+ (only needed to run from source or to build the `.exe`).

## Install & run from source

```bat
pip install -r requirements.txt
run.bat
```

`run.bat` reads `config.json`. To point at a URL ad-hoc without editing the file:

```bat
run.bat https://your.dashboard/page
```

## Configuration — `config.json`

| Key | Meaning | Default |
|-----|---------|---------|
| `url` | Page to open | `https://example.com` |
| `title` | Window title (used internally to keep it topmost) | `Web Kiosk Guard` |
| `fullscreen` | Fill the whole screen | `true` |
| `frameless` | Hide the window border/chrome | `true` |
| `exit_hotkey` | Hidden combo that exits the app | `ctrl+alt+shift+q` |
| `topmost_interval_sec` | How often to re-assert always-on-top | `1.0` |
| `auto_restart_on_crash` | Relaunch if the process dies unexpectedly | `true` |

## Build a standalone `.exe` (no Python on the target machine)

```bat
build.bat
```

Produces `dist\WebKioskGuard.exe`. Keep **`config.json` in the same folder as the
exe** — edit it there to change the URL. Double-click the exe to run.

## How exit works

The only clean way out is the hidden hotkey (`exit_hotkey`). Pressing it lets the
close-cancel guard through and shuts the app down for good (the supervisor sees an
intentional exit and does **not** relaunch). Any other termination — crash, or
Task Manager "End task" — is treated as a fault and the supervisor relaunches the
window within a couple of seconds.

## Troubleshooting

- **Hotkey does nothing.** Some locked-down machines block the `keyboard` library's
  low-level hook. In that case the app logs a warning and the hotkey is inactive;
  fall back to a win32 `RegisterHotKey`-based combo, or temporarily set
  `auto_restart_on_crash` to `false` and end the task from Task Manager while
  reconfiguring.
- **Window not staying on top.** Increase responsiveness by lowering
  `topmost_interval_sec` (e.g. `0.5`).
- **Blank window / WebView2 error.** Install the Edge WebView2 Runtime (see
  Requirements).

## Notes / limits

- "Can't be closed" is enforced at the application layer. Someone with admin
  rights can still force-kill via Task Manager — that is the deliberate final
  escape hatch, and the supervisor will relaunch unless you exit via the hotkey.
- The app does **not** steal keyboard focus; it only re-asserts topmost, so it
  won't interrupt typing elsewhere while still refusing to be covered.
