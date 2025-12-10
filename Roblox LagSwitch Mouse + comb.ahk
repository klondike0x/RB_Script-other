#NoEnv
#SingleInstance Force
#Persistent
#InstallMouseHook
#KeyHistory 0

SetBatchLines, -1
ListLines, Off
Process, Priority,, Realtime

; === CONFIGURACIÓN ===
TargetProcess := "RobloxPlayerBeta.exe"
DefaultFreezeDuration := 1
FreezeDuration := DefaultFreezeDuration
SelectedMouseButton := "LButton"
; =======================

; === GUI ===
Gui, Font, s10, Segoe UI
Gui, Add, Text, x20 y20, Freeze Duration (ms 1-1000):
Gui, Add, Edit, x20 y40 w100 vFreezeDuration, %FreezeDuration%
Gui, Add, Button, x20 y70 w100 gApplySettings, Apply Settings
Gui, Add, Button, x130 y70 w100 gTestFreeze, Test Freeze
Gui, Add, DropDownList, x20 y110 w100 vMouseButton Choose1, LButton|RButton|MButton|XButton1|XButton2
Gui, Add, Text, x20 y140 w270 vStatus, Status: Ready
Gui, Show, w320 h180, Roblox Mouse Freezer

Menu, Tray, NoStandard
Menu, Tray, Add, Open GUI, ShowGUI
Menu, Tray, Add, Exit, ExitScript

return

ApplySettings:
    Gui, Submit, NoHide
    if (FreezeDuration < 1 or FreezeDuration > 1000)
    {
        MsgBox, Please enter a value between 1-1000 ms
        FreezeDuration := DefaultFreezeDuration
        GuiControl,, FreezeDuration, %FreezeDuration%
    }
    GuiControlGet, SelectedMouseButton,, MouseButton
    GuiControl,, Status, Settings Applied (%FreezeDuration%ms)
return

TestFreeze:
    Gui, Submit, NoHide
    GuiControl,, Status, Testing Freeze...
    FreezeRoblox()
    GuiControl,, Status, Test Complete
return

ShowGUI:
    Gui, Show
return

GuiClose:
    Gui, Hide
return

ExitScript:
    ExitApp
return

; === HOTKEYS dentro de Roblox con modificadores incluidos ===
#IfWinActive ahk_exe RobloxPlayerBeta.exe

~LButton::
~^LButton::
~+LButton::
~!LButton::
~^+LButton::
~^!LButton::
~+!LButton::
~^+!LButton::
    CheckTrigger("LButton")
return

~RButton::
~^RButton::
~+RButton::
~!RButton::
~^+RButton::
~^!RButton::
~+!RButton::
~^+!RButton::
    CheckTrigger("RButton")
return

~MButton::
~^MButton::
~+MButton::
~!MButton::
~^+MButton::
~^!MButton::
~+!MButton::
~^+!MButton::
    CheckTrigger("MButton")
return

~XButton1::
~^XButton1::
~+XButton1::
~!XButton1::
~^+XButton1::
~^!XButton1::
~+!XButton1::
~^+!XButton1::
    CheckTrigger("XButton1")
return

~XButton2::
~^XButton2::
~+XButton2::
~!XButton2::
~^+XButton2::
~^!XButton2::
~+!XButton2::
~^+!XButton2::
    CheckTrigger("XButton2")
return

#IfWinActive

; === VERIFICAR SI BOTÓN SELECCIONADO COINCIDE ===
CheckTrigger(button) {
    global SelectedMouseButton
    if (SelectedMouseButton = button)
        FreezeRoblox()
}

; === FREEZE ===
FreezeRoblox() {
    global FreezeDuration, TargetProcess

    Process, Exist, %TargetProcess%
    RobloxPID := ErrorLevel

    if (!RobloxPID) {
        GuiControl,, Status, Roblox not found!
        return
    }

    GuiControl,, Status, Freezing...
    hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "UInt", RobloxPID)
    if (hProcess) {
        DllCall("ntdll\NtSuspendProcess", "Ptr", hProcess)
        Sleep, %FreezeDuration%
        DllCall("ntdll\NtResumeProcess", "Ptr", hProcess)
        DllCall("CloseHandle", "Ptr", hProcess)
        GuiControl,, Status, Frozen for %FreezeDuration%ms
    } else {
        GuiControl,, Status, Failed to open process
    }
}
