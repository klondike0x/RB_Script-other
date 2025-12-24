using System;
using System.Windows;
using Hardcodet.Wpf.TaskbarNotification;

namespace BhopScriptWPF
{
    public partial class App : Application
    {
        private TaskbarIcon _trayIcon;

        private void Application_Startup(object sender, StartupEventArgs e)
        {
            // Создаем главное окно
            MainWindow mainWindow = new MainWindow();

            // Показываем окно или сразу скрываем в трей
            if (!HasArgument("--hidden"))
            {
                mainWindow.Show();
            }
            else
            {
                mainWindow.Hide();
            }
        }

        private bool HasArgument(string arg)
        {
            foreach (string a in Environment.GetCommandLineArgs())
            {
                if (a.Equals(arg, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }

        protected override void OnExit(ExitEventArgs e)
        {
            _trayIcon?.Dispose();
            base.OnExit(e);
        }
    }
}