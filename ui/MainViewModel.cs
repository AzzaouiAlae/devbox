using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Avalonia.Threading;
using Devbox.Ui.Services;

namespace Devbox.Ui;

public sealed class MainViewModel : ObservableObject
{
    private const int OutputLimit = 200_000;      // keep the tail, not the history

    private readonly Func<Task<string?>> _pickFolder;
    private readonly StringBuilder _output = new();
    private readonly List<string> _pending = [];
    private IDisposable? _flush;

    public MainViewModel(Func<Task<string?>> pickFolder, string? initialFolder)
    {
        _pickFolder = pickFolder;

        ChooseFolderCommand = new AsyncCommand(ChooseFolderAsync);
        ApplySetupCommand   = new AsyncCommand(ApplySetupAsync, () => HasFolder && SelectedTemplate is { Length: > 0 });
        SetNetworkCommand   = new AsyncCommand(() => RunAsync(["network", NetworkInput.Trim()], project: true),
                                               () => HasSetup && NetworkInput.Trim().Length > 0);
        ClearNetworkCommand = new AsyncCommand(() => RunAsync(["network", "--none"], project: true),
                                               () => HasSetup && HasNetwork);
        UseComposeNetworkCommand = new AsyncCommand(() =>
        {
            NetworkInput = State.ComposeNetwork ?? "";
            return Task.CompletedTask;
        }, () => State.ComposeNetwork is { Length: > 0 });

        // Launched, not run: both hand over to VSCode, which does not exit.
        OpenCommand      = new AsyncCommand(() => LaunchAsync(["open", Folder], "VSCode"), () => HasFolder);
        ContainerCommand = new AsyncCommand(
            () => LaunchAsync(["container", Folder], "VSCode (it builds the container if needed)"),
            () => HasSetup);
        FixPermsCommand      = new AsyncCommand(() => RunAsync(["fix-perms", Folder]), () => HasFolder);
        CheckVersionsCommand = new AsyncCommand(() => RunAsync(["check-versions", Folder]), () => HasFolder);

        DoctorCommand   = new AsyncCommand(() => RunAsync(["doctor"]));
        WhereCommand    = new AsyncCommand(() => RunAsync(["where"]));
        RepairCommand   = new AsyncCommand(() => RunExeAsync(DevboxCli.DoctorExe, ["fix"]));
        UpdateCommand   = new AsyncCommand(() => RunExeAsync(DevboxCli.DoctorExe, ["update"]));
        ExtSaveCommand  = new AsyncCommand(() => RunAsync(["ext", "save"]));
        ExtExtrasCommand= new AsyncCommand(() => RunAsync(["ext", "extras"]));
        UpCommand       = new AsyncCommand(() => RunAsync(["up"]));
        DownCommand     = new AsyncCommand(() => RunAsync(["down"]));

        // These two need a tty: one IS a shell, the other may ask for a password.
        ShellCommand   = new AsyncCommand(() => TerminalAsync("devbox shell"));
        GoinfreCommand = new AsyncCommand(() => TerminalAsync("devbox goinfre; echo; read -rp 'done - press enter '"));
        LogsCommand    = new AsyncCommand(() => TerminalAsync("setup-doctor logs"));

        RefreshCommand     = new AsyncCommand(RefreshAsync);
        ClearOutputCommand = new AsyncCommand(() => { _output.Clear(); Raise(nameof(Output)); return Task.CompletedTask; });

        Folder = FirstUsable(initialFolder, LoadLastFolder()) ?? "";
    }

    // --- what we are looking at ------------------------------------------------

    private string _folder = "";
    public string Folder
    {
        get => _folder;
        private set
        {
            if (!Set(ref _folder, value)) return;
            Raise(nameof(FolderDisplay));
            Raise(nameof(ProjectName));
            Raise(nameof(HasFolder));
            ReadState();
            SaveLastFolder(value);
        }
    }

    public bool HasFolder => Folder.Length > 0 && Directory.Exists(Folder);
    public string ProjectName => HasFolder ? Path.GetFileName(Folder.TrimEnd('/')) : "no folder chosen";

