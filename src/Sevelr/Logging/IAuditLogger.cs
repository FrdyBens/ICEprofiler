namespace Sevelr.Logging;

public interface IAuditLogger
{
    void LogInfo(string projectId, string component, string message);
    void LogWarning(string projectId, string component, string message);
    void LogError(string projectId, string component, string message);
    void LogSecurityEvent(string projectId, string component, string target, string action, string details);
}
