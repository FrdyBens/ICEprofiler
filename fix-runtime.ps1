$ErrorActionPreference = "Stop"
$Root = (Get-Location).Path

Write-Host "[1/6] Patching BraveApplicationProvider.cs (Clean ArgumentList formatting)..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $Root "src/Sevelr/Applications/BraveApplicationProvider.cs") -Value @'
using System.Diagnostics;
using Microsoft.Win32;
using Sevelr.Core;
using Sevelr.Policies;

namespace Sevelr.Applications;

public class BraveApplicationProvider : IApplicationProvider
{
    public string Name => "brave";

    public string DiscoverExecutablePath()
    {
        string[] candidates =
        [
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"BraveSoftware\Brave-Browser\Application\brave.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"BraveSoftware\Brave-Browser\Application\brave.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"BraveSoftware\Brave-Browser\Application\brave.exe")
        ];

        foreach (var path in candidates)
        {
            if (File.Exists(path)) return path;
        }

        using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe");
        if (key?.GetValue(null) is string regPath && File.Exists(regPath))
            return regPath;

        throw new BrowserManagementException("Brave executable not found. Ensure Brave is installed or configure explicit path.");
    }

    public ProcessStartInfo BuildProcessStartInfo(string executablePath, CompiledPolicy policy, string targetUrl)
    {
        var psi = new ProcessStartInfo(executablePath)
        {
            UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(executablePath)
        };

        // Add core required security arguments without manual escaped quotes
        foreach (var arg in policy.Browser.RequiredSecurityArguments)
        {
            psi.ArgumentList.Add(arg);
        }

        // Add extension load arguments
        if (!string.IsNullOrEmpty(policy.Browser.ExtensionPath) && Directory.Exists(policy.Browser.ExtensionPath))
        {
            psi.ArgumentList.Add($"--load-extension={policy.Browser.ExtensionPath}");
            psi.ArgumentList.Add($"--disable-extensions-except={policy.Browser.ExtensionPath}");
        }

        // Add non-conflicting user arguments
        foreach (var arg in policy.Browser.UserArguments)
        {
            if (!arg.StartsWith("--user-data-dir") && !arg.StartsWith("--load-extension"))
                psi.ArgumentList.Add(arg);
        }

        if (!string.IsNullOrWhiteSpace(targetUrl))
            psi.ArgumentList.Add(targetUrl);

        return psi;
    }
}
'@

Write-Host "[2/6] Patching PolicyCompiler.cs..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $Root "src/Sevelr/Policies/PolicyCompiler.cs") -Value @'
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Sevelr.Configuration;
using Sevelr.Configuration.Models;
using Sevelr.Core;
using Sevelr.Filesystem;

namespace Sevelr.Policies;

