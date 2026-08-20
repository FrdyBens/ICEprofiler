using System.Diagnostics;
using Sevelr.Core;
using Sevelr.Logging;

namespace Sevelr.Process;

public class WindowsProcessManager(IAuditLogger logger) : IProcessManager
{
    private readonly Dictionary<string, WindowsJobObject> _activeJobs = [];

    public System.Diagnostics.Process LaunchSupervisedProcess(string projectId, ProcessStartInfo startInfo, long maxMemoryBytes)
    {
        var job = new WindowsJobObject($"Sevelr_Job_{projectId}", maxMemoryBytes);
        _activeJobs[projectId] = job;

        var proc = System.Diagnostics.Process.Start(startInfo)
            ?? throw new ProcessManagementException($"Failed to spawn target application for project '{projectId}'.");

        try
        {
            job.AssignProcess(proc);
            logger.LogSecurityEvent(projectId, "ProcessManager", startInfo.FileName, "Supervise", $"Attached PID {proc.Id} to Windows Job Object.");
        }
        catch (Exception ex)
        {
            logger.LogError(projectId, "ProcessManager", $"Failed to attach process to job object: {ex.Message}");
            proc.Kill(entireProcessTree: true);
            throw;
        }

        return proc;
    }

    public void TerminateProjectProcesses(string projectId)
    {
        if (_activeJobs.TryGetValue(projectId, out var job))
        {
            job.Dispose();
            _activeJobs.Remove(projectId);
            logger.LogSecurityEvent(projectId, "ProcessManager", projectId, "Terminate", "Terminated all processes in project Job Object.");
        }
    }
}
