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
