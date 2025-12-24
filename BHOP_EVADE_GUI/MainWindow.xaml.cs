using Hardcodet.Wpf.TaskbarNotification;
using Newtonsoft.Json;
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;

namespace BhopScriptWPF
{
    public partial class MainWindow : Window
    {
        #region Windows API

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

        [DllImport("user32.dll")]
        private static extern uint MapVirtualKey(uint uCode, uint uMapType);

        [DllImport("user32.dll")]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        // Low-level keyboard hook
        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll")]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetModuleHandle(string? lpModuleName);

        private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        private const int WH_KEYBOARD_LL = 13;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_KEYUP = 0x0101;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int WM_SYSKEYUP = 0x0105;

        private const int INPUT_KEYBOARD = 1;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const uint KEYEVENTF_SCANCODE = 0x0008;
        private const int WM_HOTKEY = 0x0312;
        private const uint MAPVK_VK_TO_VSC = 0;

        // Флаг LLKHF_INJECTED - для определения что нажатие симулировано
        private const uint LLKHF_INJECTED = 0x00000010;

        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT
        {
            public int type;
            public KEYBDINPUT ki;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
            private ulong padding; // Padding для 64-bit
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct KBDLLHOOKSTRUCT
        {
            public uint vkCode;
            public uint scanCode;
            public uint flags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        #endregion

        // Hook
        private LowLevelKeyboardProc? _keyboardProc;
        private IntPtr _hookId = IntPtr.Zero;

        // Состояние клавиши прыжка
        private volatile bool _spaceHeld = false;

        // Настройки
        private Key _toggleKey = Key.F1;
        private Key _jumpKey = Key.Space;
        private int _minDelay = 30;
        private int _maxDelay = 50;
        private volatile bool _autoJumpEnabled = false;

        // Статистика
        private int _totalJumps = 0;
        private TimeSpan _activeTime = TimeSpan.Zero;

        // Потоки и таймеры
        private Thread? _bhopThread;
        private CancellationTokenSource? _cts;
        private DispatcherTimer? _uiTimer;

        // Трей иконка
        private TaskbarIcon? _trayIcon;

        // Конфигурация
        private Config? _config;
        private const string CONFIG_FILE = "config.json";

        // Кэш
        private int _jumpKeyVk;
        private ushort _jumpKeyScan;

        public MainWindow()
        {
            InitializeComponent();
            LoadConfig();
            UpdateJumpKeyCache();
            InitializeTrayIcon();
            SetupHotkeys();
            StartUIUpdates();
            InstallKeyboardHook();
            UpdateUI();

            this.SourceInitialized += MainWindow_SourceInitialized;
        }

        private void UpdateJumpKeyCache()
        {
            _jumpKeyVk = KeyInterop.VirtualKeyFromKey(_jumpKey);
            _jumpKeyScan = (ushort)MapVirtualKey((uint)_jumpKeyVk, MAPVK_VK_TO_VSC);
        }

        #region Keyboard Hook

        private void InstallKeyboardHook()
        {
            _keyboardProc = HookCallback;
            using var curProcess = Process.GetCurrentProcess();
            using var curModule = curProcess.MainModule!;
            _hookId = SetWindowsHookEx(WH_KEYBOARD_LL, _keyboardProc, GetModuleHandle(curModule.ModuleName), 0);
        }

        private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0)
            {
                var hookStruct = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);

                // Игнорируем симулированные нажатия (INJECTED)
                // Это важно! Иначе наши собственные нажатия будут менять _spaceHeld
                bool isInjected = (hookStruct.flags & LLKHF_INJECTED) != 0;

                if (!isInjected && hookStruct.vkCode == (uint)_jumpKeyVk)
                {
                    int msg = wParam.ToInt32();
                    if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
                    {
                        _spaceHeld = true;
                    }
                    else if (msg == WM_KEYUP || msg == WM_SYSKEYUP)
                    {
                        _spaceHeld = false;
                    }
                }
            }

