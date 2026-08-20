using System.Text.Json;
using Sevelr.Configuration.Models;
using Sevelr.Logging;

namespace Sevelr.Configuration;

public class MigrationManager(IAuditLogger logger)
{
    public ProjectConfig MigrateLegacyConfiguration(string allowedDomainsPath, string? settingsPath, string targetProjectId)
    {
        logger.LogSecurityEvent(targetProjectId, "ConfigMigration", "AllowedDomains", "Migrate", "Starting prototype schema migration.");

        var config = new ProjectConfig
        {
            Project = new ProjectIdentity
            {
                Id = targetProjectId,
                DisplayName = char.ToUpper(targetProjectId[0]) + targetProjectId[1..],
                Description = "Migrated from prototype Sevelr configuration.",
                Template = "balanced"
            }
        };

        if (File.Exists(allowedDomainsPath))
        {
            var content = File.ReadAllText(allowedDomainsPath);
            try
            {
                var domains = JsonSerializer.Deserialize<List<string>>(content) ?? [];
                config.Network.AllowedDomains = domains.Distinct().ToList();
            }
            catch
            {
                var doc = JsonDocument.Parse(content);
                if (doc.RootElement.TryGetProperty("domains", out var arr))
                {
                    config.Network.AllowedDomains = arr.EnumerateArray()
                        .Select(e => e.GetString()!)
                        .Where(s => !string.IsNullOrWhiteSpace(s))
                        .Distinct()
                        .ToList();
                }
            }
        }

        if (!string.IsNullOrEmpty(settingsPath) && File.Exists(settingsPath))
        {
            try
            {
                var settingsJson = JsonDocument.Parse(File.ReadAllText(settingsPath));
                if (settingsJson.RootElement.TryGetProperty("ApplicationPath", out var appPath))
                    config.Application.Executable = appPath.GetString();
                if (settingsJson.RootElement.TryGetProperty("Strict", out var strictProp))
                    config.Security.Mode = strictProp.GetBoolean() ? "strict" : "balanced";
            }
            catch (Exception ex)
            {
                logger.LogWarning(targetProjectId, "ConfigMigration", $"Could not parse legacy settings: {ex.Message}");
            }
        }

        ConfigValidator.ValidateOrThrow(config);
        logger.LogSecurityEvent(targetProjectId, "ConfigMigration", "AllowedDomains", "Success", $"Migrated {config.Network.AllowedDomains.Count} domains.");
        return config;
    }
}