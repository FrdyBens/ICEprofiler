# ---

# ## 2. Automated Generator & Fix Script

# Create and execute this script inside `F:\M\Documents\brave builder`:

### `setup-all.ps1`
# ```powershell
#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Get-Location }

Write-Host "Creating directory structure..." -ForegroundColor Cyan
$dirs = @(
    "src/Sevelr/Core",
    "src/Sevelr/Configuration/Models",
    "src/Sevelr/Policies",
    "src/Sevelr/Applications",
    "src/Sevelr/Browser",
    "src/Sevelr/Network",
    "src/Sevelr/DNS",
    "src/Sevelr/Filesystem",
    "src/Sevelr/Process",
    "src/Sevelr/Security",
    "src/Sevelr/Extensions",
    "src/Sevelr/Logging",
    "src/Sevelr/Runtime",
    "src/Sevelr/Projects",
    "src/Sevelr/Diagnostics",
    "src/Sevelr/Commands",
    "templates",
    "docs",
    "scripts"
)

foreach ($d in $dirs) {
    $p = Join-Path $Root $d
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

# Ensure README exists
$readmePath = Join-Path $Root "README.md"
if (-not (Test-Path $readmePath)) {
    Set-Content -Path $readmePath -Value "# Sevelr`nUniversal Windows Application Isolation Platform."
}

Write-Host "Writing source files..." -ForegroundColor Cyan

# 1. Logging Interfaces & Implementations
Set-Content -Path (Join-Path $Root "src/Sevelr/Logging/IAuditLogger.cs") -Value @'
namespace Sevelr.Logging;

public interface IAuditLogger
{
    void LogInfo(string projectId, string component, string message);
    void LogWarning(string projectId, string component, string message);
    void LogError(string projectId, string component, string message);
    void LogSecurityEvent(string projectId, string component, string target, string action, string details);
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Logging/LogModels.cs") -Value @'
using System.Text.Json.Serialization;

namespace Sevelr.Logging;

public class SecurityAuditEvent
{
    [JsonPropertyName("timestamp")]
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;

    [JsonPropertyName("projectId")]
    public string ProjectId { get; set; } = string.Empty;

    [JsonPropertyName("pid")]
    public int ProcessId { get; set; } = Environment.ProcessId;

    [JsonPropertyName("component")]
    public string Component { get; set; } = string.Empty;

    [JsonPropertyName("target")]
    public string Target { get; set; } = string.Empty;

    [JsonPropertyName("action")]
    public string Action { get; set; } = string.Empty;

    [JsonPropertyName("details")]
    public string Details { get; set; } = string.Empty;
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Logging/AuditLogger.cs") -Value @'
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
'@

# 2. Filesystem Interfaces & Storage
Set-Content -Path (Join-Path $Root "src/Sevelr/Filesystem/IAclManager.cs") -Value @'
namespace Sevelr.Filesystem;

public interface IAclManager
{
    void RestrictToCurrentUserOnly(string directoryPath, bool failClosed);
    bool VerifyAccessControl(string directoryPath);
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Filesystem/IEncryptionProvider.cs") -Value @'
namespace Sevelr.Filesystem;

public interface IEncryptionProvider
{
    bool EncryptDirectory(string directoryPath, bool failClosed);
    bool IsEncrypted(string directoryPath);
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Filesystem/IStorageManager.cs") -Value @'
namespace Sevelr.Filesystem;

public record ProjectStoragePaths(
    string BaseDir,
    string ConfigDir,
    string BrowserDataDir,
    string DownloadsDir,
    string TempDir,
    string LogsDir
);

public interface IStorageManager
{
    ProjectStoragePaths InitializeProjectStorage(string projectId);
    ProjectStoragePaths GetProjectPaths(string projectId);
    void SecurePurge(string path);
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Filesystem/StorageManager.cs") -Value @'
using Sevelr.Core;

namespace Sevelr.Filesystem;

public class StorageManager : IStorageManager
{
    public StorageManager()
    {
        Directory.CreateDirectory(Constants.Paths.AppDataRoot);
        Directory.CreateDirectory(Constants.Paths.ProjectsDir);
        Directory.CreateDirectory(Constants.Paths.LogsDir);
        Directory.CreateDirectory(Constants.Paths.RuntimeDir);
        Directory.CreateDirectory(Constants.Paths.CacheDir);
    }

    public ProjectStoragePaths InitializeProjectStorage(string projectId)
    {
        var paths = GetProjectPaths(projectId);
        Directory.CreateDirectory(paths.BaseDir);
        Directory.CreateDirectory(paths.ConfigDir);
        Directory.CreateDirectory(paths.BrowserDataDir);
        Directory.CreateDirectory(paths.DownloadsDir);
        Directory.CreateDirectory(paths.TempDir);
        Directory.CreateDirectory(paths.LogsDir);
        return paths;
    }

    public ProjectStoragePaths GetProjectPaths(string projectId)
    {
        var baseDir = Path.Combine(Constants.Paths.ProjectsDir, projectId);
        return new ProjectStoragePaths(
            BaseDir: baseDir,
            ConfigDir: Path.Combine(baseDir, "config"),
            BrowserDataDir: Path.Combine(baseDir, "browser"),
            DownloadsDir: Path.Combine(baseDir, "downloads"),
            TempDir: Path.Combine(baseDir, "temp"),
            LogsDir: Path.Combine(baseDir, "logs")
        );
    }

    public void SecurePurge(string path)
    {
        if (!Directory.Exists(path)) return;
        try
        {
            var dir = new DirectoryInfo(path);
            foreach (var file in dir.GetFiles("*", SearchOption.AllDirectories))
            {
                try
                {
                    file.Attributes = FileAttributes.Normal;
                    file.Delete();
                }
                catch { }
            }
            Directory.Delete(path, true);
        }
        catch { }
    }
}
'@

# 3. Application Interfaces & Providers
Set-Content -Path (Join-Path $Root "src/Sevelr/Applications/IApplicationProvider.cs") -Value @'
using System.Diagnostics;
using Sevelr.Policies;

namespace Sevelr.Applications;

public interface IApplicationProvider
{
    string Name { get; }
    string DiscoverExecutablePath();
    ProcessStartInfo BuildProcessStartInfo(string executablePath, CompiledPolicy policy, string targetUrl);
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Applications/ApplicationProviderFactory.cs") -Value @'
using Sevelr.Core;

namespace Sevelr.Applications;

public class ApplicationProviderFactory
{
    private readonly Dictionary<string, IApplicationProvider> _providers = new(StringComparer.OrdinalIgnoreCase);

    public void RegisterProvider(IApplicationProvider provider)
    {
        _providers[provider.Name] = provider;
    }

    public IApplicationProvider GetProvider(string name)
    {
        if (_providers.TryGetValue(name, out var provider))
            return provider;

        throw new ConfigurationException($"Unsupported application provider '{name}'. Available: {string.Join(", ", _providers.Keys)}");
    }
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Applications/CustomExecutableProvider.cs") -Value @'
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
'@

# 4. Policy, Network, Security & Extension Interfaces
Set-Content -Path (Join-Path $Root "src/Sevelr/Policies/IPolicyEngine.cs") -Value @'
using Sevelr.Configuration.Models;
using Sevelr.Filesystem;

namespace Sevelr.Policies;

public interface IPolicyEngine
{
    CompiledPolicy Compile(ProjectConfig config, IStorageManager storage);
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Network/INetworkEnforcer.cs") -Value @'
using Sevelr.Policies;

namespace Sevelr.Network;

public interface INetworkEnforcer
{
    Task ApplyPolicyAsync(CompiledPolicy policy, string executablePath);
    Task RemovePolicyAsync(string projectId);
    Task<bool> VerifyEnforcementActiveAsync(string projectId, string executablePath);
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Security/ITamperDetector.cs") -Value @'
namespace Sevelr.Security;

public interface ITamperDetector
{
    void GenerateIntegrityManifest(string projectDirectory, string manifestPath);
    bool VerifyIntegrity(string projectDirectory, string manifestPath, bool failClosed);
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Extensions/IExtensionGenerator.cs") -Value @'
using Sevelr.Policies;

namespace Sevelr.Extensions;

public interface IExtensionGenerator
{
    void GenerateExtension(CompiledPolicy policy, string outputDirectory);
}
'@

# 5. Process & Runtime Management
Set-Content -Path (Join-Path $Root "src/Sevelr/Process/IProcessManager.cs") -Value @'
using System.Diagnostics;

namespace Sevelr.Process;

public interface IProcessManager
{
    System.Diagnostics.Process LaunchSupervisedProcess(string projectId, ProcessStartInfo startInfo, long maxMemoryBytes);
    void TerminateProjectProcesses(string projectId);
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Process/WindowsProcessManager.cs") -Value @'
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
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Runtime/IRuntimeStateManager.cs") -Value @'
namespace Sevelr.Runtime;

public record ProjectRuntimeInfo(string ProjectId, int ProcessId, DateTime StartedAt);

public interface IRuntimeStateManager
{
    void RecordProjectStart(string projectId, int processId);
    void RecordProjectStop(string projectId);
    ProjectRuntimeInfo? GetRuntimeInfo(string projectId);
    List<ProjectRuntimeInfo> GetAllRunningProjects();
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Runtime/RuntimeStateManager.cs") -Value @'
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
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Runtime/ProjectLock.cs") -Value @'
namespace Sevelr.Runtime;

public sealed class ProjectLock : IDisposable
{
    private readonly Mutex _mutex;
    private bool _acquired;

    public ProjectLock(string projectId)
    {
        _mutex = new Mutex(false, $@"Global\Sevelr_Project_{projectId}");
    }

    public bool TryAcquire()
    {
        try
        {
            _acquired = _mutex.WaitOne(TimeSpan.FromSeconds(1));
            return _acquired;
        }
        catch (AbandonedMutexException)
        {
            _acquired = true;
            return true;
        }
    }

    public void Dispose()
    {
        if (_acquired)
        {
            _mutex.ReleaseMutex();
            _acquired = false;
        }
        _mutex.Dispose();
    }
}
'@

# 6. Projects & Diagnostics Interfaces
Set-Content -Path (Join-Path $Root "src/Sevelr/Projects/IProjectManager.cs") -Value @'
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
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Projects/TemplateManager.cs") -Value @'
using System.Text.Json;
using Sevelr.Configuration.Models;
using Sevelr.Core;

namespace Sevelr.Projects;

public static class TemplateManager
{
    public static ProjectConfig GetTemplate(string templateName)
    {
        var templateFile = Path.Combine(AppContext.BaseDirectory, "templates", $"{templateName.ToLowerInvariant()}.json");
        if (File.Exists(templateFile))
        {
            var json = File.ReadAllText(templateFile);
            return JsonSerializer.Deserialize<ProjectConfig>(json) ?? CreateDefaultStrictConfig();
        }

        return templateName.ToLowerInvariant() switch
        {
            "balanced" => CreateDefaultBalancedConfig(),
            "temporary" => CreateDefaultTemporaryConfig(),
            _ => CreateDefaultStrictConfig()
        };
    }

    public static ProjectConfig CreateDefaultStrictConfig() => new()
    {
        Project = new() { Template = "strict" },
        Application = new() { Provider = "brave" },
        Network = new() { Mode = "allowlist", AllowHttp = false, AllowHttps = true },
        Filesystem = new() { Encrypted = true },
        Process = new() { Monitor = true, SingleInstancePerProject = true },
        Security = new() { Mode = "strict", FailClosed = true, TamperDetection = true }
    };

    public static ProjectConfig CreateDefaultBalancedConfig() => new()
    {
        Project = new() { Template = "balanced" },
        Application = new() { Provider = "brave" },
        Network = new() { Mode = "allowlist", AllowHttp = true, AllowHttps = true },
        Filesystem = new() { Encrypted = false },
        Process = new() { Monitor = true, SingleInstancePerProject = true },
        Security = new() { Mode = "balanced", FailClosed = false, TamperDetection = false }
    };

    public static ProjectConfig CreateDefaultTemporaryConfig() => new()
    {
        Project = new() { Template = "temporary" },
        Application = new() { Provider = "brave" },
        Network = new() { Mode = "allowlist", AllowHttp = true, AllowHttps = true },
        Filesystem = new() { Encrypted = true, TemporaryFiles = "isolated" },
        Privacy = new() { ClearOnExit = true },
        Security = new() { Mode = "strict", FailClosed = true }
    };
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Diagnostics/IDoctorService.cs") -Value @'
namespace Sevelr.Diagnostics;

public interface IDoctorService
{
    Task<List<DiagnosticCheckResult>> RunDiagnosticsAsync(string projectId);
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Core/Exceptions.cs") -Value @'
namespace Sevelr.Core;

public abstract class SevelrException : Exception
{
    public abstract int ExitCode { get; }
    protected SevelrException(string message) : base(message) { }
    protected SevelrException(string message, Exception inner) : base(message, inner) { }
}

public class ConfigurationException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.ConfigurationError;
}

public class PolicyException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.PolicyError;
}

public class SecurityViolationException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.SecurityError;
}

public class NetworkEnforcementException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.NetworkError;
}

public class FilesystemIsolationException(string message, Exception? inner = null) : SevelrException(message, inner!)
{
    public override int ExitCode => Constants.ExitCodes.FilesystemError;
}

public class ProcessManagementException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.ProcessError;
}

public class IntegrityVerificationException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.IntegrityError;
}

public class BrowserManagementException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.BrowserError;
}
'@

Write-Host "[✓] All source files generated." -ForegroundColor Green
Write-Host "[*] Executing package.ps1 to build and zip..." -ForegroundColor Cyan

& "$Root/scripts/package.ps1"