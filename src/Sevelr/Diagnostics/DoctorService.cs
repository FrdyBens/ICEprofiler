using Sevelr.Applications;
using Sevelr.Configuration.Models;
using Sevelr.Core;
using Sevelr.Filesystem;
using Sevelr.Projects;
using Sevelr.Security;

namespace Sevelr.Diagnostics;

public record DiagnosticCheckResult(string Component, bool Passed, string Details, string? Remediation = null);

public class DoctorService(
    IProjectManager projectManager,
    IStorageManager storageManager,
    IAclManager aclManager,
    IEncryptionProvider encryptionProvider,
    ITamperDetector tamperDetector,
    ApplicationProviderFactory appFactory) : IDoctorService
{
    public Task<List<DiagnosticCheckResult>> RunDiagnosticsAsync(string projectId)
    {
        var results = new List<DiagnosticCheckResult>();

        // 1. Config Check
        ProjectConfig? config = null;
        try
        {
            config = projectManager.GetConfig(projectId);
            results.Add(new("Configuration", true, "Project configuration schema is valid."));
        }
        catch (Exception ex)
        {
            results.Add(new("Configuration", false, $"Config invalid: {ex.Message}", "Run 'sevelr repair <project>' or check syntax."));
            return Task.FromResult(results);
        }

        var paths = storageManager.GetProjectPaths(projectId);

        // 2. Storage Directory Check
        results.Add(Directory.Exists(paths.BaseDir)
            ? new("Filesystem", true, $"Storage root exists at {paths.BaseDir}")
            : new("Filesystem", false, "Storage root directory is missing.", "Run 'sevelr repair <project>'"));

        // 3. NTFS ACL Check
        bool aclOk = aclManager.VerifyAccessControl(paths.BaseDir);
        results.Add(aclOk
            ? new("NTFS_ACL", true, "Directory permissions properly isolated to current user.")
            : new("NTFS_ACL", false, "Permissions are inherited or accessible by other principals.", "Run 'sevelr repair <project>'"));

        // 4. EFS Encryption Check
        if (config.Filesystem.Encrypted)
        {
            bool encOk = encryptionProvider.IsEncrypted(paths.BaseDir);
            results.Add(encOk
                ? new("EFS_Encryption", true, "EFS folder encryption is active.")
                : new("EFS_Encryption", false, "Directory is not encrypted.", "Enable EFS or run 'sevelr repair <project>'"));
        }

        // 5. Executable Discovery Check
        try
        {
            var provider = appFactory.GetProvider(config.Application.Provider);
            var exe = config.Application.Executable ?? provider.DiscoverExecutablePath();
            results.Add(File.Exists(exe)
                ? new("ApplicationExecutable", true, $"Executable verified: {exe}")
                : new("ApplicationExecutable", false, $"File not found: {exe}", "Install application or configure correct path."));
        }
        catch (Exception ex)
        {
            results.Add(new("ApplicationExecutable", false, ex.Message, "Verify provider configuration."));
        }

        // 6. Integrity / Tamper Check
        var manifestPath = Path.Combine(paths.ConfigDir, "manifest.json");
        bool integrityOk = tamperDetector.VerifyIntegrity(paths.BaseDir, manifestPath, failClosed: false);
        results.Add(integrityOk
            ? new("Integrity", true, "All signed project files match valid checksums.")
            : new("Integrity", false, "Checksum mismatch or modified files detected!", "Run 'sevelr repair <project>' to re-generate manifest."));

        return Task.FromResult(results);
    }
}
