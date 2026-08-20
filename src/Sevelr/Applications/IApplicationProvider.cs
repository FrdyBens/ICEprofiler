using System.Diagnostics;
using Sevelr.Policies;

namespace Sevelr.Applications;

public interface IApplicationProvider
{
    string Name { get; }
    string DiscoverExecutablePath();
    ProcessStartInfo BuildProcessStartInfo(string executablePath, CompiledPolicy policy, string targetUrl);
}
