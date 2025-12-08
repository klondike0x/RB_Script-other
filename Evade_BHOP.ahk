#NoEnv
#Warn
SendMode Input
SetWorkingDir %A_ScriptDir%

; === Настройки ===
ToggleKey   := "F1"      ; Клавиша включения/выключения
JumpKey     := "Space"   ; Клавиша прыжка
MinDelay    := 30        ; Минимальная задержка между прыжками (мс)
MaxDelay    := 50        ; Максимальная задержка между прыжками (мс)

; === Переменные ===
autoJumpEnabled := false
spaceHeld := false
lastJumpTime := 0

; === Горячие клавиши ===
Hotkey, % "*" . ToggleKey, ToggleAutoJump

ToggleAutoJump:
    autoJumpEnabled := !autoJumpEnabled
    if (autoJumpEnabled) {
        ToolTip, ✅ Распрыжка АКТИВНА`n(Удерживайте %JumpKey%)
        SetTimer, CheckJump, 10
    } else {
        ToolTip, ⛔ Распрыжка ВЫКЛ
        SetTimer, CheckJump, Off
        
        ; Отпускаем прыжок при выключении
        if (spaceHeld) {
            SendInput, {Blind}{%JumpKey% up}
            spaceHeld := false
        }
    }
    
    ; Убираем подсказку через 2 секунды
    SetTimer, RemoveToolTip, -2000
return

; === Проверяем состояние Space ===
~*Space::
    spaceHeld := true
return

~*Space up::
    spaceHeld := false
return

; === Улучшенная логика распрыжки ===
CheckJump:
    if (!autoJumpEnabled || !spaceHeld)
        return
    
    ; Проверяем, прошло ли достаточно времени с последнего прыжка
    currentTime := A_TickCount
    if (currentTime - lastJumpTime < MinDelay)
        return
    
    ; Отправляем ОДИН прыжок
    SendInput, {Blind}{%JumpKey% down}
    Sleep, 15
    SendInput, {Blind}{%JumpKey% up}
    
    ; Запоминаем время последнего прыжка
    lastJumpTime := currentTime
    
    ; Добавляем случайную задержку для естественности
    Random, randDelay, %MinDelay%, %MaxDelay%
    Sleep, %randDelay%
return

; === Убираем подсказку ===
RemoveToolTip:
    ToolTip
return

; === Очистка при выходе ===
OnExit:
    if (spaceHeld)
        SendInput, {Blind}{%JumpKey% up}
    ToolTip
ExitApp
return