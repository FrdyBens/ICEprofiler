using System.Text.RegularExpressions;
using Sevelr.Configuration.Models;
using Sevelr.Core;

namespace Sevelr.Configuration;

public static class ConfigValidator
{
    private static readonly Regex ProjectIdRegex = new("^[a-zA-Z0-9_-]{3,64}$", RegexOptions.Compiled);
    private static readonly Regex DomainRegex = new(@"^(\*\.)?([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$", RegexOptions.Compiled);

    public static List<string> Validate(ProjectConfig config)
    {
        var errors = new List<string>();

        if (string.IsNullOrWhiteSpace(config.Project.Id))
            errors.Add("Project ID must not be empty.");
        else if (!ProjectIdRegex.IsMatch(config.Project.Id))
            errors.Add($"Invalid project ID '{config.Project.Id}'. Allowed: alphanumeric, underscore, hyphen (3-64 chars).");

        if (string.IsNullOrWhiteSpace(config.Application.Provider))
            errors.Add("Application provider must be specified.");

        if (config.Network.Mode is not ("allowlist" or "denylist" or "block-all"))
            errors.Add($"Unknown network mode '{config.Network.Mode}'.");

        foreach (var domain in config.Network.AllowedDomains)
        {
            if (!DomainRegex.IsMatch(domain) && domain != "localhost")
                errors.Add($"Invalid domain format in allowedDomains: '{domain}'");
        }

        foreach (var port in config.Network.AllowedPorts)
        {
            if (port is < 1 or > 65535)
                errors.Add($"Port out of range: {port}");
        }

        if (config.Security.Mode is not ("strict" or "balanced" or "permissive"))
            errors.Add($"Invalid security mode '{config.Security.Mode}'.");

        return errors;
    }

    public static void ValidateOrThrow(ProjectConfig config)
    {
        var errors = Validate(config);
        if (errors.Count > 0)
            throw new ConfigurationException($"Configuration validation failed:\n - {string.Join("\n - ", errors)}");
    }
}