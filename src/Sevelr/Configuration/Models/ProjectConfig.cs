using System.Text.Json.Serialization;
using Sevelr.Core;

namespace Sevelr.Configuration.Models;

public class ProjectConfig
{
    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; } = Constants.CurrentSchemaVersion;

    [JsonPropertyName("project")]
    public ProjectIdentity Project { get; set; } = new();

    [JsonPropertyName("application")]
    public ApplicationConfig Application { get; set; } = new();

    [JsonPropertyName("network")]
    public NetworkConfig Network { get; set; } = new();

    [JsonPropertyName("dns")]
    public DnsConfig Dns { get; set; } = new();

    [JsonPropertyName("filesystem")]
    public FilesystemConfig Filesystem { get; set; } = new();

    [JsonPropertyName("process")]
    public ProcessConfig Process { get; set; } = new();

    [JsonPropertyName("privacy")]
    public PrivacyConfig Privacy { get; set; } = new();

    [JsonPropertyName("security")]
    public SecurityConfig Security { get; set; } = new();
}

public class ProjectIdentity
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("displayName")]
    public string DisplayName { get; set; } = string.Empty;

    [JsonPropertyName("description")]
    public string Description { get; set; } = string.Empty;

    [JsonPropertyName("template")]
    public string Template { get; set; } = "strict";

    [JsonPropertyName("createdAt")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    [JsonPropertyName("updatedAt")]
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

public class ApplicationConfig
{
    [JsonPropertyName("provider")]
    public string Provider { get; set; } = "brave";

    [JsonPropertyName("executable")]
    public string? Executable { get; set; }

    [JsonPropertyName("arguments")]
    public List<string> Arguments { get; set; } = [];

    [JsonPropertyName("initialUrl")]
    public string InitialUrl { get; set; } = "about:blank";

    [JsonPropertyName("environmentVariables")]
    public Dictionary<string, string> EnvironmentVariables { get; set; } = [];
}

public class NetworkConfig
{
    [JsonPropertyName("mode")]
    public string Mode { get; set; } = "allowlist";

    [JsonPropertyName("allowedDomains")]
    public List<string> AllowedDomains { get; set; } = [];

    [JsonPropertyName("deniedDomains")]
    public List<string> DeniedDomains { get; set; } = [];

    [JsonPropertyName("allowedIps")]
    public List<string> AllowedIps { get; set; } = [];

    [JsonPropertyName("allowedCidrs")]
    public List<string> AllowedCidrs { get; set; } = [];

    [JsonPropertyName("allowedPorts")]
    public List<int> AllowedPorts { get; set; } = [80, 443];

    [JsonPropertyName("allowHttp")]
    public bool AllowHttp { get; set; } = false;

    [JsonPropertyName("allowHttps")]
    public bool AllowHttps { get; set; } = true;

    [JsonPropertyName("allowWebSocket")]
    public bool AllowWebSocket { get; set; } = false;

    [JsonPropertyName("allowQuic")]
    public bool AllowQuic { get; set; } = false;

    [JsonPropertyName("allowIpv6")]
    public bool AllowIpv6 { get; set; } = true;

    [JsonPropertyName("allowLocalhost")]
    public bool AllowLocalhost { get; set; } = false;

    [JsonPropertyName("allowPrivateNetworks")]
    public bool AllowPrivateNetworks { get; set; } = false;
}

public class DnsConfig
{
    [JsonPropertyName("mode")]
    public string Mode { get; set; } = "policy";

    [JsonPropertyName("allowDirectIp")]
    public bool AllowDirectIp { get; set; } = false;

    [JsonPropertyName("allowDoh")]
    public bool AllowDoh { get; set; } = false;

    [JsonPropertyName("allowDot")]
    public bool AllowDot { get; set; } = false;

    [JsonPropertyName("customResolvers")]
    public List<string> CustomResolvers { get; set; } = [];
}

public class FilesystemConfig
{
    [JsonPropertyName("encrypted")]
    public bool Encrypted { get; set; } = true;

    [JsonPropertyName("downloads")]
    public string Downloads { get; set; } = "isolated";

    [JsonPropertyName("temporaryFiles")]
    public string TemporaryFiles { get; set; } = "isolated";

    [JsonPropertyName("allowSharedDirectories")]
    public bool AllowSharedDirectories { get; set; } = false;

    [JsonPropertyName("customStoragePath")]
    public string? CustomStoragePath { get; set; }
}

public class ProcessConfig
{
    [JsonPropertyName("monitor")]
    public bool Monitor { get; set; } = true;

    [JsonPropertyName("allowChildProcesses")]
    public bool AllowChildProcesses { get; set; } = true;

    [JsonPropertyName("allowedExecutables")]
    public List<string> AllowedExecutables { get; set; } = [];

    [JsonPropertyName("maxMemoryMb")]
    public int MaxMemoryMb { get; set; } = 4096;

    [JsonPropertyName("singleInstancePerProject")]
    public bool SingleInstancePerProject { get; set; } = true;
}

public class PrivacyConfig
{
    [JsonPropertyName("sync")]
    public bool Sync { get; set; } = false;

    [JsonPropertyName("telemetry")]
    public bool Telemetry { get; set; } = false;

    [JsonPropertyName("passwordSaving")]
    public bool PasswordSaving { get; set; } = false;

    [JsonPropertyName("autofill")]
    public bool Autofill { get; set; } = false;

    [JsonPropertyName("clearOnExit")]
    public bool ClearOnExit { get; set; } = false;
}

public class SecurityConfig
{
    [JsonPropertyName("mode")]
    public string Mode { get; set; } = "strict";

    [JsonPropertyName("failClosed")]
    public bool FailClosed { get; set; } = true;

    [JsonPropertyName("tamperDetection")]
    public bool TamperDetection { get; set; } = true;

    [JsonPropertyName("integrityVerification")]
    public bool IntegrityVerification { get; set; } = true;

    [JsonPropertyName("requireSignedPolicy")]
    public bool RequireSignedPolicy { get; set; } = false;

    [JsonPropertyName("preventDevTools")]
    public bool PreventDevTools { get; set; } = true;

    [JsonPropertyName("preventExtensionsModification")]
    public bool PreventExtensionsModification { get; set; } = true;
}