    /// <summary>Paths are long and the window is narrow: your home is a "~".</summary>
    public string FolderDisplay
    {
        get
        {
            if (!HasFolder) return "pick the project you want to work on";
            var home = DevboxCli.Home;
            return Folder.StartsWith(home, StringComparison.Ordinal) ? "~" + Folder[home.Length..] : Folder;
        }
    }

    private ProjectState _state = ProjectState.None;
    public ProjectState State
    {
        get => _state;
        private set
        {
            if (!Set(ref _state, value)) return;
            foreach (var n in new[]
                     {
                         nameof(HasSetup), nameof(HasNetwork), nameof(CurrentTemplate), nameof(CurrentNetwork),
                         nameof(SetupActionText), nameof(SetupHint), nameof(ComposeHint), nameof(HasComposeHint),
                     })
                Raise(n);
            Refreshable();
        }
    }

    public bool HasSetup => State.HasSetup;
    public bool HasNetwork => State.Network.Length > 0;
    public string CurrentTemplate => State.HasSetup ? State.Template : "none";
    public string CurrentNetwork => HasNetwork ? State.Network : "none";
    public bool HasComposeHint => State.ComposeNetwork is { Length: > 0 };
    public string ComposeHint => $"compose declares “{State.ComposeNetwork}”";

    // --- templates -------------------------------------------------------------

    public ObservableCollection<string> Templates { get; } = [];

    private string _selectedTemplate = "";
    public string SelectedTemplate
    {
        get => _selectedTemplate;
        set
        {
            if (!Set(ref _selectedTemplate, value)) return;
            Raise(nameof(SetupActionText));
            Raise(nameof(SetupHint));
            Refreshable();
        }
    }

    private bool _force;
    public bool Force
    {
        get => _force;
        set { if (Set(ref _force, value)) { Raise(nameof(SetupActionText)); Raise(nameof(SetupHint)); } }
    }

    /// <summary>The button says what it is about to do - the whole point of showing
    /// the current template next to it.</summary>
    public string SetupActionText
    {
        get
        {
            if (!HasSetup) return "Create setup";
            if (Force) return "Replace setup";
            return State.Template == SelectedTemplate ? "Up to date" : "Change setup";
        }
    }

    public string SetupHint
    {
        get
        {
            if (!HasFolder) return "";
            if (!HasSetup) return "writes .devcontainer/ into this folder";
            if (State.Template == SelectedTemplate && !Force) return "this folder already uses that template";
            return $"replaces .devcontainer/ — the old one is kept as .devcontainer.bak";
        }
    }

    // --- network ---------------------------------------------------------------

    private string _networkInput = "";
    public string NetworkInput
    {
        get => _networkInput;
        set { if (Set(ref _networkInput, value)) Refreshable(); }
    }

    // --- console ---------------------------------------------------------------

    public string Output => _output.Length == 0
        ? "Output from every command shows up here."
        : _output.ToString();

    private bool _isBusy;
    public bool IsBusy
    {
        get => _isBusy;
        private set { if (Set(ref _isBusy, value)) Refreshable(); }
    }

    private string _status = "ready";
    public string Status
    {
        get => _status;
        private set => Set(ref _status, value);
    }

    private string _machine = "";
    public string Machine
    {
        get => _machine;
        private set => Set(ref _machine, value);
    }

    /// <summary>The extra buttons, folded away until asked for. Stays closed by
    /// default so the window opens on the two things you actually press.</summary>
    private bool _showTools;
    public bool ShowTools
    {
        get => _showTools;
        set => Set(ref _showTools, value);
    }

    /// <summary>The console opens itself the first time something runs, and you can
    /// fold it away again. Nobody wants to hunt for the output of a failed command.</summary>
    private bool _showOutput;
    public bool ShowOutput
    {
        get => _showOutput;
        set => Set(ref _showOutput, value);
    }

    private bool _pinned = true;
    public bool Pinned
    {
        get => _pinned;
        set => Set(ref _pinned, value);
    }

    // --- commands --------------------------------------------------------------

