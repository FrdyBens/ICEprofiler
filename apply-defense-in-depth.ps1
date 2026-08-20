$ErrorActionPreference = "Stop"
$Root = (Get-Location).Path

Write-Host "[1/6] Implementing Chromium Enterprise Policy Manager..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $Root "src/Sevelr/Browser/IBrowserPolicyManager.cs") -Value @'
using Sevelr.Policies;

namespace Sevelr.Browser;

public interface IBrowserPolicyManager
{
    void ApplyPolicy(CompiledPolicy policy);
    void RemovePolicy(string projectId);
}
'@

Set-Content -Path (Join-Path $Root "src/Sevelr/Browser/ChromiumPolicyManager.cs") -Value @'
using Microsoft.Win32;
using Sevelr.Logging;
using Sevelr.Policies;

namespace Sevelr.Browser;

public class ChromiumPolicyManager(IAuditLogger logger) : IBrowserPolicyManager
{
    private static readonly string[] PolicyRegistryPaths =
    [
        @"SOFTWARE\Policies\BraveSoftware\Brave",
        @"SOFTWARE\Policies\Chromium",
        @"SOFTWARE\Policies\Google\Chrome"
    ];

    public void ApplyPolicy(CompiledPolicy policy)
    {
        foreach (var regPath in PolicyRegistryPaths)
        {
            try
            {
                using var key = Registry.CurrentUser.CreateSubKey(regPath, true);
                if (key == null) continue;

                // 1. Native Chromium URL Allowlist / Blocklist
                if (policy.Network.Mode == "allowlist")
                {
                    using var blockKey = key.CreateSubKey("URLBlocklist", true);
                    foreach (var valName in blockKey.GetValueNames())
                        blockKey.DeleteValue(valName, false);
                    blockKey.SetValue("1", "*");

                    using var allowKey = key.CreateSubKey("URLAllowlist", true);
                    foreach (var valName in allowKey.GetValueNames())
                        allowKey.DeleteValue(valName, false);

                    int idx = 1;
                    foreach (var d in policy.Network.ExactDomains)
                    {
                        allowKey.SetValue((idx++).ToString(), $"https://{d}");
                        allowKey.SetValue((idx++).ToString(), $"https://{d}/*");
                        allowKey.SetValue((idx++).ToString(), $"http://{d}");
                        allowKey.SetValue((idx++).ToString(), $"http://{d}/*");
                    }
                    foreach (var w in policy.Network.WildcardDomains)
                    {
                        allowKey.SetValue((idx++).ToString(), $"https://*.{w}");
                        allowKey.SetValue((idx++).ToString(), $"https://*.{w}/*");
                        allowKey.SetValue((idx++).ToString(), $"http://*.{w}");
                        allowKey.SetValue((idx++).ToString(), $"http://*.{w}/*");
                    }
                }

                // 2. Lock Developer Tools
                if (policy.Browser.DisableDevTools)
                {
                    key.SetValue("DeveloperToolsAvailability", 2, RegistryValueKind.DWord);
                }

                // 3. Privacy
                key.SetValue("PasswordManagerEnabled", 0, RegistryValueKind.DWord);
                key.SetValue("SyncDisabled", 1, RegistryValueKind.DWord);
                key.SetValue("MetricsReportingEnabled", 0, RegistryValueKind.DWord);

                logger.LogSecurityEvent(policy.ProjectId, "BrowserPolicy", regPath, "Apply", "Injected native enterprise URL policies.");
            }
            catch (Exception ex)
            {
                logger.LogWarning(policy.ProjectId, "BrowserPolicy", $"Failed applying registry policy to {regPath}: {ex.Message}");
            }
        }
    }

    public void RemovePolicy(string projectId)
    {
        foreach (var regPath in PolicyRegistryPaths)
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(regPath, true);
                if (key != null)
                {
                    key.DeleteSubKeyTree("URLBlocklist", false);
                    key.DeleteSubKeyTree("URLAllowlist", false);
                    key.DeleteValue("DeveloperToolsAvailability", false);
                    key.DeleteValue("PasswordManagerEnabled", false);
                    key.DeleteValue("SyncDisabled", false);
                    key.DeleteValue("MetricsReportingEnabled", false);
                }
            }
            catch { }
        }
    }
}
'@

Write-Host "[2/6] Implementing Local Enforcement Socket Proxy..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $Root "src/Sevelr/Network/LocalEnforcementProxy.cs") -Value @'
using System.Net;
using System.Net.Sockets;
using System.Text;
using Sevelr.Logging;
using Sevelr.Policies;

namespace Sevelr.Network;

public sealed class LocalEnforcementProxy : IDisposable
{
    private readonly CompiledPolicy _policy;
    private readonly IAuditLogger _logger;
    private readonly TcpListener _listener;
    private readonly CancellationTokenSource _cts = new();
    public int Port { get; }