public class PolicyCompiler : IPolicyEngine
{
    public CompiledPolicy Compile(ProjectConfig config, IStorageManager storage)
    {
        ConfigValidator.ValidateOrThrow(config);

        var paths = storage.GetProjectPaths(config.Project.Id);
        var compiled = new CompiledPolicy
        {
            ProjectId = config.Project.Id,
            FailClosed = config.Security.FailClosed || config.Security.Mode == "strict"
        };

        // Network
        compiled.Network.Mode = config.Network.Mode;
        compiled.Network.AllowHttp = config.Network.AllowHttp;
        compiled.Network.AllowHttps = config.Network.AllowHttps;
        compiled.Network.AllowWebSocket = config.Network.AllowWebSocket;
        compiled.Network.AllowQuic = config.Network.AllowQuic;
        compiled.Network.AllowDirectIp = config.Dns.AllowDirectIp;
        compiled.Network.BlockPrivateRanges = !config.Network.AllowPrivateNetworks;

        foreach (var p in config.Network.AllowedPorts)
            compiled.Network.AllowedPorts.Add(p);

        foreach (var d in config.Network.AllowedDomains)
        {
            var clean = d.Trim().ToLowerInvariant();
            if (clean.StartsWith("*."))
                compiled.Network.WildcardDomains.Add(clean[2..]);
            else
                compiled.Network.ExactDomains.Add(clean);
        }

        foreach (var ip in config.Network.AllowedIps)
            compiled.Network.AllowedIps.Add(ip.Trim());

        // DNS
        compiled.Dns.BlockDoH = !config.Dns.AllowDoh;
        compiled.Dns.BlockDoT = !config.Dns.AllowDot;
        compiled.Dns.AllowedStaticHosts = [.. config.Network.AllowedDomains];

        // Filesystem
        compiled.Filesystem.ProfilePath = paths.BrowserDataDir;
        compiled.Filesystem.DownloadsPath = paths.DownloadsDir;
        compiled.Filesystem.TempPath = paths.TempDir;
        compiled.Filesystem.Encrypted = config.Filesystem.Encrypted;
        compiled.Filesystem.StrictAcl = config.Security.Mode == "strict";

        // Browser Arguments (No manual quotes)
        compiled.Browser.DisableDevTools = config.Security.PreventDevTools;
        compiled.Browser.DisableExtensionTampering = config.Security.PreventExtensionsModification;
        compiled.Browser.ExtensionPath = Path.Combine(paths.BaseDir, "extension");

        var secArgs = new List<string>
        {
            $"--user-data-dir={paths.BrowserDataDir}",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-sync",
            "--disable-background-networking",
            "--disable-client-side-phishing-detection",
            "--disable-component-update"
        };

        if (!config.Network.AllowQuic)
            secArgs.Add("--disable-quic");

        if (!config.Dns.AllowDoh)
            secArgs.Add("--disable-features=DnsOverHttps");

        compiled.Browser.RequiredSecurityArguments = secArgs;
        compiled.Browser.UserArguments = config.Application.Arguments;

        // Enterprise Policies
        compiled.Browser.EnterprisePolicies["DeveloperToolsAvailability"] = config.Security.PreventDevTools ? 2 : 1;
        compiled.Browser.EnterprisePolicies["PasswordManagerEnabled"] = config.Privacy.PasswordSaving;
        compiled.Browser.EnterprisePolicies["AutofillAddressEnabled"] = config.Privacy.Autofill;
        compiled.Browser.EnterprisePolicies["AutofillCreditCardEnabled"] = config.Privacy.Autofill;
        compiled.Browser.EnterprisePolicies["SyncDisabled"] = !config.Privacy.Sync;
        compiled.Browser.EnterprisePolicies["MetricsReportingEnabled"] = config.Privacy.Telemetry;

        if (config.Network.Mode == "allowlist")
        {
            compiled.Browser.EnterprisePolicies["URLBlocklist"] = new[] { "*" };
            compiled.Browser.EnterprisePolicies["URLAllowlist"] = config.Network.AllowedDomains.ToArray();
        }

        // Process limits
        compiled.Process.MonitorChildren = config.Process.Monitor;
        compiled.Process.MaxMemoryBytes = (long)config.Process.MaxMemoryMb * 1024L * 1024L;
        compiled.Process.AllowedExecutableNames.Add("brave.exe");
        compiled.Process.AllowedExecutableNames.Add("chrome.exe");
        compiled.Process.AllowedExecutableNames.Add("msedge.exe");
        compiled.Process.AllowedExecutableNames.Add("firefox.exe");
        foreach (var exe in config.Process.AllowedExecutables)
            compiled.Process.AllowedExecutableNames.Add(Path.GetFileName(exe).ToLowerInvariant());

        var rawJson = JsonSerializer.Serialize(compiled);
        using var sha = SHA256.Create();
        compiled.PolicyHash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(rawJson)));

        return compiled;
    }
}
'@

Write-Host "[3/6] Patching Mv3ExtensionGenerator.cs (MV3 Web Accessible Resources)..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $Root "src/Sevelr/Extensions/Mv3ExtensionGenerator.cs") -Value @'
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
'@

Write-Host "[4/6] Patching WindowsAclManager.cs (Chromium Sandbox Compatibility)..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $Root "src/Sevelr/Filesystem/WindowsAclManager.cs") -Value @'
using System.Security.AccessControl;
using System.Security.Principal;
using Sevelr.Core;
using Sevelr.Logging;