    public AsyncCommand ChooseFolderCommand { get; }
    public AsyncCommand ApplySetupCommand { get; }
    public AsyncCommand SetNetworkCommand { get; }
    public AsyncCommand ClearNetworkCommand { get; }
    public AsyncCommand UseComposeNetworkCommand { get; }
    public AsyncCommand OpenCommand { get; }
    public AsyncCommand ContainerCommand { get; }
    public AsyncCommand FixPermsCommand { get; }
    public AsyncCommand CheckVersionsCommand { get; }
    public AsyncCommand DoctorCommand { get; }
    public AsyncCommand WhereCommand { get; }
    public AsyncCommand RepairCommand { get; }
    public AsyncCommand UpdateCommand { get; }
    public AsyncCommand ExtSaveCommand { get; }
    public AsyncCommand ExtExtrasCommand { get; }
    public AsyncCommand UpCommand { get; }
    public AsyncCommand DownCommand { get; }
    public AsyncCommand ShellCommand { get; }
    public AsyncCommand GoinfreCommand { get; }
    public AsyncCommand LogsCommand { get; }
    public AsyncCommand RefreshCommand { get; }
    public AsyncCommand ClearOutputCommand { get; }

    private void Refreshable()
    {
        foreach (var c in new[]
                 {
                     ChooseFolderCommand, ApplySetupCommand, SetNetworkCommand, ClearNetworkCommand,
                     UseComposeNetworkCommand, OpenCommand, ContainerCommand, FixPermsCommand,
                     CheckVersionsCommand, DoctorCommand, WhereCommand, RepairCommand, UpdateCommand,
                     ExtSaveCommand, ExtExtrasCommand, UpCommand, DownCommand, ShellCommand,
                     GoinfreCommand, LogsCommand, RefreshCommand, ClearOutputCommand,
                 })
            c.RaiseCanExecuteChanged();
    }

    // --- doing things ----------------------------------------------------------

    public async Task LoadAsync()
    {
        foreach (var t in await DevboxCli.TemplatesAsync().ConfigureAwait(true)) Templates.Add(t);
        ReadState();
        SelectedTemplate = Templates.Contains(State.Template) ? State.Template
            : Templates.Contains("base") ? "base"
            : Templates.FirstOrDefault() ?? "";
        NetworkInput = State.Network;
        await ReadMachineAsync().ConfigureAwait(true);
    }

    private async Task RefreshAsync()
    {
        ReadState();
        NetworkInput = State.Network;
        await ReadMachineAsync().ConfigureAwait(true);
        Status = "refreshed";
    }

    /// <summary>One line for the header: which store, which docker. Both come from
    /// `devbox where`, so they cannot disagree with the CLI.</summary>
    private async Task ReadMachineAsync()
    {
        var text = await DevboxCli.CaptureAsync("where").ConfigureAwait(true);
        var bits = new List<string>();
        foreach (var line in text.Split('\n'))
        {
            var i = line.IndexOf(':');
            if (i < 0) continue;
            var key = line[..i].Trim();
            var val = line[(i + 1)..].Trim();
            if (val.Length == 0) continue;
            if (key == "store") bits.Add(val);
            else if (key == "docker mode") bits.Add(val);
        }
        Machine = bits.Count > 0 ? string.Join("  •  ", bits) : "machine not provisioned yet";
    }

    private void ReadState() => State = ProjectState.Read(HasFolder ? Folder : null);

    private async Task ChooseFolderAsync()
    {
        var picked = await _pickFolder().ConfigureAwait(true);
        if (picked is null) return;
        Folder = picked;
        SelectedTemplate = Templates.Contains(State.Template) ? State.Template : SelectedTemplate;
        NetworkInput = State.Network;
        Status = $"opened {ProjectName}";
    }

    private async Task ApplySetupAsync()
    {
        // The CLI decides what "change" means - including refusing to touch a folder
        // that already matches. We only pass what the buttons say.
        var args = new List<string> { "init", SelectedTemplate };
        if (NetworkInput.Trim().Length > 0) { args.Add("--network"); args.Add(NetworkInput.Trim()); }
        if (Force) args.Add("--force");
        await RunAsync(args, project: true).ConfigureAwait(true);
        Force = false;
    }

    private Task RunAsync(IReadOnlyList<string> args, bool project = false)
        => RunExeAsync(DevboxCli.Exe, args, project);

