using System.Text.Json;
using Sevelr.Configuration.Models;
using Sevelr.Core;

namespace Sevelr.Projects;

public static class TemplateManager
{
    public static ProjectConfig GetTemplate(string templateName)
    {
        var templateFile = Path.Combine(AppContext.BaseDirectory, "templates", $"{templateName.ToLowerInvariant()}.json");
        if (File.Exists(templateFile))
        {
            var json = File.ReadAllText(templateFile);
            return JsonSerializer.Deserialize<ProjectConfig>(json) ?? CreateDefaultStrictConfig();
        }

        return templateName.ToLowerInvariant() switch
        {
            "balanced" => CreateDefaultBalancedConfig(),
            "temporary" => CreateDefaultTemporaryConfig(),
            _ => CreateDefaultStrictConfig()
        };
    }

    public static ProjectConfig CreateDefaultStrictConfig() => new()
    {
        Project = new() { Template = "strict" },
        Application = new() { Provider = "brave" },
        Network = new() { Mode = "allowlist", AllowHttp = false, AllowHttps = true },
        Filesystem = new() { Encrypted = true },
        Process = new() { Monitor = true, SingleInstancePerProject = true },
        Security = new() { Mode = "strict", FailClosed = true, TamperDetection = true }
    };

    public static ProjectConfig CreateDefaultBalancedConfig() => new()
    {
        Project = new() { Template = "balanced" },
        Application = new() { Provider = "brave" },
        Network = new() { Mode = "allowlist", AllowHttp = true, AllowHttps = true },
        Filesystem = new() { Encrypted = false },
        Process = new() { Monitor = true, SingleInstancePerProject = true },
        Security = new() { Mode = "balanced", FailClosed = false, TamperDetection = false }
    };

    public static ProjectConfig CreateDefaultTemporaryConfig() => new()
    {
        Project = new() { Template = "temporary" },
        Application = new() { Provider = "brave" },
        Network = new() { Mode = "allowlist", AllowHttp = true, AllowHttps = true },
        Filesystem = new() { Encrypted = true, TemporaryFiles = "isolated" },
        Privacy = new() { ClearOnExit = true },
        Security = new() { Mode = "strict", FailClosed = true }
    };
}
