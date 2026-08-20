using System.Text.Json;
using Sevelr.Applications;
using Sevelr.Browser;
using Sevelr.Commands;
using Sevelr.Configuration;
using Sevelr.Configuration.Models;
using Sevelr.Core;
using Sevelr.Extensions;
using Sevelr.Filesystem;
using Sevelr.Logging;
using Sevelr.Network;
using Sevelr.Policies;
using Sevelr.Process;
using Sevelr.Runtime;
using Sevelr.Security;

namespace Sevelr.Projects;

public class ProjectManager(
    IStorageManager storage,
    IAclManager aclManager,
    IEncryptionProvider efsProvider,
    IPolicyEngine policyEngine,
    IExtensionGenerator extensionGen,
    INetworkEnforcer networkEnforcer,
    IBrowserPolicyManager browserPolicy,
    IProcessManager processManager,
    IRuntimeStateManager runtimeState,
    ITamperDetector tamperDetector,
    ApplicationProviderFactory appFactory,
    IAuditLogger logger) : IProjectManager
{
    public void CreateProject(string projectId, string templateName = "strict", Action<ProjectConfig>? configure = null)
    {
        if (ProjectExists(projectId))
            throw new ConfigurationException($"Project '{projectId}' already exists.");

        var config = TemplateManager.GetTemplate(templateName);
        config.Project.Id = projectId;
        config.Project.DisplayName = projectId;
        configure?.Invoke(config);

        ConfigValidator.ValidateOrThrow(config);

        var paths = storage.InitializeProjectStorage(projectId);
        SaveConfig(config);

        aclManager.RestrictToCurrentUserOnly(paths.BaseDir, failClosed: config.Security.Mode == "strict");
        if (config.Filesystem.Encrypted)
            efsProvider.EncryptDirectory(paths.BaseDir, failClosed: config.Security.Mode == "strict");

        var policy = policyEngine.Compile(config, storage);
        var extDir = Path.Combine(paths.BaseDir, "extension");
        extensionGen.GenerateExtension(policy, extDir);

        var manifestPath = Path.Combine(paths.ConfigDir, "manifest.json");
        tamperDetector.GenerateIntegrityManifest(paths.BaseDir, manifestPath);

        logger.LogSecurityEvent(projectId, "Lifecycle", projectId, "Create", $"Created isolated environment with template '{templateName}'.");
    }

    public async Task LaunchProjectAsync(string projectId, bool temporary = false)
    {
        var config = GetConfig(projectId);
        var paths = storage.GetProjectPaths(projectId);

        using var projLock = new ProjectLock(projectId);
        if (!projLock.TryAcquire())
            throw new ProcessManagementException($"Project '{projectId}' is already running.");

        var manifestPath = Path.Combine(paths.ConfigDir, "manifest.json");
        if (config.Security.TamperDetection)
        {
            tamperDetector.VerifyIntegrity(paths.BaseDir, manifestPath, failClosed: config.Security.Mode == "strict");
        }

        var provider = appFactory.GetProvider(config.Application.Provider);
        var exePath = config.Application.Executable ?? provider.DiscoverExecutablePath();

        // 1. Compile Policy & Regenerate Extension
        var policy = policyEngine.Compile(config, storage);
        var extDir = Path.Combine(paths.BaseDir, "extension");
        extensionGen.GenerateExtension(policy, extDir);

        // 2. Start Socket Enforcement Proxy (Layer 2)
        using var proxy = new LocalEnforcementProxy(policy, logger);
        proxy.Start();

        // 3. Inject Native Chromium Policies into Registry (Layer 1)
        browserPolicy.ApplyPolicy(policy);

        // 4. Apply OS Kernel Firewall Rules (Layer 3)
        await networkEnforcer.ApplyPolicyAsync(policy, exePath);

        // 5. Build arguments with Proxy enforcement
        var psi = provider.BuildProcessStartInfo(exePath, policy, config.Application.InitialUrl);
        psi.ArgumentList.Add($"--proxy-server=http://127.0.0.1:{proxy.Port}");

        OutputFormatter.PrintSecurityDashboard(
            projectId,
            provider.Name,
            config.Security.Mode,
            netEnforced: true,
            efsEncrypted: config.Filesystem.Encrypted,
            aclStrict: true,
            processMonitored: config.Process.Monitor);

        logger.LogSecurityEvent(projectId, "Lifecycle", exePath, "Launch", "Starting isolated process.");

        var proc = processManager.LaunchSupervisedProcess(projectId, psi, policy.Process.MaxMemoryBytes);
        runtimeState.RecordProjectStart(projectId, proc.Id);

        await proc.WaitForExitAsync();

        // Cleanup
        runtimeState.RecordProjectStop(projectId);
        browserPolicy.RemovePolicy(projectId);
        await networkEnforcer.RemovePolicyAsync(projectId);

        if (temporary || config.Privacy.ClearOnExit)
        {
            storage.SecurePurge(paths.BrowserDataDir);
            storage.SecurePurge(paths.TempDir);
            logger.LogSecurityEvent(projectId, "Lifecycle", projectId, "TemporaryClean", "Purged temporary directories.");
        }
    }

    public ProjectConfig GetConfig(string projectId)
    {
        var paths = storage.GetProjectPaths(projectId);
        var cfgFile = Path.Combine(paths.ConfigDir, "project.json");
        if (!File.Exists(cfgFile))
            throw new ConfigurationException($"Project '{projectId}' configuration not found at {cfgFile}.");

        var json = File.ReadAllText(cfgFile);
        return JsonSerializer.Deserialize<ProjectConfig>(json)
            ?? throw new ConfigurationException("Failed deserializing project configuration.");
    }

    public void SaveConfig(ProjectConfig config)
    {
        var paths = storage.GetProjectPaths(config.Project.Id);
        var cfgFile = Path.Combine(paths.ConfigDir, "project.json");
        File.WriteAllText(cfgFile, JsonSerializer.Serialize(config, new JsonSerializerOptions { WriteIndented = true }));
    }

    public bool ProjectExists(string projectId) =>
        Directory.Exists(storage.GetProjectPaths(projectId).BaseDir);
}
