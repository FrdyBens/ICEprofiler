using Sevelr.Configuration.Models;
using Sevelr.Filesystem;
using Sevelr.Policies;
using Xunit;

namespace Sevelr.Tests;

public class NetworkPolicyTests
{
    private class MockStorage : IStorageManager
    {
        public ProjectStoragePaths InitializeProjectStorage(string projectId) => GetProjectPaths(projectId);
        public ProjectStoragePaths GetProjectPaths(string projectId) => new(
            Path.Combine(Path.GetTempPath(), projectId),
            Path.Combine(Path.GetTempPath(), projectId, "config"),
            Path.Combine(Path.GetTempPath(), projectId, "browser"),
            Path.Combine(Path.GetTempPath(), projectId, "downloads"),
            Path.Combine(Path.GetTempPath(), projectId, "temp"),
            Path.Combine(Path.GetTempPath(), projectId, "logs")
        );
        public void SecurePurge(string path) { }
    }

    [Fact]
    public void PolicyCompiler_CorrectlySeparatesExactAndWildcardDomains()
    {
        var config = new ProjectConfig
        {
            Project = new() { Id = "test-net" },
            Network = new()
            {
                AllowedDomains = ["github.com", "*.github.com", "api.stripe.com"]
            }
        };

        var compiler = new PolicyCompiler();
        var compiled = compiler.Compile(config, new MockStorage());

        Assert.Contains("github.com", compiled.Network.ExactDomains);
        Assert.Contains("api.stripe.com", compiled.Network.ExactDomains);
        Assert.Contains("github.com", compiled.Network.WildcardDomains);
        Assert.True(compiled.FailClosed);
    }
}