            return CallNextHookEx(_hookId, nCode, wParam, lParam);
        }

        #endregion

        private void MainWindow_SourceInitialized(object? sender, EventArgs e)
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            HwndSource.FromHwnd(hwnd)?.AddHook(HwndHook);
            RegisterHotKey(hwnd, 1, 0, (uint)KeyInterop.VirtualKeyFromKey(Key.F1));
            RegisterHotKey(hwnd, 2, 0, (uint)KeyInterop.VirtualKeyFromKey(Key.F2));
        }

        private IntPtr HwndHook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_HOTKEY)
            {
                switch (wParam.ToInt32())
                {
                    case 1: ToggleAutoJump(); handled = true; break;
                    case 2: ShowWindow(); handled = true; break;
                }
            }
            return IntPtr.Zero;
        }

        private void LoadConfig()
        {
            try
            {
                if (File.Exists(CONFIG_FILE))
                {
                    string json = File.ReadAllText(CONFIG_FILE);
                    _config = JsonConvert.DeserializeObject<Config>(json);
                    if (_config != null)
                    {
                        _toggleKey = (Key)Enum.Parse(typeof(Key), _config.ToggleKey);
                        _jumpKey = (Key)Enum.Parse(typeof(Key), _config.JumpKey);
                        _minDelay = _config.MinDelay;
                        _maxDelay = _config.MaxDelay;
                        _totalJumps = _config.TotalJumps;
                        _activeTime = TimeSpan.FromSeconds(_config.ActiveTimeSeconds);
                    }
                    else _config = new Config();
                }
                else _config = new Config();
            }
            catch { _config = new Config(); }
        }

        private void SaveConfig()
        {
            try
            {
                _config ??= new Config();
                _config.ToggleKey = _toggleKey.ToString();
                _config.JumpKey = _jumpKey.ToString();
                _config.MinDelay = _minDelay;
                _config.MaxDelay = _maxDelay;
                _config.TotalJumps = _totalJumps;
                _config.ActiveTimeSeconds = (int)_activeTime.TotalSeconds;
                File.WriteAllText(CONFIG_FILE, JsonConvert.SerializeObject(_config, Newtonsoft.Json.Formatting.Indented));
            }
            catch { }
        }

        private void InitializeTrayIcon()
        {
            _trayIcon = new TaskbarIcon
            {
                ToolTipText = "AutoBhop Pro\nF1 - Вкл/Выкл\nF2 - Показать",
                Visibility = Visibility.Visible
            };

            var menu = new ContextMenu();
            var showItem = new MenuItem { Header = "Показать" };
            showItem.Click += (s, e) => ShowWindow();
            var toggleItem = new MenuItem { Header = "Вкл/Выкл (F1)" };
            toggleItem.Click += (s, e) => ToggleAutoJump();
            var exitItem = new MenuItem { Header = "Выход" };
            exitItem.Click += (s, e) => ExitApplication();

            menu.Items.Add(showItem);
            menu.Items.Add(new Separator());
            menu.Items.Add(toggleItem);
            menu.Items.Add(new Separator());
            menu.Items.Add(exitItem);

            _trayIcon.ContextMenu = menu;
            _trayIcon.TrayMouseDoubleClick += (s, e) => ShowWindow();
        }

        private void SetupHotkeys()
        {
            tbToggleKey.Text = _toggleKey.ToString();
            tbJumpKey.Text = _jumpKey.ToString();
            sliderMinDelay.Value = _minDelay;
            sliderMaxDelay.Value = _maxDelay;
        }

        private void StartUIUpdates()
        {
            _uiTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
            _uiTimer.Tick += (s, e) => UpdateStats();
            _uiTimer.Start();
        }

        private void UpdateUI()
        {
            if (_autoJumpEnabled)
            {
                borderStatus.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(166, 227, 161));
                tbStatusIcon.Text = "✅";
                tbStatusText.Text = "Распрыжка АКТИВНА";
                btnToggle.Content = "🟢 Включено";
                btnToggle.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(166, 227, 161));
                btnToggle.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(30, 30, 46)); // #1E1E2E
                progressBar.Visibility = Visibility.Visible;
            }
            else
            {
                borderStatus.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(243, 139, 168));
                tbStatusIcon.Text = "⛔";
                tbStatusText.Text = "Распрыжка ВЫКЛЮЧЕНА";
                btnToggle.Content = "🔴 Выключено";
                btnToggle.Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(243, 139, 168));
                btnToggle.Foreground = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(30, 30, 46)); // #1E1E2E
                progressBar.Visibility = Visibility.Collapsed;
            }
        }

        private void UpdateStats()
        {
            tbTotalJumps.Text = _totalJumps.ToString();
            tbActiveTime.Text = _activeTime.ToString(@"hh\:mm\:ss");
            if (_autoJumpEnabled)
            {
                _activeTime = _activeTime.Add(TimeSpan.FromMilliseconds(100));
                progressBar.Value = (progressBar.Value + 5) % 100;
            }
        }

        private void ToggleAutoJump()
        {
            _autoJumpEnabled = !_autoJumpEnabled;

            if (_autoJumpEnabled)
            {
                _cts = new CancellationTokenSource();
                _bhopThread = new Thread(() => CheckJumpLoop(_cts.Token))
                {
                    IsBackground = true,
                    Priority = ThreadPriority.AboveNormal
                };
                _bhopThread.Start();
                ShowTrayNotification("✅ Распрыжка АКТИВНА", $"Удерживайте {_jumpKey} для прыжков");
            }
            else
            {
                _cts?.Cancel();
                _bhopThread?.Join(500);
                ShowTrayNotification("⛔ Распрыжка ВЫКЛЮЧЕНА", "");
            }

            UpdateUI();
            SaveConfig();
        }

        private void CheckJumpLoop(CancellationToken token)
        {
            var random = new Random();
            long lastJumpTime = 0;

            while (!token.IsCancellationRequested)
            {
                if (!_autoJumpEnabled || !_spaceHeld)
                {
                    Thread.Sleep(10);
                    continue;
                }

                long currentTime = Environment.TickCount64;
                if (currentTime - lastJumpTime < _minDelay)
                {
                    Thread.Sleep(1);
                    continue;
                }

                // Симулируем нажатие через SendInput со scan code
                SendKeyDown();
                Thread.Sleep(15);
                SendKeyUp();

                lastJumpTime = currentTime;
                Interlocked.Increment(ref _totalJumps);

                int randDelay = random.Next(_minDelay, _maxDelay + 1);
                Thread.Sleep(randDelay);
            }
        }

        private void SendKeyDown()
        {
            var input = new INPUT
            {
                type = INPUT_KEYBOARD,
                ki = new KEYBDINPUT
                {
                    wVk = 0,  // Не используем VK при SCANCODE
                    wScan = _jumpKeyScan,
                    dwFlags = KEYEVENTF_SCANCODE,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero
                }
            };
            SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
        }

        private void SendKeyUp()
        {
            var input = new INPUT
            {
                type = INPUT_KEYBOARD,
                ki = new KEYBDINPUT
                {
                    wVk = 0,
                    wScan = _jumpKeyScan,
                    dwFlags = KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP,
                    time = 0,
                    dwExtraInfo = IntPtr.Zero
                }
            };
            SendInput(1, new[] { input }, Marshal.SizeOf<INPUT>());
        }

        #region UI Event Handlers

        private void Border_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ChangedButton == MouseButton.Left) DragMove();
        }

        private void btnClose_Click(object sender, RoutedEventArgs e) => Hide();

        private void btnChangeToggleKey_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new KeyDialog("Выберите клавишу для вкл/выкл:", _toggleKey);
            if (dialog.ShowDialog() == true)
            {
                _toggleKey = dialog.SelectedKey;
                tbToggleKey.Text = _toggleKey.ToString();
            }
        }

        private void btnChangeJumpKey_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new KeyDialog("Выберите клавишу прыжка:", _jumpKey);
            if (dialog.ShowDialog() == true)
            {
                _jumpKey = dialog.SelectedKey;
                tbJumpKey.Text = _jumpKey.ToString();
                UpdateJumpKeyCache();
            }
        }

        private void SliderMinDelay_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            _minDelay = (int)e.NewValue;
            if (tbMinDelay != null) tbMinDelay.Text = _minDelay.ToString();
        }

        private void SliderMaxDelay_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            _maxDelay = (int)e.NewValue;
            if (tbMaxDelay != null) tbMaxDelay.Text = _maxDelay.ToString();
        }

        private void btnSave_Click(object sender, RoutedEventArgs e)
        {
            SaveConfig();
            ShowTrayNotification("✅ Настройки сохранены", "");
        }

        private void btnToggle_Click(object sender, RoutedEventArgs e) => ToggleAutoJump();
        private void btnHide_Click(object sender, RoutedEventArgs e) => Hide();

        private void btnResetStats_Click(object sender, RoutedEventArgs e)
        {
            _totalJumps = 0;
            _activeTime = TimeSpan.Zero;
            SaveConfig();
        }

        #endregion

        private void ShowWindow()
        {
            Show();
            WindowState = WindowState.Normal;
            Activate();
        }

        private void ShowTrayNotification(string title, string message)
        {
            _trayIcon?.ShowBalloonTip(title, message, BalloonIcon.Info);
        }

        private void ExitApplication()
        {
            _cts?.Cancel();
            _uiTimer?.Stop();
            if (_hookId != IntPtr.Zero) UnhookWindowsHookEx(_hookId);
            SaveConfig();
            _trayIcon?.Dispose();
            Application.Current.Shutdown();
        }

        protected override void OnClosed(EventArgs e)
        {
            _cts?.Cancel();
            if (_hookId != IntPtr.Zero) UnhookWindowsHookEx(_hookId);
            SaveConfig();
            base.OnClosed(e);
        }
    }

    public class Config
    {
        public string ToggleKey { get; set; } = "F1";
        public string JumpKey { get; set; } = "Space";
        public int MinDelay { get; set; } = 30;
        public int MaxDelay { get; set; } = 50;
        public int TotalJumps { get; set; } = 0;
        public int ActiveTimeSeconds { get; set; } = 0;
    }

    public partial class KeyDialog : Window
    {
        public Key SelectedKey { get; private set; }

        public KeyDialog(string message, Key currentKey)
        {
            SelectedKey = currentKey;
            Title = "Выбор клавиши";
            Width = 300; Height = 150;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
            WindowStyle = WindowStyle.ToolWindow;

            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition());

            var textBlock = new TextBlock { Text = message, Margin = new Thickness(10), TextWrapping = TextWrapping.Wrap };
            Grid.SetRow(textBlock, 0);

            var border = new Border
            {
                Background = System.Windows.Media.Brushes.LightGray,
                CornerRadius = new CornerRadius(5),
                Margin = new Thickness(10),
                Height = 40
            };
            Grid.SetRow(border, 1);

            var keyText = new TextBlock
            {
                Text = currentKey.ToString(),
                FontSize = 18,
                FontWeight = FontWeights.Bold,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };
            border.Child = keyText;

            KeyDown += (s, e) => { SelectedKey = e.Key; keyText.Text = SelectedKey.ToString(); };

            var button = new Button { Content = "OK", Width = 80, Margin = new Thickness(10), HorizontalAlignment = HorizontalAlignment.Right };
            button.Click += (s, e) => DialogResult = true;
            Grid.SetRow(button, 2);

            grid.Children.Add(textBlock);
            grid.Children.Add(border);
            grid.Children.Add(button);
            Content = grid;
        }
    }
}