    public LocalEnforcementProxy(CompiledPolicy policy, IAuditLogger logger)
    {
        _policy = policy;
        _logger = logger;
        _listener = new TcpListener(IPAddress.Loopback, 0);
        _listener.Start();
        Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
    }

    public void Start()
    {
        Task.Run(async () =>
        {
            while (!_cts.Token.IsCancellationRequested)
            {
                try
                {
                    var client = await _listener.AcceptTcpClientAsync(_cts.Token);
                    _ = Task.Run(() => HandleClientAsync(client, _cts.Token));
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(_policy.ProjectId, "Proxy", $"Listener error: {ex.Message}");
                }
            }
        });
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken ct)
    {
        using (client)
        using (var clientStream = client.GetStream())
        {
            try
            {
                var buffer = new byte[8192];
                int read = await clientStream.ReadAsync(buffer, ct);
                if (read == 0) return;

                var request = Encoding.ASCII.GetString(buffer, 0, read);
                var lines = request.Split("\r\n");
                if (lines.Length == 0) return;

                var firstLine = lines[0].Split(' ');
                if (firstLine.Length < 2) return;

                var method = firstLine[0];
                var target = firstLine[1];

                string host;
                int port = 80;

                if (method.Equals("CONNECT", StringComparison.OrdinalIgnoreCase))
                {
                    var parts = target.Split(':');
                    host = parts[0];
                    if (parts.Length > 1 && int.TryParse(parts[1], out var p))
                        port = p;
                    else
                        port = 443;
                }
                else
                {
                    if (Uri.TryCreate(target, UriKind.Absolute, out var uri))
                    {
                        host = uri.Host;
                        port = uri.Port;
                    }
                    else
                    {
                        var parts = target.Split(':');
                        host = parts[0];
                    }
                }

                if (!IsHostAllowed(host))
                {
                    _logger.LogSecurityEvent(_policy.ProjectId, "ProxyFilter", host, "Drop", "Blocked unauthorized destination at socket proxy level.");
                    var blockedResponse = "HTTP/1.1 403 Forbidden\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n<h1>403 Forbidden - Blocked by Sevelr Security Policy</h1>";
                    var respBytes = Encoding.UTF8.GetBytes(blockedResponse);
                    await clientStream.WriteAsync(respBytes, ct);
                    return;
                }

                // Forward connection
                using var remoteClient = new TcpClient();
                await remoteClient.ConnectAsync(host, port, ct);
                using var remoteStream = remoteClient.GetStream();

                if (method.Equals("CONNECT", StringComparison.OrdinalIgnoreCase))
                {
                    var okResponse = Encoding.ASCII.GetBytes("HTTP/1.1 200 Connection Established\r\n\r\n");
                    await clientStream.WriteAsync(okResponse, ct);
                }
                else
                {
                    await remoteStream.WriteAsync(buffer.AsMemory(0, read), ct);
                }

                var clientToRemote = clientStream.CopyToAsync(remoteStream, ct);
                var remoteToClient = remoteStream.CopyToAsync(clientStream, ct);
                await Task.WhenAny(clientToRemote, remoteToClient);
            }
            catch { }
        }
    }

    private bool IsHostAllowed(string host)
    {
        host = host.Trim().ToLowerInvariant();
        if (host == "127.0.0.1" || host == "localhost") return true;

        if (_policy.Network.ExactDomains.Contains(host))
            return true;

        foreach (var wildcard in _policy.Network.WildcardDomains)
        {
            if (host.EndsWith("." + wildcard) || host == wildcard)
                return true;
        }

        return false;
    }

    public void Dispose()
    {
        _cts.Cancel();
        _listener.Stop();
    }
}
'@

Write-Host "[3/6] Updating ProjectManager.cs with Multi-Layer Enforcements..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $Root "src/Sevelr/Projects/ProjectManager.cs") -Value @'
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
'@

Write-Host "[4/6] Updating Program.cs wiring..." -ForegroundColor Cyan
Set-Content -Path (Join-Path $Root "src/Sevelr/Program.cs") -Value @'
using Sevelr.Applications;
using Sevelr.Browser;
using Sevelr.Commands;
using Sevelr.Core;
using Sevelr.Diagnostics;
using Sevelr.Extensions;
using Sevelr.Filesystem;
using Sevelr.Logging;
using Sevelr.Network;
using Sevelr.Policies;
using Sevelr.Process;
using Sevelr.Projects;
using Sevelr.Runtime;
using Sevelr.Security;

namespace Sevelr;

