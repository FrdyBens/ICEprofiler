using System.IO;

namespace Sevelr.Runtime;

public sealed class ProjectLock : IDisposable
{
    private readonly string _lockFilePath;
    private FileStream? _lockStream;

    public ProjectLock(string projectId)
    {
        var runtimeDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Sevelr", "runtime");
        Directory.CreateDirectory(runtimeDir);
        _lockFilePath = Path.Combine(runtimeDir, $"{projectId}.lock");
    }

    public bool TryAcquire()
    {
        try
        {
            _lockStream = new FileStream(_lockFilePath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch
        {
            return false;
        }
    }

    public void Dispose()
    {
        if (_lockStream != null)
        {
            try
            {
                _lockStream.Dispose();
                _lockStream = null;
                if (File.Exists(_lockFilePath))
                {
                    File.Delete(_lockFilePath);
                }
            }
            catch { }
        }
    }
}
