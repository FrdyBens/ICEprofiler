using System.Diagnostics;

namespace Sevelr.Process;

public interface IProcessManager
{
    System.Diagnostics.Process LaunchSupervisedProcess(string projectId, ProcessStartInfo startInfo, long maxMemoryBytes);
    void TerminateProjectProcesses(string projectId);
}
