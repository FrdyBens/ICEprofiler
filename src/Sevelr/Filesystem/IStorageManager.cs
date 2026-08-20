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
