namespace Sevelr.Runtime;

public record ProjectRuntimeInfo(string ProjectId, int ProcessId, DateTime StartedAt);

public interface IRuntimeStateManager
{
    void RecordProjectStart(string projectId, int processId);
    void RecordProjectStop(string projectId);
    ProjectRuntimeInfo? GetRuntimeInfo(string projectId);
    List<ProjectRuntimeInfo> GetAllRunningProjects();
}