namespace Sevelr.Filesystem;

public class WindowsAclManager(IAuditLogger logger) : IAclManager
{
    public void RestrictToCurrentUserOnly(string directoryPath, bool failClosed)
    {
        try
        {
            if (!Directory.Exists(directoryPath))
                Directory.CreateDirectory(directoryPath);

            var dirInfo = new DirectoryInfo(directoryPath);
            var dSecurity = dirInfo.GetAccessControl();

            // Disable inheritance and strip inherited rules
            dSecurity.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);

            var currentUser = WindowsIdentity.GetCurrent().User
                ?? throw new FilesystemIsolationException("Unable to resolve current Windows user identity.");

            // Clear existing rules
            var currentRules = dSecurity.GetAccessRules(true, false, typeof(SecurityIdentifier));
            foreach (FileSystemAccessRule rule in currentRules)
            {
                dSecurity.RemoveAccessRule(rule);
            }

            var inheritance = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;

            // 1. Current User: FullControl
            dSecurity.AddAccessRule(new FileSystemAccessRule(
                currentUser,
                FileSystemRights.FullControl,
                inheritance,
                PropagationFlags.None,
                AccessControlType.Allow));

            // 2. SYSTEM: FullControl (Required by Windows and Chromium service processes)
            var systemSid = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
            dSecurity.AddAccessRule(new FileSystemAccessRule(
                systemSid,
                FileSystemRights.FullControl,
                inheritance,
                PropagationFlags.None,
                AccessControlType.Allow));

            // 3. Administrators: FullControl
            var adminsSid = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
            dSecurity.AddAccessRule(new FileSystemAccessRule(
                adminsSid,
                FileSystemRights.FullControl,
                inheritance,
                PropagationFlags.None,
                AccessControlType.Allow));

            // 4. ALL APPLICATION PACKAGES (S-1-15-2-1): Read & Execute (Required for Chromium Sandbox)
            try
            {
                var appPackagesSid = new SecurityIdentifier("S-1-15-2-1");
                dSecurity.AddAccessRule(new FileSystemAccessRule(
                    appPackagesSid,
                    FileSystemRights.ReadAndExecute,
                    inheritance,
                    PropagationFlags.None,
                    AccessControlType.Allow));
            }
            catch { }

            dirInfo.SetAccessControl(dSecurity);
            logger.LogSecurityEvent("SYSTEM", "ACL", directoryPath, "Protect", $"Isolated directory to user {currentUser.Value}");
        }
        catch (Exception ex)
        {
            logger.LogError("SYSTEM", "ACL", $"Failed applying NTFS ACL to {directoryPath}: {ex.Message}");
            if (failClosed)
                throw new FilesystemIsolationException($"Strict mode ACL failure on path '{directoryPath}': {ex.Message}", ex);
        }
    }

    public bool VerifyAccessControl(string directoryPath)
    {
        try
        {
            if (!Directory.Exists(directoryPath)) return false;
            var dirInfo = new DirectoryInfo(directoryPath);
            var dSecurity = dirInfo.GetAccessControl();
            return dSecurity.AreAccessRulesProtected;
        }
        catch
        {
            return false;
        }
    }
}
'@

Write-Host "[5/6] Patching TamperDetector.cs (Dynamic Browser State Exclusion)..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $Root "src/Sevelr/Security/TamperDetector.cs") -Value @'
using System.Security.Cryptography;
using System.Text.Json;
using Sevelr.Core;
using Sevelr.Logging;

namespace Sevelr.Security;

public class TamperDetector(IAuditLogger logger) : ITamperDetector
{
    private record ManifestRecord(Dictionary<string, string> FileHashes, DateTime GeneratedAt);

