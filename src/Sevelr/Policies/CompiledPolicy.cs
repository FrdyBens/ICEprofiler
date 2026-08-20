namespace Sevelr.Policies;

public class CompiledPolicy
{
    public string ProjectId { get; set; } = string.Empty;
    public DateTime CompiledAt { get; set; } = DateTime.UtcNow;
    public string PolicyHash { get; set; } = string.Empty;
    public bool FailClosed { get; set; }

    public CompiledNetworkPolicy Network { get; set; } = new();
    public CompiledBrowserPolicy Browser { get; set; } = new();
    public CompiledFilesystemPolicy Filesystem { get; set; } = new();
    public CompiledProcessPolicy Process { get; set; } = new();
    public CompiledDnsPolicy Dns { get; set; } = new();
}

public class CompiledNetworkPolicy
{
    public string Mode { get; set; } = "allowlist";
    public HashSet<string> ExactDomains { get; set; } = [];
    public List<string> WildcardDomains { get; set; } = [];
    public HashSet<string> AllowedIps { get; set; } = [];
    public HashSet<int> AllowedPorts { get; set; } = [];
    public bool AllowHttp { get; set; }
    public bool AllowHttps { get; set; } = true;
    public bool AllowWebSocket { get; set; }
    public bool AllowQuic { get; set; }
    public bool AllowDirectIp { get; set; }
    public bool BlockPrivateRanges { get; set; } = true;
}

public class CompiledBrowserPolicy
{
    public Dictionary<string, object> EnterprisePolicies { get; set; } = [];
    public List<string> RequiredSecurityArguments { get; set; } = [];
    public List<string> UserArguments { get; set; } = [];
    public string ExtensionId { get; set; } = string.Empty;
    public string ExtensionPath { get; set; } = string.Empty;
    public bool DisableDevTools { get; set; } = true;
    public bool DisableExtensionTampering { get; set; } = true;
}

public class CompiledFilesystemPolicy
{
    public string ProfilePath { get; set; } = string.Empty;
    public string DownloadsPath { get; set; } = string.Empty;
    public string TempPath { get; set; } = string.Empty;
    public bool Encrypted { get; set; } = true;
    public bool StrictAcl { get; set; } = true;
}

public class CompiledProcessPolicy
{
    public bool MonitorChildren { get; set; } = true;
    public HashSet<string> AllowedExecutableNames { get; set; } = [];
    public long MaxMemoryBytes { get; set; } = 4096L * 1024L * 1024L;
}

public class CompiledDnsPolicy
{
    public bool BlockDoH { get; set; } = true;
    public bool BlockDoT { get; set; } = true;
    public List<string> AllowedStaticHosts { get; set; } = [];
}