    private async Task RunExeAsync(string exe, IReadOnlyList<string> args, bool project = false)
    {
        IsBusy = true;
        ShowOutput = true;
        Status = string.Join(' ', args.Take(2));
        Append($"$ {Path.GetFileName(exe)} {string.Join(' ', args)}");

        // Working directory matters: `devbox init` writes into the folder it runs in.
        var cwd = HasFolder ? Folder : null;
        var code = await DevboxCli.RunAsync(exe, args, cwd, line => Dispatcher.UIThread.Post(() => Append(line)))
            .ConfigureAwait(true);

        Append(code == 0 ? "-- done" : $"-- failed (exit {code})");
        Append("");
        IsBusy = false;
        Status = code == 0 ? "ready" : $"last command failed ({code})";
        if (project) ReadState();
    }

    /// <summary>Hand off to VSCode and return at once. Its progress belongs in its
    /// own window, not in a console pane that cannot keep up with it.</summary>
    private Task LaunchAsync(IReadOnlyList<string> args, string what)
    {
        Append($"$ devbox {string.Join(' ', args)}");
        var err = DevboxCli.Launch(args, HasFolder ? Folder : null);
        if (err is null)
        {
            Append($"-- opening {what}");
            Status = $"opening {what}";
        }
        else
        {
            Append($"-- could not start it: {err}");
            Status = "launch failed";
        }
        return Task.CompletedTask;
    }

    private Task TerminalAsync(string command)
    {
        if (!DevboxCli.OpenInTerminal(command, HasFolder ? Folder : null))
            Append($"no terminal emulator found — run it yourself:  {command}");
        else
            Status = "opened a terminal";
        return Task.CompletedTask;
    }

    /// <summary>
    /// Add a line to the console.
    ///
    /// This used to raise Output on every single line, and Output rebuilds the
    /// whole string - so a chatty command (a container build is thousands of
    /// lines) made the UI thread re-allocate and re-measure everything, over and
    /// over, until the window stopped painting and went black. Now lines go into
    /// a buffer and the pane is refreshed on a timer, so the cost per line is an
    /// append and nothing else.
    /// </summary>
    private void Append(string line)
    {
        lock (_pending) _pending.Add(line);
        _flush ??= DispatcherTimer.Run(FlushOutput, TimeSpan.FromMilliseconds(100),
                                       DispatcherPriority.Background);
    }

    private bool FlushOutput()
    {
        string[] lines;
        lock (_pending)
        {
            if (_pending.Count == 0) return true;      // keep the timer, nothing to do
            lines = _pending.ToArray();
            _pending.Clear();
        }

        foreach (var l in lines) _output.AppendLine(l);

        // A build can print megabytes. Keep the tail: it is what you read anyway,
        // and an unbounded TextBlock is the other half of the freeze.
        if (_output.Length > OutputLimit)
        {
            var text = _output.ToString();
            var cut = text.IndexOf('\n', text.Length - OutputLimit);
            _output.Clear();
            _output.Append("… earlier output trimmed …\n")
                   .Append(text[(cut < 0 ? text.Length - OutputLimit : cut + 1)..]);
        }

        Raise(nameof(Output));
        return true;
    }

    // --- remembering the last folder -------------------------------------------

    private static string StateFile
    {
        get
        {
            var dir = Environment.GetEnvironmentVariable("VS_STATE_DIR") is { Length: > 0 } d
                ? d
                : Path.Combine(DevboxCli.Home, ".local", "state", "vscode-setup");
            return Path.Combine(dir, "ui-folder");
        }
    }

    private static string? LoadLastFolder()
    {
        try { return File.Exists(StateFile) ? File.ReadAllText(StateFile).Trim() : null; }
        catch (Exception) { return null; }
    }

    private static void SaveLastFolder(string folder)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(StateFile)!);
            File.WriteAllText(StateFile, folder);
        }
        catch (Exception)
        {
            // Remembering is a nicety, not a feature worth an error dialog.
        }
    }

    private static string? FirstUsable(params string?[] candidates)
        => candidates.FirstOrDefault(c => c is { Length: > 0 } && Directory.Exists(c));
}
