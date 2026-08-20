using Sevelr.Policies;

namespace Sevelr.Extensions;

public interface IExtensionGenerator
{
    void GenerateExtension(CompiledPolicy policy, string outputDirectory);
}
