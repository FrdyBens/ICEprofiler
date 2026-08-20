namespace Sevelr.Core;

public abstract class SevelrException : Exception
{
    public abstract int ExitCode { get; }
    protected SevelrException(string message) : base(message) { }
    protected SevelrException(string message, Exception inner) : base(message, inner) { }
}

public class ConfigurationException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.ConfigurationError;
}

public class PolicyException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.PolicyError;
}

public class SecurityViolationException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.SecurityError;
}

public class NetworkEnforcementException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.NetworkError;
}

public class FilesystemIsolationException(string message, Exception? inner = null) : SevelrException(message, inner!)
{
    public override int ExitCode => Constants.ExitCodes.FilesystemError;
}

public class ProcessManagementException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.ProcessError;
}

public class IntegrityVerificationException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.IntegrityError;
}

public class BrowserManagementException(string message) : SevelrException(message)
{
    public override int ExitCode => Constants.ExitCodes.BrowserError;
}