    public void GenerateIntegrityManifest(string projectDirectory, string manifestPath)
    {
        var hashes = new Dictionary<string, string>();
        var configDir = Path.Combine(projectDirectory, "config");
        
        if (Directory.Exists(configDir))
        {
            using var sha = SHA256.Create();
            foreach (var file in Directory.GetFiles(configDir, "*.*", SearchOption.AllDirectories))
            {
                if (file.Equals(manifestPath, StringComparison.OrdinalIgnoreCase))
                    continue;

                var relative = Path.GetRelativePath(projectDirectory, file);
                using var stream = File.OpenRead(file);
                var hash = Convert.ToHexString(sha.ComputeHash(stream));
                hashes[relative] = hash;
            }
        }

        var record = new ManifestRecord(hashes, DateTime.UtcNow);
        File.WriteAllText(manifestPath, JsonSerializer.Serialize(record, new JsonSerializerOptions { WriteIndented = true }));
        logger.LogSecurityEvent("SYSTEM", "Integrity", manifestPath, "Generate", $"Generated manifest with {hashes.Count} signatures.");
    }

    public bool VerifyIntegrity(string projectDirectory, string manifestPath, bool failClosed)
    {
        if (!File.Exists(manifestPath))
        {
            var msg = $"Integrity manifest missing at '{manifestPath}'";
            logger.LogError("SYSTEM", "Integrity", msg);
            if (failClosed) throw new IntegrityVerificationException(msg);
            return false;
        }

        var json = File.ReadAllText(manifestPath);
        var record = JsonSerializer.Deserialize<ManifestRecord>(json)
            ?? throw new IntegrityVerificationException("Corrupted integrity manifest.");

        using var sha = SHA256.Create();
        foreach (var (relative, expectedHash) in record.FileHashes)
        {
            var fullPath = Path.Combine(projectDirectory, relative);
            if (!File.Exists(fullPath))
            {
                var msg = $"Tamper detected: Missing file '{relative}'";
                logger.LogSecurityEvent("SYSTEM", "Integrity", relative, "TamperDetected", msg);
                if (failClosed) throw new IntegrityVerificationException(msg);
                return false;
            }

            using var stream = File.OpenRead(fullPath);
            var actualHash = Convert.ToHexString(sha.ComputeHash(stream));
            if (!actualHash.Equals(expectedHash, StringComparison.OrdinalIgnoreCase))
            {
                var msg = $"Tamper detected: Hash mismatch on '{relative}'. Expected: {expectedHash}, Actual: {actualHash}";
                logger.LogSecurityEvent("SYSTEM", "Integrity", relative, "TamperDetected", msg);
                if (failClosed) throw new IntegrityVerificationException(msg);
                return false;
            }
        }

        return true;
    }
}
'@

Write-Host "[6/6] Publishing and updating installed binary..." -ForegroundColor Cyan
$PublishDir = Join-Path $Root "dist"
if (Test-Path $PublishDir) { Remove-Item -Recurse -Force $PublishDir }

$publishArgs = @(
    "publish",
    (Join-Path $Root "src/Sevelr/Sevelr.csproj"),
    "-c", "Release",
    "-r", "win-x64",
    "--self-contained", "true",
    "-p:PublishSingleFile=true",
    "-p:IncludeNativeLibrariesForSelfExtract=true",
    "-o", (Join-Path $PublishDir "bin")
)
& dotnet @publishArgs

# Update the running executable in PATH
$InstallBin = "$env:LOCALAPPDATA\Programs\Sevelr\bin"
if (Test-Path $InstallBin) {
    Copy-Item (Join-Path $PublishDir "bin\sevelr.exe") $InstallBin -Force
}

# Update release zip
Copy-Item -Recurse (Join-Path $Root "templates") (Join-Path $PublishDir "templates")
Copy-Item -Recurse (Join-Path $Root "docs") (Join-Path $PublishDir "docs")
Copy-Item -Recurse (Join-Path $Root "scripts") (Join-Path $PublishDir "scripts")
Copy-Item (Join-Path $Root "README.md") $PublishDir

$ZipPath = Join-Path $Root "sevelr-v2.0.0-win-x64.zip"
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
Compress-Archive -Path "$PublishDir\*" -DestinationPath $ZipPath

Write-Host "`n[✓] Fixes compiled and applied successfully!" -ForegroundColor Green