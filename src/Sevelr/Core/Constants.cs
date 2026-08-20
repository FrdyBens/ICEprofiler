namespace Sevelr.Core;

public static class Constants
{
    public const string PlatformName = "Sevelr";
    public const string PlatformVersion = "2.0.0";
    public const int CurrentSchemaVersion = 2;

    public static class Paths
    {
        public static readonly string AppDataRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), PlatformName);
        public static readonly string ConfigDir = Path.Combine(AppDataRoot, "config");
        public static readonly string ProjectsDir = Path.Combine(AppDataRoot, "projects");
        public static readonly string ProfilesDir = Path.Combine(AppDataRoot, "profiles");
        public static readonly string PoliciesDir = Path.Combine(AppDataRoot, "policies");
        public static readonly string LogsDir = Path.Combine(AppDataRoot, "logs");
        public static readonly string RuntimeDir = Path.Combine(AppDataRoot, "runtime");
        public static readonly string CacheDir = Path.Combine(AppDataRoot, "cache");
        public static readonly string TemplatesDir = Path.Combine(AppDataRoot, "templates");
    }

    public static class ExitCodes
    {
        public const int Success = 0;
        public const int GenericFailure = 1;
        public const int ConfigurationError = 2;
        public const int PolicyError = 3;
        public const int SecurityError = 4;
        public const int NetworkError = 5;
        public const int FilesystemError = 6;
        public const int ProcessError = 7;
        public const int BrowserError = 8;
        public const int IntegrityError = 9;
        public const int DoctorCheckFailed = 10;
    }
}