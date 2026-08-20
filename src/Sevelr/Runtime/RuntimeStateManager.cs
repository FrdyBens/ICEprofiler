using System.Text.Json;
using Sevelr.Core;

namespace Sevelr.Runtime;

public class RuntimeStateManager : IRuntimeStateManager
{
    private readonly string _stateFilePath = Path.Combine(Constants.Paths.RuntimeDir, "active_sessions.json");
    private readonly object _lock = new();

    public void RecordProjectStart(string projectId, int processId)
    {
        lock (_lock)
        {
            var sessions = LoadSessions();
            sessions.RemoveAll(s => s.ProjectId.Equals(projectId, StringComparison.OrdinalIgnoreCase));
            sessions.Add(new ProjectRuntimeInfo(projectId, processId, DateTime.UtcNow));
            SaveSessions(sessions);
        }
    }

    public void RecordProjectStop(string projectId)
    {
        lock (_lock)
        {
            var sessions = LoadSessions();
            sessions.RemoveAll(s => s.ProjectId.Equals(projectId, StringComparison.OrdinalIgnoreCase));
            SaveSessions(sessions);
        }
    }

    public ProjectRuntimeInfo? GetRuntimeInfo(string projectId)
    {
        lock (_lock)
        {
            var sessions = LoadSessions();
            return sessions.FirstOrDefault(s => s.ProjectId.Equals(projectId, StringComparison.OrdinalIgnoreCase));
        }
    }

    public List<ProjectRuntimeInfo> GetAllRunningProjects()
    {
        lock (_lock)
        {
            return LoadSessions();
        }
    }

    private List<ProjectRuntimeInfo> LoadSessions()
    {
        if (!File.Exists(_stateFilePath)) return [];
        try
        {
            var json = File.ReadAllText(_stateFilePath);
            return JsonSerializer.Deserialize<List<ProjectRuntimeInfo>>(json) ?? [];
        }
        catch
        {
            return [];
        }
    }

    private void SaveSessions(List<ProjectRuntimeInfo> sessions)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_stateFilePath)!);
        File.WriteAllText(_stateFilePath, JsonSerializer.Serialize(sessions, new JsonSerializerOptions { WriteIndented = true }));
    }
}
