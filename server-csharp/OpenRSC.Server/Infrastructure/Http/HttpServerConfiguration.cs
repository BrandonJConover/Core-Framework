using System.Net;
using System.Security.Cryptography.X509Certificates;
using Microsoft.AspNetCore.Server.Kestrel.Core;

namespace OpenRSC.Server.Infrastructure.Http;

/// <summary>
/// Configuration settings for the Kestrel HTTP server.
/// </summary>
public sealed class HttpServerSettings
{
    public const string SectionName = "HttpServer";

    /// <summary>
    /// Enable the HTTP API server.
    /// </summary>
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// HTTP port for the API server.
    /// </summary>
    public int HttpPort { get; set; } = 8080;

    /// <summary>
    /// HTTPS port for the API server.
    /// </summary>
    public int HttpsPort { get; set; } = 8443;

    /// <summary>
    /// Enable HTTPS.
    /// </summary>
    public bool EnableHttps { get; set; } = false;

    /// <summary>
    /// Enable HTTP/2 support.
    /// </summary>
    public bool EnableHttp2 { get; set; } = true;

    /// <summary>
    /// Enable HTTP/3 (QUIC) support.
    /// </summary>
    public bool EnableHttp3 { get; set; } = true;

    /// <summary>
    /// Path to TLS certificate (PFX format).
    /// </summary>
    public string CertificatePath { get; set; } = "";

    /// <summary>
    /// TLS certificate password.
    /// </summary>
    public string CertificatePassword { get; set; } = "";

    /// <summary>
    /// Maximum concurrent connections.
    /// </summary>
    public long? MaxConcurrentConnections { get; set; }

    /// <summary>
    /// Maximum request body size in bytes.
    /// </summary>
    public long MaxRequestBodySize { get; set; } = 10 * 1024 * 1024; // 10MB

    /// <summary>
    /// Request header timeout in seconds.
    /// </summary>
    public int RequestHeadersTimeoutSeconds { get; set; } = 30;

    /// <summary>
    /// Keep-alive timeout in seconds.
    /// </summary>
    public int KeepAliveTimeoutSeconds { get; set; } = 130;

    /// <summary>
    /// Allowed CORS origins (comma-separated, or * for all).
    /// </summary>
    public string CorsOrigins { get; set; } = "*";

    /// <summary>
    /// Enable Swagger/OpenAPI documentation.
    /// </summary>
    public bool EnableSwagger { get; set; } = true;

    /// <summary>
    /// API key for admin endpoints (empty = disabled).
    /// </summary>
    public string AdminApiKey { get; set; } = "";

    /// <summary>
    /// Enable rate limiting for API endpoints.
    /// </summary>
    public bool EnableRateLimiting { get; set; } = true;

    /// <summary>
    /// Rate limit requests per minute per IP.
    /// </summary>
    public int RateLimitPerMinute { get; set; } = 100;
}

/// <summary>
/// Extension methods for configuring Kestrel HTTP server.
/// </summary>
public static class KestrelConfigurationExtensions
{
    /// <summary>
    /// Configures Kestrel with HTTP/1.1, HTTP/2, and HTTP/3 support.
    /// </summary>
    public static void ConfigureKestrel(this WebApplicationBuilder builder, HttpServerSettings settings)
    {
        builder.WebHost.ConfigureKestrel((context, options) =>
        {
            // HTTP endpoint
            options.Listen(IPAddress.Any, settings.HttpPort, listenOptions =>
            {
                listenOptions.Protocols = settings.EnableHttp2
                    ? HttpProtocols.Http1AndHttp2
                    : HttpProtocols.Http1;
            });

            // HTTPS endpoint with HTTP/2 and HTTP/3
            if (settings.EnableHttps && !string.IsNullOrEmpty(settings.CertificatePath))
            {
                var cert = LoadCertificate(settings.CertificatePath, settings.CertificatePassword);

                options.Listen(IPAddress.Any, settings.HttpsPort, listenOptions =>
                {
                    listenOptions.UseHttps(cert);

                    if (settings.EnableHttp3)
                    {
                        listenOptions.Protocols = HttpProtocols.Http1AndHttp2AndHttp3;
                    }
                    else if (settings.EnableHttp2)
                    {
                        listenOptions.Protocols = HttpProtocols.Http1AndHttp2;
                    }
                });
            }

            // Connection limits
            if (settings.MaxConcurrentConnections.HasValue)
            {
                options.Limits.MaxConcurrentConnections = settings.MaxConcurrentConnections.Value;
            }

            options.Limits.MaxRequestBodySize = settings.MaxRequestBodySize;
            options.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(settings.RequestHeadersTimeoutSeconds);
            options.Limits.KeepAliveTimeout = TimeSpan.FromSeconds(settings.KeepAliveTimeoutSeconds);

            // HTTP/2 specific settings
            options.Limits.Http2.MaxStreamsPerConnection = 100;
            options.Limits.Http2.InitialConnectionWindowSize = 128 * 1024;
            options.Limits.Http2.InitialStreamWindowSize = 96 * 1024;

            // HTTP/3 specific settings (if supported)
            if (settings.EnableHttp3)
            {
                options.Limits.Http3.MaxRequestHeaderFieldSize = 16 * 1024;
            }
        });
    }

    private static X509Certificate2 LoadCertificate(string path, string password)
    {
        if (string.IsNullOrEmpty(password))
        {
            return new X509Certificate2(path);
        }

        return new X509Certificate2(path, password, X509KeyStorageFlags.MachineKeySet);
    }
}
