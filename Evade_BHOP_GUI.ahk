#NoEnv
#Warn
#SingleInstance Force
SendMode Input
SetWorkingDir %A_ScriptDir%

; === Настройки по умолчанию ===
ToggleKey   := "F1"
JumpKey     := "Space"
MinDelay    := 30
MaxDelay    := 50

; === Чтение сохраненных настроек ===
ReadSettings()

; === Переменные ===
autoJumpEnabled := false  ; НАЧАЛЬНОЕ ЗНАЧЕНИЕ: ВЫКЛЮЧЕНО
spaceHeld := false
lastJumpTime := 0

; === Создание GUI ===
CreateGUI()

; === Инициализация горячих клавиш ===
InitHotkeys()

; === Трей-меню ===
Menu, Tray, NoStandard
Menu, Tray, Add, Открыть настройки, ShowGUI
Menu, Tray, Add
Menu, Tray, Add, Включить/Выключить (F1), ToggleAutoJump
Menu, Tray, Add, Перезагрузить скрипт, ReloadScript
Menu, Tray, Add, Выход, ExitScript
Menu, Tray, Default, Открыть настройки
Menu, Tray, Tip, AutoBhop Script`nF1 - Вкл/Выкл`nF2 - Настройки

return ; Конец автозапуска

; === Функция создания GUI ===
CreateGUI() {
    global ToggleKey, JumpKey, MinDelay, MaxDelay
    global StatusTextActive, StatusTextInactive, ToggleKeyGUI, JumpKeyGUI, MinDelayGUI, MaxDelayGUI
    
    ; Основное окно
    Gui, Main:New, +AlwaysOnTop +ToolWindow +Caption, AutoBhop Settings
    Gui, Main:Color, F0F0F0
    Gui, Main:Font, s10, Segoe UI
    
    ; Секция горячих клавиш
    Gui, Main:Font, s10 Bold
    Gui, Main:Add, GroupBox, x10 y10 w280 h110 c333333, Горячие клавиши
    Gui, Main:Font, s10 Norm
    
    Gui, Main:Add, Text, x20 y40 w100 c333333, Вкл/Выкл (F1):
    Gui, Main:Add, Edit, x130 y37 w150 h25 vToggleKeyGUI c333333, %ToggleKey%
    
    Gui, Main:Add, Text, x20 y75 w100 c333333, Клавиша прыжка:
    Gui, Main:Add, Edit, x130 y72 w150 h25 vJumpKeyGUI c333333, %JumpKey%
    
    ; Секция задержек
    Gui, Main:Font, s10 Bold
    Gui, Main:Add, GroupBox, x10 y130 w280 h110 c333333, Задержки прыжков (мс)
    Gui, Main:Font, s10 Norm
    
    Gui, Main:Add, Text, x20 y160 w100 c333333, Мин. задержка:
    Gui, Main:Add, Edit, x130 y157 w150 h25 vMinDelayGUI c333333, %MinDelay%
    
    Gui, Main:Add, Text, x20 y195 w100 c333333, Макс. задержка:
    Gui, Main:Add, Edit, x130 y192 w150 h25 vMaxDelayGUI c333333, %MaxDelay%
    
    ; Статус
    Gui, Main:Font, s10 Bold
    Gui, Main:Add, GroupBox, x10 y250 w280 h60 c333333, Статус
    Gui, Main:Font, s10 Norm
    
    ; Два текстовых элемента для статуса
    ; Когда автопрыжок ВЫКЛЮЧЕН - показываем красный текст
    Gui, Main:Add, Text, x20 y275 w260 h20 vStatusTextInactive cRed, ⛔ Распрыжка ВЫКЛЮЧЕНА
    
    ; Когда автопрыжок ВКЛЮЧЕН - показываем зеленый текст (скрыт по умолчанию)
    Gui, Main:Add, Text, x20 y275 w260 h20 vStatusTextActive cGreen Hidden, ✅ Распрыжка АКТИВНА
    
    ; Кнопки
    Gui, Main:Add, Button, x10 y320 w135 h40 gSaveSettingsLabel, 💾 Сохранить
    Gui, Main:Add, Button, x155 y320 w135 h40 gToggleFromGUILabel, 🔄 Вкл/Выкл (F1)
    
    ; Кнопка скрытия
    Gui, Main:Add, Button, x10 y370 w280 h30 gHideGUILabel, Скрыть окно
    
    ; Устанавливаем цвет для кнопок
    GuiControl, Main:+BackgroundD0D0D0, Button1
    GuiControl, Main:+BackgroundD0D0D0, Button2
    GuiControl, Main:+BackgroundD0D0D0, Button3
}

; === Показать GUI ===
ShowGUI:
    ; Обновляем статус перед показом
    UpdateStatus()
    Gui, Main:Show, xCenter yCenter, AutoBhop Settings
return

