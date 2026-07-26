using System.Linq;
using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;

namespace Devbox.Ui;

public partial class App : Application
{
    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            // `devbox ui [dir]` passes the folder you were standing in.
            var folder = desktop.Args?.FirstOrDefault(a => !a.StartsWith('-'));
            desktop.MainWindow = new MainWindow(folder);
        }

        base.OnFrameworkInitializationCompleted();
    }
}
