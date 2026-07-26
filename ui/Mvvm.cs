using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using System.Windows.Input;

namespace Devbox.Ui;

/// <summary>Just enough MVVM. A whole toolkit for one window would be a package to
/// restore on every machine, for two classes we can read in a minute.</summary>
public abstract class ObservableObject : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected void Raise([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (Equals(field, value)) return false;
        field = value;
        Raise(name);
        return true;
    }
}

/// <summary>An async command that cannot be fired twice at once - which is exactly
/// what you want when the click starts a process that writes to your project.</summary>
public sealed class AsyncCommand : ICommand
{
    private readonly Func<Task> _run;
    private readonly Func<bool>? _can;
    private bool _running;

    public AsyncCommand(Func<Task> run, Func<bool>? can = null)
    {
        _run = run;
        _can = can;
    }

    public event EventHandler? CanExecuteChanged;

    public void RaiseCanExecuteChanged() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);

    public bool CanExecute(object? parameter) => !_running && (_can?.Invoke() ?? true);

    public async void Execute(object? parameter)
    {
        if (!CanExecute(parameter)) return;
        _running = true;
        RaiseCanExecuteChanged();
        try
        {
            await _run().ConfigureAwait(true);
        }
        finally
        {
            _running = false;
            RaiseCanExecuteChanged();
        }
    }
}
