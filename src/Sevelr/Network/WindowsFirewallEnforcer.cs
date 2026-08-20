using System.Diagnostics;
using System.Net;
using System.Security.Principal;
using Sevelr.Core;
using Sevelr.Logging;
using Sevelr.Policies;
using SysProcess = System.Diagnostics.Process;

namespace Sevelr.Network;

public class WindowsFirewallEnforcer(IAuditLogger logger) : INetworkEnforcer
{
    private const string RulePrefix = "SEVELR_ENFORCE_";

    public static bool IsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    public async Task ApplyPolicyAsync(CompiledPolicy policy, string executablePath)
    {
        var projectId = policy.ProjectId;
        bool isAdmin = IsAdministrator();

        if (!isAdmin)
        {
            if (policy.FailClosed)
            {
                throw new NetworkEnforcementException(
                    "Strict mode requires Windows Firewall network enforcement (Administrator privileges).\n" +
                    " -> Action 1: Re-run PowerShell as Administrator.\n" +
                    " -> Action 2: Or create/launch the project with '--template balanced' to run without elevation.");
            }
            else
            {
                logger.LogWarning(projectId, "NetworkEnforcement", "Skipping OS Firewall rules (not running as Administrator). Browser-level policy remains active.");
                return;
            }
        }

        logger.LogSecurityEvent(projectId, "NetworkEnforcement", executablePath, "Configure", "Applying native Windows Firewall rules.");

        await RemovePolicyAsync(projectId);

        if (policy.Network.Mode == "block-all")
        {
            await CreateBlockRuleAsync(projectId, executablePath, "BlockAll", "out");
            return;
        }

        // 1. Block outbound by default for this executable
        await CreateBlockRuleAsync(projectId, executablePath, "DefaultOutboundBlock", "out");

        // 2. Allow Loopback if configured
        if (!policy.Network.BlockPrivateRanges)
        {
            await CreateAllowRuleAsync(projectId, executablePath, "AllowLocal", "127.0.0.1,::1", "any");
        }

        // 3. Resolve and allow explicit IPs and domains
        var ipsToAllow = new HashSet<string>(policy.Network.AllowedIps);

        foreach (var domain in policy.Network.ExactDomains)
        {
            try
            {
                var resolved = await Dns.GetHostAddressesAsync(domain);
                foreach (var ip in resolved)
                {
                    if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6 && !policy.Network.AllowHttps)
                        continue;
                    ipsToAllow.Add(ip.ToString());
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(projectId, "DNS_Resolver", $"Could not resolve allowed domain '{domain}': {ex.Message}");
            }
        }

        if (ipsToAllow.Count > 0)
        {
            var ipList = string.Join(",", ipsToAllow);
            var ports = string.Join(",", policy.Network.AllowedPorts);
            await CreateAllowRuleAsync(projectId, executablePath, "AllowOutboundAllowedIPs", ipList, ports);
        }
        else if (policy.FailClosed)
        {
            throw new NetworkEnforcementException("Network mode is 'allowlist' but 0 valid destinations were resolved. Fail-closed stopped launch.");
        }
    }

    public async Task RemovePolicyAsync(string projectId)
    {
        if (!IsAdministrator()) return;

        try
        {
            var rulePattern = $"{RulePrefix}{projectId}_*";
            await RunNetshAsync($"advfirewall firewall delete rule name=\"{rulePattern}\"");
        }
        catch (Exception ex)
        {
            logger.LogWarning(projectId, "FirewallCleanup", $"Error removing firewall rules: {ex.Message}");
        }
    }

    public async Task<bool> VerifyEnforcementActiveAsync(string projectId, string executablePath)
    {
        if (!IsAdministrator()) return false;
        var result = await RunNetshAsync($"advfirewall firewall show rule name=\"{RulePrefix}{projectId}_DefaultOutboundBlock\"");
        return result.ExitCode == 0 && result.Output.Contains(executablePath);
    }

    private async Task CreateBlockRuleAsync(string projectId, string exe, string name, string dir)
    {
        var ruleName = $"{RulePrefix}{projectId}_{name}";
        var cmd = $"advfirewall firewall add rule name=\"{ruleName}\" program=\"{exe}\" dir={dir} action=block enable=yes";
        var res = await RunNetshAsync(cmd);
        if (res.ExitCode != 0)
            throw new NetworkEnforcementException($"Failed to create firewall block rule: {res.Error}");
    }

    private async Task CreateAllowRuleAsync(string projectId, string exe, string name, string remoteIp, string remotePort)
    {
        var ruleName = $"{RulePrefix}{projectId}_{name}";
        var portArg = remotePort == "any" ? "" : $"protocol=TCP remoteport={remotePort}";
        var cmd = $"advfirewall firewall add rule name=\"{ruleName}\" program=\"{exe}\" dir=out action=allow remoteip={remoteIp} {portArg} enable=yes";
        var res = await RunNetshAsync(cmd);
        if (res.ExitCode != 0)
            throw new NetworkEnforcementException($"Failed to create firewall allow rule: {res.Error}");
    }

    private static async Task<(int ExitCode, string Output, string Error)> RunNetshAsync(string arguments)
    {
        var psi = new ProcessStartInfo("netsh", arguments)
        {
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        using var proc = SysProcess.Start(psi)
            ?? throw new NetworkEnforcementException("Unable to launch netsh process for network filtering.");
        
        var output = await proc.StandardOutput.ReadToEndAsync();
        var error = await proc.StandardError.ReadToEndAsync();
        await proc.WaitForExitAsync();
        return (proc.ExitCode, output, error);
    }
}
