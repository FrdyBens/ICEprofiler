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
