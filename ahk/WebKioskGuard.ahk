; Web Kiosk Guard (AutoHotkey v1.1) — guards the machine's installed Chrome.
;
; What it does:
;   * launches Chrome fullscreen (--kiosk) on a configured URL, in an isolated
;     profile so it never mixes with the user's normal Chrome windows,
;   * keeps that window always-on-top,
;   * relaunches it ONLY when our Chrome process has actually exited — so it can
;     never stack up extra windows,
;   * blocks the usual close shortcuts (Alt+F4 / Ctrl+W),
;   * exits ONLY via a hidden hotkey (default Ctrl+Alt+Shift+Q).
;
; Liveness is checked by process (Process,Exist) + window handle — no WMI, no
; page-title dependency. Runs on old Windows (7/8.1) and new alike.
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
IniRead, gRefreshSec,  %ConfigFile%, kiosk, refresh_interval_sec, 1800
IniRead, gRefreshHard, %ConfigFile%, kiosk, refresh_hard,         1
IniRead, gHideCursor,  %ConfigFile%, kiosk, hide_cursor,          1
IniRead, gAutoUpdate,  %ConfigFile%, kiosk, auto_update,          1
IniRead, gUpdateSec,   %ConfigFile%, kiosk, update_interval_sec,  86400

global gUpdateUrl := "https://github.com/Baiqu/web-kiosk-guard/releases/latest/download/WebKioskGuardAHK.exe"

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
global gWin := 0          ; HWND of the kiosk Chrome window we manage
global gPid := 0          ; PID of the Chrome process that owns that window
global gLastRefresh := 0  ; A_TickCount of the last auto-refresh (or page open)
global gLastUpdate := 0   ; A_TickCount of the last update check

; Restore the system cursor on ANY exit (hotkey, update-restart, crash-safe-ish).
OnExit("OnExitHandler")

; ---------------- Hide cursor ----------------
if (gHideCursor)
    SystemCursor(false)

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
gLastUpdate := A_TickCount
CheckUpdate()          ; check once at startup (page is already showing)

Loop {
    if (!gRunning)
        break

    MaybeUpdate()                                        ; self-upgrade on the configured interval

    if (gWin && WinExist("ahk_id " . gWin)) {
        WinSet, AlwaysOnTop, On, % "ahk_id " . gWin      ; keep it above everything
        MaybeRefresh()                                   ; reload on the configured interval
    } else {
        ; Lost the window handle. Re-adopt our process's window if it still has
        ; one; otherwise relaunch ONLY if the process is truly gone (never stack).
        h := FindWindowByPid(gPid)
        if (h) {
            gWin := h
            WinSet, AlwaysOnTop, On, % "ahk_id " . gWin
        } else if (!ProcAlive(gPid)) {
            StartKiosk()
        }
        ; else: process alive but no window yet -> wait, do NOT relaunch
    }
    Sleep, %gPollMs%
}
ExitApp

; ======================= subroutines =======================

DoExit:
    gRunning := false
    if (gWin && WinExist("ahk_id " . gWin))
        WinClose, % "ahk_id " . gWin
    else if (gPid) {
        h := FindWindowByPid(gPid)
        if (h)
            WinClose, % "ahk_id " . h
    }
    ExitApp
return

BlockKey:
return

; ======================= functions =======================

; Launch Chrome once and capture the handle + PID of the window it opens.
StartKiosk() {
    global gWin, gPid, gLastRefresh
    before := SnapshotChromeWindows()
    LaunchChrome()
    gWin := CaptureNewChromeWindow(before)
    gPid := 0
    if (gWin) {
        WinGet, p, PID, % "ahk_id " . gWin
        gPid := p
    }
    gLastRefresh := A_TickCount   ; count the refresh interval from a fresh page
}

; Reload the page on the configured interval (send a refresh key to the SAME
; window — never opens or navigates a new one). 0 = disabled.
MaybeRefresh() {
    global gRefreshSec, gLastRefresh
    if (gRefreshSec <= 0)
        return
    delta := A_TickCount - gLastRefresh
    if (delta < 0) {                       ; A_TickCount wraps ~every 49.7 days
        gLastRefresh := A_TickCount
        return
    }
    if (delta >= gRefreshSec * 1000) {
        RefreshKiosk()
        gLastRefresh := A_TickCount
    }
}

RefreshKiosk() {
    global gWin, gRefreshHard
    if (!gWin || !WinExist("ahk_id " . gWin))
        return
    WinActivate, % "ahk_id " . gWin        ; sending keys needs focus; kiosk is the only window
    WinWaitActive, % "ahk_id " . gWin, , 2
    if (gRefreshHard)
        Send, ^{F5}                        ; Ctrl+F5 = hard reload, ignore cache
    else
        Send, {F5}
}

LaunchChrome() {
    global gChromePath, gUrl, gUserDataDir
    q := Chr(34)   ; double-quote
    ; NOTE: no --new-window; a fresh isolated profile opens one window on its
    ; own, and omitting it means an accidental double-launch can't spawn a
    ; second kiosk window.
    flags := "--kiosk --no-first-run --no-default-browser-check "
           . "--disable-session-crashed-bubble --disable-infobars "
           . "--disable-features=TranslateUI --overscroll-history-navigation=0"
    cmd := q gChromePath q " " flags " --user-data-dir=" q gUserDataDir q " " q gUrl q
    Run, %cmd%,,, pid
}

; Snapshot HWNDs of currently-visible Chrome windows, so the freshly-opened one
; can be told apart and the user's own Chrome is never touched.
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

