namespace Sevelr.Commands;

public class ParsedArguments
{
    public string Command { get; set; } = string.Empty;
    public string? Target { get; set; }
    public string? SecondaryTarget { get; set; }
    public Dictionary<string, string> Options { get; set; } = [];
    public HashSet<string> Flags { get; set; } = [];
}

public static class CommandLineParser
{
    public static ParsedArguments Parse(string[] args)
    {
        var result = new ParsedArguments();
        if (args.Length == 0) return result;

        int idx = 0;
        // Legacy backward compatibility wrappers (--launch, --status, --repair)
        if (args[0].StartsWith("--"))
        {
            result.Command = args[0][2..].ToLowerInvariant();
            idx = 1;
        }
        else
        {
            result.Command = args[0].ToLowerInvariant();
            idx = 1;
        }

        while (idx < args.Length)
        {
            var item = args[idx];
            if (item.StartsWith("--"))
            {
                var optName = item[2..].ToLowerInvariant();
                if (idx + 1 < args.Length && !args[idx + 1].StartsWith("--"))
                {
                    result.Options[optName] = args[idx + 1];
                    idx += 2;
                }
                else
                {
                    result.Flags.Add(optName);
                    idx++;
                }
            }
            else
            {
                if (result.Target == null)
                    result.Target = item;
                else if (result.SecondaryTarget == null)
                    result.SecondaryTarget = item;
                idx++;
            }
        }

        return result;
    }
}