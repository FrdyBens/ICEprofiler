namespace Sevelr.Filesystem;

public interface IAclManager
{
    void RestrictToCurrentUserOnly(string directoryPath, bool failClosed);
    bool VerifyAccessControl(string directoryPath);
}
