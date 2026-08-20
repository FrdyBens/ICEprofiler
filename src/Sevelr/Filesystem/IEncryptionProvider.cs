namespace Sevelr.Filesystem;

public interface IEncryptionProvider
{
    bool EncryptDirectory(string directoryPath, bool failClosed);
    bool IsEncrypted(string directoryPath);
}