; Find a real visible Chrome window owned by process `pid`.
FindWindowByPid(pid) {
    if (!pid)
        return 0
    WinGet, list, List, ahk_class Chrome_WidgetWin_1
    Loop, %list% {
        h := list%A_Index%
        WinGet, wpid, PID, ahk_id %h%
        if (wpid = pid) {
            WinGetPos,,, w, ht, ahk_id %h%
            if (w > 100 && ht > 100)
                return h
        }
    }
    return 0
}

ProcAlive(pid) {
    if (!pid)
        return false
    Process, Exist, %pid%
    return (ErrorLevel != 0)
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

; --------------------- cursor hide/restore ---------------------

; Restore the real system cursor on any exit so we never leave the machine
; cursorless (hidden hotkey, update-restart, or normal close all pass here).
OnExitHandler(ExitReason, ExitCode) {
    global gHideCursor
    if (gHideCursor)
        SystemCursor(true)
}

; Hide (show=false) or restore (show=true) the entire system cursor.
; Hiding swaps every system cursor for a fully-transparent one; restoring
; reloads the OS defaults. Works on Windows 7+.
SystemCursor(show) {
    static ids := "32512,32513,32514,32515,32516,32631,32642,32643,32644,32645,32646,32648,32649,32650,32651"
    if (show) {
        DllCall("SystemParametersInfo", "uint", 0x57, "uint", 0, "ptr", 0, "uint", 0)  ; SPI_SETCURSORS
        return
    }
    VarSetCapacity(andMask, 32*4, 0xFF)   ; all 1s
    VarSetCapacity(xorMask, 32*4, 0x00)   ; all 0s  -> fully transparent 32x32 cursor
    blank := DllCall("CreateCursor", "ptr", 0, "int", 0, "int", 0, "int", 32, "int", 32
                   , "ptr", &andMask, "ptr", &xorMask, "ptr")
    for i, id in StrSplit(ids, ",") {
        h := DllCall("CopyImage", "ptr", blank, "uint", 2, "int", 0, "int", 0, "uint", 0, "ptr")
        DllCall("SetSystemCursor", "ptr", h, "uint", id)   ; consumes h
    }
    DllCall("DestroyCursor", "ptr", blank)
}

; --------------------- self-update ---------------------

MaybeUpdate() {
    global gAutoUpdate, gUpdateSec, gLastUpdate
    if (!gAutoUpdate || gUpdateSec <= 0)
        return
    delta := A_TickCount - gLastUpdate
    if (delta < 0) {                       ; A_TickCount wraps ~every 49.7 days
        gLastUpdate := A_TickCount
        return
    }
    if (delta >= gUpdateSec * 1000) {
        gLastUpdate := A_TickCount
        CheckUpdate()
    }
}

; Download the latest exe, compare with the running one, and upgrade if different.
CheckUpdate() {
    global gAutoUpdate, gUpdateUrl
    if (!gAutoUpdate)
        return
    newExe := A_ScriptDir . "\WebKioskGuardAHK.new.exe"
    if FileExist(newExe)
        FileDelete, %newExe%

    dq := Chr(34)
    ps := "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; "
        . "Invoke-WebRequest -UseBasicParsing '" . gUpdateUrl . "' -OutFile '" . newExe . "'"
    cmd := "powershell -NoProfile -ExecutionPolicy Bypass -Command " . dq . ps . dq
    RunWait, %cmd%,, Hide

    if (!IsValidExe(newExe)) {          ; download failed / incomplete -> leave kiosk alone
        if FileExist(newExe)
            FileDelete, %newExe%
        return
    }

    ; Binary-compare with the currently running exe (fc /b is built into Windows).
    RunWait, %ComSpec% /c fc /b "%A_ScriptFullPath%" "%newExe%" >nul 2>&1,, Hide
    if (ErrorLevel = 0) {               ; identical -> already up to date
        FileDelete, %newExe%
        return
    }
    DoUpdate(newExe)
}

IsValidExe(path) {
    if (!FileExist(path))
        return false
    FileGetSize, sz, %path%
    if (sz < 200000)                    ; our exe is ~0.9 MB; guard against error pages
        return false
    magic := ""
    f := FileOpen(path, "r")
    if (!f)
        return false
    magic := Chr(f.ReadUChar()) . Chr(f.ReadUChar())
    f.Close()
    return (magic = "MZ")
}

; Hand the swap off to a batch file: a running exe can't overwrite itself.
DoUpdate(newExe) {
    global gRunning
    pid := DllCall("GetCurrentProcessId")
    bat := A_ScriptDir . "\wkg-update.bat"
    exe := A_ScriptFullPath
    dir := A_ScriptDir
    if FileExist(bat)
        FileDelete, %bat%
    txt := "@echo off`r`n"
         . ":wait`r`n"
         . "tasklist /fi ""PID eq " . pid . """ | find """ . pid . """ >nul && ( ping -n 2 127.0.0.1 >nul & goto wait )`r`n"
         . "move /y """ . newExe . """ """ . exe . """ >nul`r`n"
         . "echo %DATE% %TIME% updated> """ . dir . "\last-update.txt""`r`n"
         . "start """" """ . exe . """`r`n"
         . "del ""%~f0""`r`n"
    FileAppend, %txt%, %bat%
    Run, % Chr(34) . bat . Chr(34),, Hide
    gRunning := false
    ExitApp                             ; OnExit restores the cursor before we go
}
