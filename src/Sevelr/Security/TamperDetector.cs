using System.Security.Cryptography;
using System.Text.Json;
using Sevelr.Core;
using Sevelr.Logging;

namespace Sevelr.Security;

public class TamperDetector(IAuditLogger logger) : ITamperDetector
{
    private record ManifestRecord(Dictionary<string, string> FileHashes, DateTime GeneratedAt);

    public void GenerateIntegrityManifest(string projectDirectory, string manifestPath)
    {
        var hashes = new Dictionary<string, string>();
        var configDir = Path.Combine(projectDirectory, "config");
        
        if (Directory.Exists(configDir))
        {
            using var sha = SHA256.Create();
            foreach (var file in Directory.GetFiles(configDir, "*.*", SearchOption.AllDirectories))
            {
                if (file.Equals(manifestPath, StringComparison.OrdinalIgnoreCase))
                    continue;

                var relative = Path.GetRelativePath(projectDirectory, file);
                using var stream = File.OpenRead(file);
                var hash = Convert.ToHexString(sha.ComputeHash(stream));
                hashes[relative] = hash;
            }
        }

        var record = new ManifestRecord(hashes, DateTime.UtcNow);
        File.WriteAllText(manifestPath, JsonSerializer.Serialize(record, new JsonSerializerOptions { WriteIndented = true }));
        logger.LogSecurityEvent("SYSTEM", "Integrity", manifestPath, "Generate", $"Generated manifest with {hashes.Count} signatures.");
    }

    public bool VerifyIntegrity(string projectDirectory, string manifestPath, bool failClosed)
    {
        if (!File.Exists(manifestPath))
        {
            var msg = $"Integrity manifest missing at '{manifestPath}'";
            logger.LogError("SYSTEM", "Integrity", msg);
            if (failClosed) throw new IntegrityVerificationException(msg);
            return false;
        }

        var json = File.ReadAllText(manifestPath);
        var record = JsonSerializer.Deserialize<ManifestRecord>(json)
            ?? throw new IntegrityVerificationException("Corrupted integrity manifest.");

        using var sha = SHA256.Create();
        foreach (var (relative, expectedHash) in record.FileHashes)
        {
            var fullPath = Path.Combine(projectDirectory, relative);
            if (!File.Exists(fullPath))
            {
                var msg = $"Tamper detected: Missing file '{relative}'";
                logger.LogSecurityEvent("SYSTEM", "Integrity", relative, "TamperDetected", msg);
                if (failClosed) throw new IntegrityVerificationException(msg);
                return false;
            }

            using var stream = File.OpenRead(fullPath);
            var actualHash = Convert.ToHexString(sha.ComputeHash(stream));
            if (!actualHash.Equals(expectedHash, StringComparison.OrdinalIgnoreCase))
            {
                var msg = $"Tamper detected: Hash mismatch on '{relative}'. Expected: {expectedHash}, Actual: {actualHash}";
                logger.LogSecurityEvent("SYSTEM", "Integrity", relative, "TamperDetected", msg);
                if (failClosed) throw new IntegrityVerificationException(msg);
                return false;
            }
        }

        return true;
    }
}
