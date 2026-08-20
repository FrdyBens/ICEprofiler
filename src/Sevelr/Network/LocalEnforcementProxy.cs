using System.Net;
using System.Net.Sockets;
using System.Text;
using Sevelr.Logging;
using Sevelr.Policies;

namespace Sevelr.Network;

public sealed class LocalEnforcementProxy : IDisposable
{
    private readonly CompiledPolicy _policy;
    private readonly IAuditLogger _logger;
    private readonly TcpListener _listener;
    private readonly CancellationTokenSource _cts = new();
    public int Port { get; }

    public LocalEnforcementProxy(CompiledPolicy policy, IAuditLogger logger)
    {
        _policy = policy;
        _logger = logger;
        _listener = new TcpListener(IPAddress.Loopback, 0);
        _listener.Start();
        Port = ((IPEndPoint)_listener.LocalEndpoint).Port;
    }

    public void Start()
    {
        Task.Run(async () =>
        {
            while (!_cts.Token.IsCancellationRequested)
            {
                try
                {
                    var client = await _listener.AcceptTcpClientAsync(_cts.Token);
                    _ = Task.Run(() => HandleClientAsync(client, _cts.Token));
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(_policy.ProjectId, "Proxy", $"Listener error: {ex.Message}");
                }
            }
        });
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken ct)
    {
        using (client)
        using (var clientStream = client.GetStream())
        {
            try
            {
                var buffer = new byte[8192];
                int read = await clientStream.ReadAsync(buffer, ct);
                if (read == 0) return;

                var request = Encoding.ASCII.GetString(buffer, 0, read);
                var lines = request.Split("\r\n");
                if (lines.Length == 0) return;

                var firstLine = lines[0].Split(' ');
                if (firstLine.Length < 2) return;

                var method = firstLine[0];
                var target = firstLine[1];

                string host;
                int port = 80;

                if (method.Equals("CONNECT", StringComparison.OrdinalIgnoreCase))
                {
                    var parts = target.Split(':');
                    host = parts[0];
                    if (parts.Length > 1 && int.TryParse(parts[1], out var p))
                        port = p;
                    else
                        port = 443;
                }
                else
                {
                    if (Uri.TryCreate(target, UriKind.Absolute, out var uri))
                    {
                        host = uri.Host;
                        port = uri.Port;
                    }
                    else
                    {
                        var parts = target.Split(':');
                        host = parts[0];
                    }
                }

                if (!IsHostAllowed(host))
                {
                    _logger.LogSecurityEvent(_policy.ProjectId, "ProxyFilter", host, "Drop", "Blocked unauthorized destination at socket proxy level.");
                    var blockedResponse = "HTTP/1.1 403 Forbidden\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n<h1>403 Forbidden - Blocked by Sevelr Security Policy</h1>";
                    var respBytes = Encoding.UTF8.GetBytes(blockedResponse);
                    await clientStream.WriteAsync(respBytes, ct);
                    return;
                }

                // Forward connection
                using var remoteClient = new TcpClient();
                await remoteClient.ConnectAsync(host, port, ct);
                using var remoteStream = remoteClient.GetStream();

                if (method.Equals("CONNECT", StringComparison.OrdinalIgnoreCase))
                {
                    var okResponse = Encoding.ASCII.GetBytes("HTTP/1.1 200 Connection Established\r\n\r\n");
                    await clientStream.WriteAsync(okResponse, ct);
                }
                else
                {
                    await remoteStream.WriteAsync(buffer.AsMemory(0, read), ct);
                }

                var clientToRemote = clientStream.CopyToAsync(remoteStream, ct);
                var remoteToClient = remoteStream.CopyToAsync(clientStream, ct);
                await Task.WhenAny(clientToRemote, remoteToClient);
            }
            catch { }
        }
    }

    private bool IsHostAllowed(string host)
    {
        host = host.Trim().ToLowerInvariant();
        if (host == "127.0.0.1" || host == "localhost") return true;

        if (_policy.Network.ExactDomains.Contains(host))
            return true;

        foreach (var wildcard in _policy.Network.WildcardDomains)
        {
            if (host.EndsWith("." + wildcard) || host == wildcard)
                return true;
        }

        return false;
    }

    public void Dispose()
    {
        _cts.Cancel();
        _listener.Stop();
    }
}
