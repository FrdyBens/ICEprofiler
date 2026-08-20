using Sevelr.Applications;
using Sevelr.Browser;
using Sevelr.Commands;
using Sevelr.Core;
using Sevelr.Diagnostics;
using Sevelr.Extensions;
using Sevelr.Filesystem;
using Sevelr.Logging;
using Sevelr.Network;
using Sevelr.Policies;
using Sevelr.Process;
using Sevelr.Projects;
using Sevelr.Runtime;
using Sevelr.Security;

namespace Sevelr;

public static class Program
{
    public static async Task<int> Main(string[] args)
    {
        OutputFormatter.PrintBanner();

        var parsed = CommandLineParser.Parse(args);
        if (string.IsNullOrEmpty(parsed.Command) || parsed.Flags.Contains("help"))
        {
            PrintUsage();
            return Constants.ExitCodes.Success;
        }

        var logger = new AuditLogger();
        var storage = new StorageManager();
        var aclManager = new WindowsAclManager(logger);
        var efsProvider = new WindowsEfsProvider(logger);
        var policyEngine = new PolicyCompiler();
        var extensionGen = new Mv3ExtensionGenerator();
        var networkEnforcer = new WindowsFirewallEnforcer(logger);
        var browserPolicy = new ChromiumPolicyManager(logger);
        var processManager = new WindowsProcessManager(logger);
        var runtimeState = new RuntimeStateManager();
        var tamperDetector = new TamperDetector(logger);

        var appFactory = new ApplicationProviderFactory();
        appFactory.RegisterProvider(new BraveApplicationProvider());
        appFactory.RegisterProvider(new CustomExecutableProvider());

        var projectManager = new ProjectManager(
            storage, aclManager, efsProvider, policyEngine,
            extensionGen, networkEnforcer, browserPolicy, processManager,
            runtimeState, tamperDetector, appFactory, logger);

        var doctorService = new DoctorService(projectManager, storage, aclManager, efsProvider, tamperDetector, appFactory);

        try
        {
            switch (parsed.Command)
            {
                case "create":
                    var template = parsed.Options.GetValueOrDefault("template", "strict");
                    projectManager.CreateProject(parsed.Target ?? throw new ConfigurationException("Project name is required."), template);
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine($"[✓] Project '{parsed.Target}' created successfully using template '{template}'.");
                    Console.ResetColor();
                    break;

                case "launch":
                    await projectManager.LaunchProjectAsync(
                        parsed.Target ?? "default",
                        temporary: parsed.Flags.Contains("temporary"));
                    break;

                case "doctor":
                    var results = await doctorService.RunDiagnosticsAsync(parsed.Target ?? throw new ConfigurationException("Project name is required."));
                    bool allPass = true;
                    Console.WriteLine($"Diagnostics for '{parsed.Target}':\n");
                    foreach (var r in results)
                    {
                        Console.ForegroundColor = r.Passed ? ConsoleColor.Green : ConsoleColor.Red;
                        Console.WriteLine($" [{(r.Passed ? "PASS" : "FAIL")}] {r.Component}: {r.Details}");
                        if (!r.Passed && r.Remediation != null)
                            Console.WriteLine($"        Action: {r.Remediation}");
                        if (!r.Passed) allPass = false;
                    }
                    Console.ResetColor();
                    return allPass ? Constants.ExitCodes.Success : Constants.ExitCodes.DoctorCheckFailed;

                case "version":
                    Console.WriteLine($"Sevelr Universal Application Isolation Engine v{Constants.PlatformVersion}");
                    break;

                default:
                    Console.ForegroundColor = ConsoleColor.Yellow;
                    Console.WriteLine($"Unknown command '{parsed.Command}'. Use --help for usage.");
                    Console.ResetColor();
                    return Constants.ExitCodes.GenericFailure;
            }

            return Constants.ExitCodes.Success;
        }
        catch (SevelrException sex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"\n[SECURITY ERROR] ({sex.GetType().Name}): {sex.Message}");
            Console.ResetColor();
            return sex.ExitCode;
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"\n[FATAL ERROR]: {ex.Message}");
            Console.ResetColor();
            return Constants.ExitCodes.GenericFailure;
        }
    }

    private static void PrintUsage()
    {
        Console.WriteLine(@"
Usage: sevelr <command> [target] [options]

Commands:
  create <project>    Initialize an isolated project environment
  launch <project>    Run an application inside an enforced sandbox
  doctor <project>    Perform end-to-end security diagnostics
  version             Print version information

Options:
  --template <name>   Template: strict, balanced, development, research, temporary
  --temporary         Purge isolated storage upon termination
");
    }
}
