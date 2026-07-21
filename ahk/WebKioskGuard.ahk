; Web Kiosk Guard (AutoHotkey v1.1) — guards the machine's installed Chrome.
;
; What it does:
;   * launches Chrome fullscreen (--kiosk) on a configured URL, in an isolated
;     profile so it never mixes with the user's normal Chrome windows,
;   * keeps that window always-on-top so nothing covers it,
;   * relaunches it automatically if it ever closes/crashes,
;   * blocks the usual close shortcuts (Alt+F4 / Ctrl+W),
;   * exits ONLY via a hidden hotkey (default Ctrl+Alt+Shift+Q).
;
; Runs on old Windows (7/8.1) and new alike — no Python, no api-ms-win-* DLLs.
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
global gMarker := gUserDataDir   ; unique per-profile dir; identifies OUR Chrome

; ---------------- Hotkeys ----------------
Hotkey, %gExitHotkey%, DoExit
if (gBlockClose) {
    Hotkey, !F4, BlockKey       ; Alt+F4
    Hotkey, ^w,  BlockKey       ; Ctrl+W
    Hotkey, ^+w, BlockKey       ; Ctrl+Shift+W
    Hotkey, ^F4, BlockKey       ; Ctrl+F4
}

; ---------------- Start + guard loop ----------------
LaunchChrome()
Sleep, 4000

Loop {
    if (!gRunning)
        break
    hwnds := GetKioskWindows()
    if (hwnds.Length() = 0) {
        LaunchChrome()          ; window gone -> bring it back
        Sleep, 5000             ; give Chrome time to open before re-checking
    } else {
        for i, h in hwnds
            WinSet, AlwaysOnTop, On, ahk_id %h%
        Sleep, %gPollMs%
    }
}
ExitApp

; ======================= subroutines =======================

DoExit:
    gRunning := false
    for i, h in GetKioskWindows()
        WinClose, ahk_id %h%
    KillKioskChrome()
    ExitApp
return

BlockKey:
return

; ======================= functions =======================

LaunchChrome() {
    global gChromePath, gUrl, gUserDataDir
    q := Chr(34)   ; double-quote
    flags := "--kiosk --new-window --no-first-run --no-default-browser-check "
           . "--disable-session-crashed-bubble --disable-infobars "
           . "--disable-features=TranslateUI --overscroll-history-navigation=0"
    cmd := q gChromePath q " " flags " --user-data-dir=" q gUserDataDir q " " q gUrl q
    Run, %cmd%,,, pid
}

; Return an array of HWNDs for the kiosk Chrome window(s) we launched.
; Uses WMI to match only chrome.exe processes whose command line contains our
; unique user-data-dir, so the user's other Chrome windows are ignored.
GetKioskWindows() {
    global gMarker
    hwnds := []
    pids := {}
    wmiOk := false
    try {
        col := ComObjGet("winmgmts:\\.\root\cimv2").ExecQuery(""
            . "SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name = 'chrome.exe'")
        wmiOk := true
        for proc in col {
            cl := proc.CommandLine
            if (cl != "" && InStr(cl, gMarker))
                pids[proc.ProcessId + 0] := true
        }
    } catch e {
        wmiOk := false
    }

    WinGet, list, List, ahk_class Chrome_WidgetWin_1
    Loop, %list% {
        h := list%A_Index%
        WinGetTitle, t, ahk_id %h%
        if (t = "")
            continue
        WinGet, pid, PID, ahk_id %h%
        if (wmiOk) {
            if (pids.HasKey(pid + 0))
                hwnds.Push(h)
        } else {
            ; WMI unavailable: best-effort, accept any titled Chrome window.
            hwnds.Push(h)
        }
    }
    return hwnds
}

KillKioskChrome() {
    global gMarker
    try {
        for proc in ComObjGet("winmgmts:\\.\root\cimv2").ExecQuery(""
            . "SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name = 'chrome.exe'") {
            if (proc.CommandLine != "" && InStr(proc.CommandLine, gMarker))
                proc.Terminate()
        }
    } catch e {
    }
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
