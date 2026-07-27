using System.ComponentModel;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Markup.Xaml;
using Avalonia.Platform.Storage;
using Avalonia.Threading;

namespace Devbox.Ui;

public partial class MainWindow : Window
{
    private readonly MainViewModel _vm;

    public MainWindow() : this(null) { }

    public MainWindow(string? initialFolder)
    {
        InitializeComponent();

        _vm = new MainViewModel(PickFolderAsync, initialFolder);
        _vm.PropertyChanged += OnViewModelChanged;
        DataContext = _vm;

        Opened += async (_, _) => await _vm.LoadAsync();
    }

    private void InitializeComponent() => AvaloniaXamlLoader.Load(this);

    /// <summary>A console you have to scroll yourself is a console you stop reading.</summary>
    private void OnViewModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(MainViewModel.Output)) return;
        Dispatcher.UIThread.Post(() => this.FindControl<ScrollViewer>("ConsoleScroll")?.ScrollToEnd(),
            DispatcherPriority.Background);
    }

    /// <summary>
    /// One dialog, two jobs: picking a project, and picking the disk the store
    /// goes on. They differ only in the title and where the dialog opens, and an
    /// external drive is worth opening at - /media/$USER and /mnt are where a
    /// desktop Linux mounts one, and hunting for it from $HOME is three clicks
    /// of nothing.
    /// </summary>
    private async Task<string?> PickFolderAsync(string title, string? startAt)
    {
        var top = GetTopLevel(this);
        if (top is null) return null;

        IStorageFolder? start = null;
        foreach (var candidate in Candidates(startAt))
        {
            start = await top.StorageProvider.TryGetFolderFromPathAsync(candidate);
            if (start is not null) break;
        }

        var picked = await top.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            Title = title,
            AllowMultiple = false,
            SuggestedStartLocation = start,
        });

        return picked.Count > 0 ? picked[0].Path.LocalPath : null;
    }

    private static System.Collections.Generic.IEnumerable<string> Candidates(string? startAt)
    {
        if (startAt is { Length: > 0 }) yield return startAt;
    }
}
