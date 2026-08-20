using Microsoft.Win32;
using Sevelr.Logging;
using Sevelr.Policies;

namespace Sevelr.Browser;

public class ChromiumPolicyManager(IAuditLogger logger) : IBrowserPolicyManager
{
    private static readonly string[] PolicyRegistryPaths =
    [
        @"SOFTWARE\Policies\BraveSoftware\Brave",
        @"SOFTWARE\Policies\Chromium",
        @"SOFTWARE\Policies\Google\Chrome"
    ];

    public void ApplyPolicy(CompiledPolicy policy)
    {
        foreach (var regPath in PolicyRegistryPaths)
        {
            try
            {
                using var key = Registry.CurrentUser.CreateSubKey(regPath, true);
                if (key == null) continue;

                // 1. Native Chromium URL Allowlist / Blocklist
                if (policy.Network.Mode == "allowlist")
                {
                    using var blockKey = key.CreateSubKey("URLBlocklist", true);
                    foreach (var valName in blockKey.GetValueNames())
                        blockKey.DeleteValue(valName, false);
                    blockKey.SetValue("1", "*");

                    using var allowKey = key.CreateSubKey("URLAllowlist", true);
                    foreach (var valName in allowKey.GetValueNames())
                        allowKey.DeleteValue(valName, false);

                    int idx = 1;
                    foreach (var d in policy.Network.ExactDomains)
                    {
                        allowKey.SetValue((idx++).ToString(), $"https://{d}");
                        allowKey.SetValue((idx++).ToString(), $"https://{d}/*");
                        allowKey.SetValue((idx++).ToString(), $"http://{d}");
                        allowKey.SetValue((idx++).ToString(), $"http://{d}/*");
                    }
                    foreach (var w in policy.Network.WildcardDomains)
                    {
                        allowKey.SetValue((idx++).ToString(), $"https://*.{w}");
                        allowKey.SetValue((idx++).ToString(), $"https://*.{w}/*");
                        allowKey.SetValue((idx++).ToString(), $"http://*.{w}");
                        allowKey.SetValue((idx++).ToString(), $"http://*.{w}/*");
                    }
                }

                // 2. Lock Developer Tools
                if (policy.Browser.DisableDevTools)
                {
                    key.SetValue("DeveloperToolsAvailability", 2, RegistryValueKind.DWord);
                }

                // 3. Privacy
                key.SetValue("PasswordManagerEnabled", 0, RegistryValueKind.DWord);
                key.SetValue("SyncDisabled", 1, RegistryValueKind.DWord);
                key.SetValue("MetricsReportingEnabled", 0, RegistryValueKind.DWord);

                logger.LogSecurityEvent(policy.ProjectId, "BrowserPolicy", regPath, "Apply", "Injected native enterprise URL policies.");
            }
            catch (Exception ex)
            {
                logger.LogWarning(policy.ProjectId, "BrowserPolicy", $"Failed applying registry policy to {regPath}: {ex.Message}");
            }
        }
    }

    public void RemovePolicy(string projectId)
    {
        foreach (var regPath in PolicyRegistryPaths)
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(regPath, true);
                if (key != null)
                {
                    key.DeleteSubKeyTree("URLBlocklist", false);
                    key.DeleteSubKeyTree("URLAllowlist", false);
                    key.DeleteValue("DeveloperToolsAvailability", false);
                    key.DeleteValue("PasswordManagerEnabled", false);
                    key.DeleteValue("SyncDisabled", false);
                    key.DeleteValue("MetricsReportingEnabled", false);
                }
            }
            catch { }
        }
    }
}
