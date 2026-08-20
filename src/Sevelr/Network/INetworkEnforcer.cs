using Sevelr.Policies;

namespace Sevelr.Network;

public interface INetworkEnforcer
{
    Task ApplyPolicyAsync(CompiledPolicy policy, string executablePath);
    Task RemovePolicyAsync(string projectId);
    Task<bool> VerifyEnforcementActiveAsync(string projectId, string executablePath);
}
