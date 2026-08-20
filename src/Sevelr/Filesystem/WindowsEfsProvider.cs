using System.Runtime.InteropServices;
using Sevelr.Core;
using Sevelr.Logging;

namespace Sevelr.Filesystem;

public class WindowsEfsProvider(IAuditLogger logger) : IEncryptionProvider
{
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern bool EncryptFile(string lpFileName);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern bool FileEncryptionStatus(string lpFileName, out uint lpStatus);

    private const uint FILE_IS_ENCRYPTED = 1;
    private const uint FILE_ENCRYPTABLE = 0;

    public bool EncryptDirectory(string directoryPath, bool failClosed)
    {
        if (!Directory.Exists(directoryPath))
            Directory.CreateDirectory(directoryPath);

        bool success = EncryptFile(directoryPath);
        if (!success)
        {
            int err = Marshal.GetLastWin32Error();
            var msg = $"EFS encryption failed on '{directoryPath}' with Win32 error code {err}.";
            logger.LogError("SYSTEM", "EFS", msg);
            if (failClosed)
                throw new FilesystemIsolationException(msg);
            return false;
        }

        logger.LogSecurityEvent("SYSTEM", "EFS", directoryPath, "Encrypt", "Applied Windows EFS directory encryption.");
        return true;
    }

    public bool IsEncrypted(string directoryPath)
    {
        if (!Directory.Exists(directoryPath)) return false;
        if (FileEncryptionStatus(directoryPath, out uint status))
        {
            return status == FILE_IS_ENCRYPTED;
        }
        return false;
    }
}