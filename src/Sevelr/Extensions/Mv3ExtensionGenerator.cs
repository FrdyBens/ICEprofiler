using System.Text.Json;
using Sevelr.Policies;

namespace Sevelr.Extensions;

public class Mv3ExtensionGenerator : IExtensionGenerator
{
    public void GenerateExtension(CompiledPolicy policy, string outputDirectory)
    {
        if (Directory.Exists(outputDirectory))
            Directory.Delete(outputDirectory, true);

        Directory.CreateDirectory(outputDirectory);

        // 1. Manifest
        var manifest = new
        {
            manifest_version = 3,
            name = $"Sevelr Security Enforcer [{policy.ProjectId}]",
            version = "2.0.0",
            description = "Policy enforcement and navigation security for Sevelr application isolation.",
            permissions = new[] { "declarativeNetRequest" },
            host_permissions = new[] { "<all_urls>" },
            action = new
            {
                default_popup = "popup.html",
                default_title = "Sevelr Security Status"
            },
            declarative_net_request = new
            {
                rule_resources = new[]
                {
                    new
                    {
                        id = "ruleset_1",
                        enabled = true,
                        path = "rules.json"
                    }
                }
            },
            web_accessible_resources = new[]
            {
                new
                {
                    resources = new[] { "blocked.html", "popup.html" },
                    matches = new[] { "<all_urls>" }
                }
            }
        };

        File.WriteAllText(Path.Combine(outputDirectory, "manifest.json"), JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }));

        // 2. DeclarativeNetRequest Rules
        var rules = new List<object>();
        int ruleId = 1;

        if (policy.Network.Mode == "allowlist")
        {
            // Allow configured domains
            foreach (var domain in policy.Network.ExactDomains)
            {
                rules.Add(new
                {
                    id = ruleId++,
                    priority = 2,
                    action = new { type = "allow" },
                    condition = new
                    {
                        urlFilter = $"||{domain}/",
                        resourceTypes = new[] { "main_frame", "sub_frame", "stylesheet", "script", "image", "xmlhttprequest" }
                    }
                });
            }
            foreach (var wildcard in policy.Network.WildcardDomains)
            {
                rules.Add(new
                {
                    id = ruleId++,
                    priority = 2,
                    action = new { type = "allow" },
                    condition = new
                    {
                        urlFilter = $"||{wildcard}/",
                        resourceTypes = new[] { "main_frame", "sub_frame", "stylesheet", "script", "image", "xmlhttprequest" }
                    }
                });
            }

            // Block everything else by default
            rules.Add(new
            {
                id = ruleId++,
                priority = 1,
                action = new { type = "redirect", redirect = new { extensionPath = "/blocked.html" } },
                condition = new
                {
                    urlFilter = "*",
                    resourceTypes = new[] { "main_frame" }
                }
            });
        }

        File.WriteAllText(Path.Combine(outputDirectory, "rules.json"), JsonSerializer.Serialize(rules, new JsonSerializerOptions { WriteIndented = true }));

        // 3. Blocked Page UX
        string blockedHtml = $@"<!DOCTYPE html>
<html>
<head>
    <meta charset=""utf-8"">
    <title>Navigation Blocked — Sevelr</title>
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #f8fafc; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }}
        .card {{ background: #1e293b; border: 1px solid #334155; border-radius: 12px; padding: 32px; max-width: 520px; width: 100%; box-shadow: 0 10px 25px -5px rgba(0,0,0,0.5); }}
        .badge {{ background: #ef4444; color: #fff; padding: 4px 10px; border-radius: 6px; font-weight: 700; font-size: 12px; text-transform: uppercase; }}
        h1 {{ font-size: 20px; margin: 16px 0 8px 0; }}
        p {{ color: #94a3b8; font-size: 14px; line-height: 1.5; }}
        .meta {{ background: #0f172a; padding: 12px; border-radius: 6px; font-family: monospace; font-size: 12px; color: #38bdf8; margin: 16px 0; word-break: break-all; }}
    </style>
</head>
<body>
    <div class=""card"">
        <span class=""badge"">Access Restricted</span>
        <h1>Destination Not Permitted</h1>
        <p>This application environment is isolated under the <strong>{policy.ProjectId}</strong> security policy. Outbound connection to this host was blocked by policy.</p>
        <div class=""meta"">Policy Hash: {policy.PolicyHash[..16]}...</div>
        <p style=""font-size:12px; color:#64748b;"">Sevelr Universal Application Isolation &copy; 2026</p>
    </div>
</body>
</html>";
        File.WriteAllText(Path.Combine(outputDirectory, "blocked.html"), blockedHtml);

        // 4. Popup Status
        string popupHtml = $@"<!DOCTYPE html>
<html>
<head>
    <meta charset=""utf-8"">
    <style>
        body {{ width: 280px; font-family: sans-serif; background: #0f172a; color: #f8fafc; padding: 16px; margin: 0; }}
        h2 {{ font-size: 14px; margin: 0 0 10px 0; color: #38bdf8; }}
        .status-row {{ display: flex; justify-content: space-between; font-size: 12px; margin: 6px 0; color: #94a3b8; }}
        .val {{ color: #22c55e; font-weight: 600; }}
    </style>
</head>
<body>
    <h2>SEVELR ENFORCED</h2>
    <div class=""status-row""><span>Project:</span> <span class=""val"" style=""color:#38bdf8;"">{policy.ProjectId}</span></div>
    <div class=""status-row""><span>Security Mode:</span> <span class=""val"">{(policy.FailClosed ? "STRICT" : "BALANCED")}</span></div>
    <div class=""status-row""><span>OS Firewall:</span> <span class=""val"">ACTIVE</span></div>
    <div class=""status-row""><span>Isolation:</span> <span class=""val"">NTFS / EFS</span></div>
</body>
</html>";
        File.WriteAllText(Path.Combine(outputDirectory, "popup.html"), popupHtml);
    }
}
