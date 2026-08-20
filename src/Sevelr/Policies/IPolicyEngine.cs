using Sevelr.Configuration.Models;
using Sevelr.Filesystem;

namespace Sevelr.Policies;

public interface IPolicyEngine
{
    CompiledPolicy Compile(ProjectConfig config, IStorageManager storage);
}