; === Скрыть GUI ===
HideGUILabel:
    Gui, Main:Hide
return

; === Сохранить настройки ===
SaveSettingsLabel:
    Gui, Main:Submit, NoHide
    
    ToggleKey := ToggleKeyGUI
    JumpKey := JumpKeyGUI
    MinDelay := MinDelayGUI
    MaxDelay := MaxDelayGUI
    
    if (MinDelay > MaxDelay) {
        MsgBox, 16, Ошибка, Минимальная задержка не может быть больше максимальной!
        return
    }
    
    SaveSettingsToFile()
    UpdateHotkeys()
    
    ToolTip, ✅ Настройки сохранены!
    SetTimer, RemoveToolTip, -1500
return

; === Чтение настроек из файла ===
ReadSettings() {
    global ToggleKey, JumpKey, MinDelay, MaxDelay
    
    if (FileExist("bhop_settings.ini")) {
        IniRead, ToggleKey, bhop_settings.ini, Settings, ToggleKey, F1
        IniRead, JumpKey, bhop_settings.ini, Settings, JumpKey, Space
        IniRead, MinDelay, bhop_settings.ini, Settings, MinDelay, 30
        IniRead, MaxDelay, bhop_settings.ini, Settings, MaxDelay, 50
    }
}

; === Сохранение настроек в файл ===
SaveSettingsToFile() {
    global ToggleKey, JumpKey, MinDelay, MaxDelay
    
    IniWrite, %ToggleKey%, bhop_settings.ini, Settings, ToggleKey
    IniWrite, %JumpKey%, bhop_settings.ini, Settings, JumpKey
    IniWrite, %MinDelay%, bhop_settings.ini, Settings, MinDelay
    IniWrite, %MaxDelay%, bhop_settings.ini, Settings, MaxDelay
}

; === Инициализация горячих клавиш ===
InitHotkeys() {
    global ToggleKey
    
    ; Назначаем хоткеи при запуске
    Hotkey, % "*" . ToggleKey, ToggleAutoJump
    Hotkey, *F2, ShowGUI
    
    Menu, Tray, Tip, AutoBhop Script`n%ToggleKey% - Вкл/Выкл`nF2 - Настройки
}

; === Обновление горячих клавиш ===
UpdateHotkeys() {
    global ToggleKey
    
    ; Сначала отключаем все возможные хоткеи
    try {
        Hotkey, % "*" . ToggleKey, Off
    }
    
    try {
        Hotkey, *F2, Off
    }
    
    ; Устанавливаем новые хоткеи
    Hotkey, % "*" . ToggleKey, ToggleAutoJump, On
    Hotkey, *F2, ShowGUI, On
    
    Menu, Tray, Tip, AutoBhop Script`n%ToggleKey% - Вкл/Выкл`nF2 - Настройки
}

; === Обновление статуса в GUI ===
UpdateStatus() {
    global autoJumpEnabled
    
    ; Показываем/скрываем соответствующий текст в зависимости от состояния
    if (autoJumpEnabled) {
        ; ВКЛЮЧЕНО - показываем зеленый текст, скрываем красный
        GuiControl, Main:Show, StatusTextActive
        GuiControl, Main:Hide, StatusTextInactive
    } else {
        ; ВЫКЛЮЧЕНО - показываем красный текст, скрываем зеленый
        GuiControl, Main:Show, StatusTextInactive
        GuiControl, Main:Hide, StatusTextActive
    }
}

; === Переключение из GUI ===
ToggleFromGUILabel:
    GoSub, ToggleAutoJump
return

; === Основная функция переключения ===
ToggleAutoJump:
    ; Меняем состояние на противоположное
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
    
    ; Обновляем статус в GUI
    UpdateStatus()
    
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

; === Логика распрыжки ===
CheckJump:
    if (!autoJumpEnabled || !spaceHeld)
        return
    
    currentTime := A_TickCount
    if (currentTime - lastJumpTime < MinDelay)
        return
    
    SendInput, {Blind}{%JumpKey% down}
    Sleep, 15
    SendInput, {Blind}{%JumpKey% up}
    
    lastJumpTime := currentTime
    
    Random, randDelay, %MinDelay%, %MaxDelay%
    Sleep, %randDelay%
return

; === Убираем подсказку ===
RemoveToolTip:
    ToolTip
return

; === Перезагрузка скрипта ===
ReloadScript:
    Reload
return

; === Выход из скрипта ===
ExitScript:
    ExitApp
return

; === Очистка при выходе ===
OnExit:
    if (spaceHeld)
        SendInput, {Blind}{%JumpKey% up}
    ToolTip
    SaveSettingsToFile()
    ExitApp
return

; === Горячие клавиши GUI ===
#If WinActive("AutoBhop Settings")
Enter::GoSub, SaveSettingsLabel
Escape::GoSub, HideGUILabel
#If