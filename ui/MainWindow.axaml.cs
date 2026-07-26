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

    private async Task<string?> PickFolderAsync()
    {
        var top = GetTopLevel(this);
        if (top is null) return null;

        IStorageFolder? start = null;
        if (_vm.HasFolder)
            start = await top.StorageProvider.TryGetFolderFromPathAsync(_vm.Folder);

        var picked = await top.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            Title = "Choose a project folder",
            AllowMultiple = false,
            SuggestedStartLocation = start,
        });

        return picked.Count > 0 ? picked[0].Path.LocalPath : null;
    }
}
