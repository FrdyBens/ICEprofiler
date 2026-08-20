using System.Diagnostics;
using Sevelr.Core;
using Sevelr.Policies;

namespace Sevelr.Applications;

public class CustomExecutableProvider : IApplicationProvider
{
    public string Name => "custom";

    public string DiscoverExecutablePath()
    {
        throw new ConfigurationException("Custom provider requires an explicit executable path in configuration.");
    }

    public ProcessStartInfo BuildProcessStartInfo(string executablePath, CompiledPolicy policy, string targetUrl)
    {
        var psi = new ProcessStartInfo(executablePath)
        {
            UseShellExecute = false,
            WorkingDirectory = Path.GetDirectoryName(executablePath)
        };

        foreach (var arg in policy.Browser.UserArguments)
            psi.ArgumentList.Add(arg);

        if (!string.IsNullOrWhiteSpace(targetUrl) && targetUrl != "about:blank")
            psi.ArgumentList.Add(targetUrl);

        return psi;
    }
}
