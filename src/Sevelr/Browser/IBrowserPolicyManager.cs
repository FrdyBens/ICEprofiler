using Sevelr.Policies;

namespace Sevelr.Browser;

public interface IBrowserPolicyManager
{
    void ApplyPolicy(CompiledPolicy policy);
    void RemovePolicy(string projectId);
}
