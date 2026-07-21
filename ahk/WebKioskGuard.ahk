; Web Kiosk Guard (AutoHotkey v1.1) — guards the machine's installed Chrome.
;
; What it does:
;   * launches Chrome fullscreen (--kiosk) on a configured URL, in an isolated
;     profile so it never mixes with the user's normal Chrome windows,
;   * remembers THAT window's handle and keeps it always-on-top,
;   * relaunches it only if that window actually closes/crashes,
;   * blocks the usual close shortcuts (Alt+F4 / Ctrl+W),
;   * exits ONLY via a hidden hotkey (default Ctrl+Alt+Shift+Q).
;
; Detection is by window handle — no WMI, no page-title dependency — so it does
; NOT keep reloading the page. Runs on old Windows (7/8.1) and new alike.
; Settings live in config.ini next to the exe.

#NoEnv
#SingleInstance Force
#Persistent
SetBatchLines, -1
SetTitleMatchMode, 2

; ---------------- Load config.ini (falls back to defaults) ----------------
global ConfigFile := A_ScriptDir . "\config.ini"
IniRead, gUrl,         %ConfigFile%, kiosk, url,              https://example.com
IniRead, gExitHotkey,  %ConfigFile%, kiosk, exit_hotkey,     ^!+q
IniRead, gPollMs,      %ConfigFile%, kiosk, poll_ms,         1000
IniRead, gChromePath,  %ConfigFile%, kiosk, chrome_path,     %A_Space%
IniRead, gUserDataDir, %ConfigFile%, kiosk, user_data_dir,   %A_Space%
IniRead, gBlockClose,  %ConfigFile%, kiosk, block_close_keys, 1

gUrl := Trim(gUrl)
gChromePath := Trim(gChromePath)
gUserDataDir := Trim(gUserDataDir)
if (gChromePath = "" || gChromePath = "ERROR")
    gChromePath := DetectChrome()
if (gUserDataDir = "" || gUserDataDir = "ERROR")
    gUserDataDir := A_ScriptDir . "\chrome-kiosk-profile"

if (gChromePath = "" || !FileExist(gChromePath)) {
    MsgBox, 16, Web Kiosk Guard, Chrome was not found.`n`nSet chrome_path in config.ini to the full path of chrome.exe.
    ExitApp
}

global gRunning := true
global gWin := 0    ; HWND of the kiosk Chrome window we manage

; ---------------- Hotkeys ----------------
Hotkey, %gExitHotkey%, DoExit
if (gBlockClose) {
    Hotkey, !F4, BlockKey       ; Alt+F4
    Hotkey, ^w,  BlockKey       ; Ctrl+W
    Hotkey, ^+w, BlockKey       ; Ctrl+Shift+W
    Hotkey, ^F4, BlockKey       ; Ctrl+F4
}

; ---------------- Start + guard loop ----------------
StartKiosk()

Loop {
    if (!gRunning)
        break
    if (gWin && WinExist("ahk_id " . gWin)) {
        WinSet, AlwaysOnTop, On, % "ahk_id " . gWin   ; keep it above everything
        Sleep, %gPollMs%
    } else {
        StartKiosk()                                  ; window gone -> bring it back
        Sleep, 1000
    }
}
ExitApp

; ======================= subroutines =======================

DoExit:
    gRunning := false
    if (gWin && WinExist("ahk_id " . gWin))
        WinClose, % "ahk_id " . gWin                  ; closing the kiosk window quits that Chrome
    ExitApp
return

BlockKey:
return

; ======================= functions =======================

; Launch Chrome and capture the handle of the NEW window it opens.
StartKiosk() {
    global gWin
    before := SnapshotChromeWindows()
    LaunchChrome()
    gWin := CaptureNewChromeWindow(before)
}

LaunchChrome() {
    global gChromePath, gUrl, gUserDataDir
    q := Chr(34)   ; double-quote
    flags := "--kiosk --new-window --no-first-run --no-default-browser-check "
           . "--disable-session-crashed-bubble --disable-infobars "
           . "--disable-features=TranslateUI --overscroll-history-navigation=0"
    cmd := q gChromePath q " " flags " --user-data-dir=" q gUserDataDir q " " q gUrl q
    Run, %cmd%,,, pid
}

; Snapshot the HWNDs of the currently-visible Chrome windows (so we can tell
; which one is newly created by our launch, and never touch the user's Chrome).
SnapshotChromeWindows() {
    snap := {}
    WinGet, list, List, ahk_class Chrome_WidgetWin_1
    Loop, %list% {
        snap[list%A_Index% + 0] := true
    }
    return snap
}

; Wait for a real Chrome window that wasn't in `before` and return its HWND.
CaptureNewChromeWindow(before) {
    Loop, 80 {                         ; up to ~20s
        WinGet, list, List, ahk_class Chrome_WidgetWin_1
        Loop, %list% {
            h := list%A_Index%
            if (before.HasKey(h + 0))
                continue
            WinGetPos,,, w, ht, ahk_id %h%
            if (w > 100 && ht > 100)   ; skip tiny helper windows
                return h
        }
        Sleep, 250
    }
    return 0
}

DetectChrome() {
    ; 1) Registry App Paths (default value holds the full chrome.exe path)
    keys := [ ["HKLM", "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"]
            , ["HKLM", "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"]
            , ["HKCU", "SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"] ]
    for i, kv in keys {
        RegRead, p, % kv[1], % kv[2]
        if (!ErrorLevel && p != "" && FileExist(p))
            return p
    }
    ; 2) Common install locations
    EnvGet, pf,   ProgramFiles
    EnvGet, pf86, ProgramFiles(x86)
    EnvGet, lad,  LocalAppData
    cands := [ pf   . "\Google\Chrome\Application\chrome.exe"
             , pf86 . "\Google\Chrome\Application\chrome.exe"
             , lad  . "\Google\Chrome\Application\chrome.exe" ]
    for i, c in cands {
        if (c != "" && FileExist(c))
            return c
    }
    return ""
}