public static class Program
{
    public static async Task<int> Main(string[] args)
    {
        OutputFormatter.PrintBanner();

        var parsed = CommandLineParser.Parse(args);
        if (string.IsNullOrEmpty(parsed.Command) || parsed.Flags.Contains("help"))
        {
            PrintUsage();
            return Constants.ExitCodes.Success;
        }

        var logger = new AuditLogger();
        var storage = new StorageManager();
        var aclManager = new WindowsAclManager(logger);
        var efsProvider = new WindowsEfsProvider(logger);
        var policyEngine = new PolicyCompiler();
        var extensionGen = new Mv3ExtensionGenerator();
        var networkEnforcer = new WindowsFirewallEnforcer(logger);
        var browserPolicy = new ChromiumPolicyManager(logger);
        var processManager = new WindowsProcessManager(logger);
        var runtimeState = new RuntimeStateManager();
        var tamperDetector = new TamperDetector(logger);

        var appFactory = new ApplicationProviderFactory();
        appFactory.RegisterProvider(new BraveApplicationProvider());
        appFactory.RegisterProvider(new CustomExecutableProvider());

        var projectManager = new ProjectManager(
            storage, aclManager, efsProvider, policyEngine,
            extensionGen, networkEnforcer, browserPolicy, processManager,
            runtimeState, tamperDetector, appFactory, logger);

        var doctorService = new DoctorService(projectManager, storage, aclManager, efsProvider, tamperDetector, appFactory);

        try
        {
            switch (parsed.Command)
            {
                case "create":
                    var template = parsed.Options.GetValueOrDefault("template", "strict");
                    projectManager.CreateProject(parsed.Target ?? throw new ConfigurationException("Project name is required."), template);
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine($"[✓] Project '{parsed.Target}' created successfully using template '{template}'.");
                    Console.ResetColor();
                    break;

                case "launch":
                    await projectManager.LaunchProjectAsync(
                        parsed.Target ?? "default",
                        temporary: parsed.Flags.Contains("temporary"));
                    break;

                case "doctor":
                    var results = await doctorService.RunDiagnosticsAsync(parsed.Target ?? throw new ConfigurationException("Project name is required."));
                    bool allPass = true;
                    Console.WriteLine($"Diagnostics for '{parsed.Target}':\n");
                    foreach (var r in results)
                    {
                        Console.ForegroundColor = r.Passed ? ConsoleColor.Green : ConsoleColor.Red;
                        Console.WriteLine($" [{(r.Passed ? "PASS" : "FAIL")}] {r.Component}: {r.Details}");
                        if (!r.Passed && r.Remediation != null)
                            Console.WriteLine($"        Action: {r.Remediation}");
                        if (!r.Passed) allPass = false;
                    }
                    Console.ResetColor();
                    return allPass ? Constants.ExitCodes.Success : Constants.ExitCodes.DoctorCheckFailed;

                case "version":
                    Console.WriteLine($"Sevelr Universal Application Isolation Engine v{Constants.PlatformVersion}");
                    break;

                default:
                    Console.ForegroundColor = ConsoleColor.Yellow;
                    Console.WriteLine($"Unknown command '{parsed.Command}'. Use --help for usage.");
                    Console.ResetColor();
                    return Constants.ExitCodes.GenericFailure;
            }

            return Constants.ExitCodes.Success;
        }
        catch (SevelrException sex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"\n[SECURITY ERROR] ({sex.GetType().Name}): {sex.Message}");
            Console.ResetColor();
            return sex.ExitCode;
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"\n[FATAL ERROR]: {ex.Message}");
            Console.ResetColor();
            return Constants.ExitCodes.GenericFailure;
        }
    }

    private static void PrintUsage()
    {
        Console.WriteLine(@"
Usage: sevelr <command> [target] [options]

Commands:
  create <project>    Initialize an isolated project environment
  launch <project>    Run an application inside an enforced sandbox
  doctor <project>    Perform end-to-end security diagnostics
  version             Print version information

Options:
  --template <name>   Template: strict, balanced, development, research, temporary
  --temporary         Purge isolated storage upon termination
");
    }
}
'@

Write-Host "[5/6] Compiling single-file binary..." -ForegroundColor Cyan
$PublishDir = Join-Path $Root "dist"
if (Test-Path $PublishDir) { Remove-Item -Recurse -Force $PublishDir }

$publishArgs = @(
    "publish",
    (Join-Path $Root "src/Sevelr/Sevelr.csproj"),
    "-c", "Release",
    "-r", "win-x64",
    "--self-contained", "true",
    "-p:PublishSingleFile=true",
    "-p:IncludeNativeLibrariesForSelfExtract=true",
    "-o", (Join-Path $PublishDir "bin")
)
& dotnet @publishArgs

Write-Host "[6/6] Updating binaries in PATH..." -ForegroundColor Cyan
$InstallBin = "$env:LOCALAPPDATA\Programs\Sevelr\bin"
if (Test-Path $InstallBin) {
    Copy-Item (Join-Path $PublishDir "bin\sevelr.exe") $InstallBin -Force
}

$ZipPath = Join-Path $Root "sevelr-v2.0.0-win-x64.zip"
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
Compress-Archive -Path "$PublishDir\*" -DestinationPath $ZipPath

Write-Host "`n[✓] Defense-in-depth enforcements compiled and deployed!" -ForegroundColor Green