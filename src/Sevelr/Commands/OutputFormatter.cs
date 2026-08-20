namespace Sevelr.Commands;

public static class OutputFormatter
{
    public static void PrintBanner()
    {
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine(@"
   ______ _________  ______  __    ____ 
  / ___// ____/ | / / ____/ / /   / __ \
  \__ \/ __/ /  |/ / __/   / /   / /_/ /
 ___/ / /___/ /|  / /___  / /___/ _, _/ 
/____/_____/_/ |_/_____/ /_____/_/ |_|  
 Universal Windows Application Isolation Platform v2.0
");
        Console.ResetColor();
    }

    public static void PrintSecurityDashboard(string projectId, string app, string mode, bool netEnforced, bool efsEncrypted, bool aclStrict, bool processMonitored)
    {
        Console.WriteLine($"\n==================================================");
        Console.WriteLine($" SEVELR ENVIRONMENT: {projectId.ToUpper()}");
        Console.WriteLine($"==================================================");
        PrintRow("Application", app);
        PrintRow("Security Policy", mode.ToUpper(), mode == "strict" ? ConsoleColor.Red : ConsoleColor.Yellow);
        PrintRow("NTFS ACL Isolation", aclStrict ? "PROTECTED (RESTRICTED)" : "STANDARD", ConsoleColor.Green);
        PrintRow("Storage Encryption", efsEncrypted ? "ENABLED (EFS)" : "DISABLED", efsEncrypted ? ConsoleColor.Green : ConsoleColor.DarkGray);
        PrintRow("Native Network Enforce", netEnforced ? "ACTIVE (OS FIREWALL)" : "INACTIVE", netEnforced ? ConsoleColor.Green : ConsoleColor.Red);
        PrintRow("Process Sandbox / Job", processMonitored ? "ACTIVE (JOB_OBJECT)" : "STANDALONE", ConsoleColor.Green);
        Console.WriteLine($"==================================================\n");
    }

    private static void PrintRow(string label, string value, ConsoleColor color = ConsoleColor.White)
    {
        Console.Write($" {label,-22} : ");
        Console.ForegroundColor = color;
        Console.WriteLine(value);
        Console.ResetColor();
    }
}