using Sevelr.Configuration.Models;

namespace Sevelr.Projects;

public interface IProjectManager
{
    void CreateProject(string projectId, string templateName = "strict", Action<ProjectConfig>? configure = null);
    Task LaunchProjectAsync(string projectId, bool temporary = false);
    ProjectConfig GetConfig(string projectId);
    void SaveConfig(ProjectConfig config);
    bool ProjectExists(string projectId);
}
