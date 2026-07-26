using System;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Devbox.Ui.Services;

/// <summary>
/// What a folder already has. Read straight off disk and never written here:
/// changing any of it is `devbox init` / `devbox network`'s job. Reading it
/// ourselves just keeps the window honest without spawning a process per repaint.
/// </summary>
public sealed record ProjectState(bool HasSetup, string Template, string Network, string? ComposeNetwork)
{
    public static readonly ProjectState None = new(false, "", "", null);

    public static ProjectState Read(string? folder)
    {
        if (string.IsNullOrWhiteSpace(folder) || !Directory.Exists(folder)) return None;

        var compose = ComposeNetworkOf(folder);
        var file = Path.Combine(folder, ".devcontainer", "devcontainer.json");
        if (!File.Exists(file)) return None with { ComposeNetwork = compose };

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(file), new JsonDocumentOptions
            {
                CommentHandling = JsonCommentHandling.Skip,
                AllowTrailingCommas = true,
            });
            var root = doc.RootElement;

            var template = root.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";

            // The same shape `devbox network` reads: the join command lists them.
            var network = "";
            if (root.TryGetProperty("postStartCommand", out var p) && p.GetString() is { } cmd)
            {
                var m = Regex.Match(cmd, @"for n in (.+?); do");
                if (m.Success) network = m.Groups[1].Value.Trim();
            }

            return new ProjectState(true, template, network, compose);
        }
        catch (Exception)
        {
            // A devcontainer.json we cannot parse is still a setup - just not one
            // we can describe. Saying "unknown" beats pretending there is none.
            return new ProjectState(true, "unknown", "", compose);
        }
    }

    /// <summary>
    /// The network this project's compose file declares, so the window can offer it
    /// instead of making you go and read the file. Mirrors _compose_network in the CLI.
    /// </summary>
    private static string? ComposeNetworkOf(string folder)
    {
        foreach (var name in new[] { "docker-compose.yml", "docker-compose.yaml", "compose.yml" })
        {
            var f = Path.Combine(folder, name);
            if (!File.Exists(f)) continue;
            try
            {
                var txt = File.ReadAllText(f);
                var block = Regex.Match(txt, @"^networks:\s*$(.*?)(?=^\S|\Z)",
                    RegexOptions.Multiline | RegexOptions.Singleline);
                if (!block.Success) return null;
                var names = Regex.Matches(block.Groups[1].Value, @"^\s+name:\s*([A-Za-z0-9._-]+)\s*$",
                    RegexOptions.Multiline);
                return names.Count == 1 ? names[0].Groups[1].Value : null;
            }
            catch (Exception)
            {
                return null;
            }
        }
        return null;
    }
}
