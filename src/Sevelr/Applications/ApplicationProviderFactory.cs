using Sevelr.Core;

namespace Sevelr.Applications;

public class ApplicationProviderFactory
{
    private readonly Dictionary<string, IApplicationProvider> _providers = new(StringComparer.OrdinalIgnoreCase);

    public void RegisterProvider(IApplicationProvider provider)
    {
        _providers[provider.Name] = provider;
    }

    public IApplicationProvider GetProvider(string name)
    {
        if (_providers.TryGetValue(name, out var provider))
            return provider;

        throw new ConfigurationException($"Unsupported application provider '{name}'. Available: {string.Join(", ", _providers.Keys)}");
    }
}
