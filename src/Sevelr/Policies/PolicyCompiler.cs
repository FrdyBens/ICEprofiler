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
