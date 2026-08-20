using System.Text.Json;
using Sevelr.Core;

namespace Sevelr.Logging;

public class AuditLogger : IAuditLogger
{
    private static readonly object _lock = new();

    public AuditLogger()
    {
        Directory.CreateDirectory(Constants.Paths.LogsDir);
    }

    public void LogInfo(string projectId, string component, string message) =>
        WriteLog("INFO", projectId, component, message);

    public void LogWarning(string projectId, string component, string message) =>
        WriteLog("WARN", projectId, component, message);

    public void LogError(string projectId, string component, string message) =>
        WriteLog("ERROR", projectId, component, message);

    public void LogSecurityEvent(string projectId, string component, string target, string action, string details)
    {
        var evt = new SecurityAuditEvent
        {
            ProjectId = projectId,
            Component = component,
            Target = target,
            Action = action,
            Details = details
        };

        var jsonLine = JsonSerializer.Serialize(evt);
        lock (_lock)
        {
            File.AppendAllText(Path.Combine(Constants.Paths.LogsDir, "security.jsonl"), jsonLine + Environment.NewLine);
        }
        WriteLog("SECURITY", projectId, component, $"[{action}] {target} - {details}");
    }

    private void WriteLog(string level, string projectId, string component, string message)
    {
        var line = $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss.fff}] [{level}] [{projectId}] [{component}] {message}";
        lock (_lock)
        {
            try
            {
                File.AppendAllText(Path.Combine(Constants.Paths.LogsDir, "sevelr.log"), line + Environment.NewLine);
            }
            catch { }
        }
    }
}
