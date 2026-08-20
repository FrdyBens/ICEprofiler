namespace Sevelr.Security;

public interface ITamperDetector
{
    void GenerateIntegrityManifest(string projectDirectory, string manifestPath);
    bool VerifyIntegrity(string projectDirectory, string manifestPath, bool failClosed);
}
