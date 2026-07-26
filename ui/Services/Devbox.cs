using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;

namespace Devbox.Ui.Services;

/// <summary>
/// Runs the `devbox` CLI. Every action in this app goes through here, so the app
/// can only ever do what the command line already does.
/// </summary>
public static class DevboxCli
{
    /// <summary>Where the scripts live. Same default as every script in the repo.</summary>
    public static string SetupHome { get; } =
        Environment.GetEnvironmentVariable("VS_SETUP_HOME") is { Length: > 0 } h
            ? h
            : Path.Combine(Home, ".config", "vscode-setup");

    public static string Home =>
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    /// <summary>The CLI itself: the installed copy, else the shim, else PATH.</summary>
    public static string Exe { get; } = FirstExisting(
        Path.Combine(SetupHome, "bin", "devbox"),
        Path.Combine(Home, ".local", "bin", "devbox")) ?? "devbox";

    public static string DoctorExe { get; } =
        FirstExisting(Path.Combine(SetupHome, "bin", "setup-doctor")) ?? "setup-doctor";

    public static string EnsureExe { get; } =
        FirstExisting(Path.Combine(SetupHome, "ensure.sh")) ?? "true";

    private static string? FirstExisting(params string[] paths)
    {
        foreach (var p in paths)
            if (File.Exists(p)) return p;
        return null;
    }

    /// <summary>
    /// Run a command, streaming stdout AND stderr to <paramref name="onLine"/> as they
    /// arrive. stderr matters: devbox writes all of its info/ok/warn lines there.
    /// </summary>
    public static async Task<int> RunAsync(
        string exe, IReadOnlyList<string> args, string? workingDirectory, Action<string> onLine)
    {
        var psi = new ProcessStartInfo
        {
            FileName = exe,
            WorkingDirectory = workingDirectory is { Length: > 0 } && Directory.Exists(workingDirectory)
                ? workingDirectory
                : Home,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        psi.Environment["VS_SETUP_HOME"] = SetupHome;

        using var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        proc.OutputDataReceived += (_, e) => { if (e.Data is not null) onLine(e.Data); };
        proc.ErrorDataReceived  += (_, e) => { if (e.Data is not null) onLine(e.Data); };

        try
        {
            proc.Start();
        }
        catch (Exception ex)
        {
            onLine($"could not run {exe}: {ex.Message}");
            return 127;
        }

        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();
        await proc.WaitForExitAsync().ConfigureAwait(false);
        return proc.ExitCode;
    }

    /// <summary>Run `devbox …` and stream it.</summary>
    public static Task<int> RunAsync(IReadOnlyList<string> args, string? workingDirectory, Action<string> onLine)
        => RunAsync(Exe, args, workingDirectory, onLine);

    /// <summary>
    /// Start `devbox …` and walk away. For the two commands that hand over to
    /// VSCode: those do not finish - `devbox container` execs the editor, which
    /// lives as long as you keep it open. Waiting on that is waiting forever, and
    /// streaming a container build's output through the window is what turned it
    /// black. So we launch, and let the editor report its own progress.
    /// </summary>
    public static string? Launch(IReadOnlyList<string> args, string? workingDirectory)
    {
        var psi = new ProcessStartInfo
        {
            FileName = Exe,
            WorkingDirectory = workingDirectory is { Length: > 0 } && Directory.Exists(workingDirectory)
                ? workingDirectory
                : Home,
            UseShellExecute = false,
            RedirectStandardOutput = true,   // swallowed on purpose: nothing reads it,
            RedirectStandardError = true,    // and an unread inherited pipe can block us
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        psi.Environment["VS_SETUP_HOME"] = SetupHome;

        try
        {
            var p = Process.Start(psi);
            if (p is null) return "could not start " + Exe;
            // Drain both pipes into nothing. Without this a chatty child fills the
            // pipe buffer and blocks on its own write.
            p.OutputDataReceived += (_, _) => { };
            p.ErrorDataReceived += (_, _) => { };
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            return null;
        }
        catch (Exception ex)
        {
            return ex.Message;
        }
    }

    /// <summary>Run `devbox …` for its output only (no streaming, no console noise).</summary>
    public static async Task<string> CaptureAsync(params string[] args)
    {
        var sb = new System.Text.StringBuilder();
        await RunAsync(args, null, line => sb.AppendLine(line)).ConfigureAwait(false);
        return sb.ToString();
    }

    /// <summary>
    /// The templates you can scaffold from. `devbox templates` is the source of
    /// truth; the folder scan is only there for an installed copy older than that
    /// command. Either way, adding a template folder makes it appear here.
    /// </summary>
    public static async Task<List<string>> TemplatesAsync()
    {
        var names = new List<string>();
        foreach (var line in (await CaptureAsync("templates").ConfigureAwait(false))
                 .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (!line.Contains(' ') && !line.Contains(':')) names.Add(line);
        }

        if (names.Count == 0)
        {
            var dir = Path.Combine(SetupHome, "templates", "devcontainer");
            if (Directory.Exists(dir))
                foreach (var d in Directory.GetDirectories(dir))
                    if (File.Exists(Path.Combine(d, "devcontainer.json")))
                        names.Add(Path.GetFileName(d));
        }

        names.Sort(StringComparer.Ordinal);
        return names;
    }

    /// <summary>
    /// Open a terminal on a command. For the two things a GUI cannot host: an
    /// interactive shell, and sudo asking for a password.
    /// </summary>
    public static bool OpenInTerminal(string command, string? workingDirectory)
    {
        string[][] candidates =
        [
            ["ptyxis", "--", "bash", "-lc", command],
            ["gnome-terminal", "--", "bash", "-lc", command],
            ["konsole", "-e", "bash", "-lc", command],
            ["xfce4-terminal", "-e", $"bash -lc \"{command}\""],
            ["x-terminal-emulator", "-e", "bash", "-lc", command],
            ["xterm", "-e", "bash", "-lc", command],
        ];

        foreach (var c in candidates)
        {
            var psi = new ProcessStartInfo
            {
                FileName = c[0],
                WorkingDirectory = workingDirectory is { Length: > 0 } && Directory.Exists(workingDirectory)
                    ? workingDirectory
                    : Home,
                UseShellExecute = false,
            };
            for (var i = 1; i < c.Length; i++) psi.ArgumentList.Add(c[i]);
            psi.Environment["VS_SETUP_HOME"] = SetupHome;
            try
            {
                if (Process.Start(psi) is not null) return true;
            }
            catch
            {
                // Not installed - try the next one.
            }
        }
        return false;
    }
}
