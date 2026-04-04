using System.Collections.Concurrent;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;

namespace OpenRSC.Server.Security;

/// <summary>
/// Security event types for audit logging.
/// </summary>
public enum SecurityEventType
{
    // Authentication events
    LoginSuccess,
    LoginFailed,
    LoginBlocked,
    LogoutSuccess,
    SessionCreated,
    SessionExpired,
    SessionRevoked,

    // Account events
    AccountCreated,
    AccountLocked,
    AccountUnlocked,
    PasswordChanged,
    PasswordResetRequested,
    PasswordResetCompleted,

    // Authorization events
    AccessDenied,
    PrivilegeEscalation,
    AdminAction,

    // Security violations
    RateLimitExceeded,
    SuspiciousActivity,
    InvalidInput,
    TamperingDetected,
    BruteForceAttempt,

    // Data events
    SensitiveDataAccessed,
    DataExported,
    DataModified,

    // System events
    ConfigurationChanged,
    EncryptionKeyRotated,
    SecurityPolicyViolation
}

/// <summary>
/// Severity levels for security events.
/// </summary>
public enum SecurityEventSeverity
{
    /// <summary>Informational - normal security events.</summary>
    Info,

    /// <summary>Warning - potentially concerning but not critical.</summary>
    Warning,

    /// <summary>Critical - security violations requiring attention.</summary>
    Critical,

    /// <summary>Alert - immediate action required.</summary>
    Alert
}

/// <summary>
/// A security audit event.
/// </summary>
public sealed class SecurityAuditEvent
{
    /// <summary>Unique event identifier.</summary>
    public Guid EventId { get; init; } = Guid.NewGuid();

    /// <summary>Timestamp when the event occurred.</summary>
    public DateTime Timestamp { get; init; } = DateTime.UtcNow;

    /// <summary>Type of security event.</summary>
    public SecurityEventType EventType { get; init; }

    /// <summary>Severity of the event.</summary>
    public SecurityEventSeverity Severity { get; init; }

    /// <summary>Username associated with the event (if applicable).</summary>
    public string? Username { get; init; }

    /// <summary>IP address of the client.</summary>
    public string? IpAddress { get; init; }

    /// <summary>Session ID (if applicable).</summary>
    public string? SessionId { get; init; }

    /// <summary>Resource being accessed.</summary>
    public string? Resource { get; init; }

    /// <summary>Action being performed.</summary>
    public string? Action { get; init; }

    /// <summary>Whether the action was successful.</summary>
    public bool Success { get; init; }

    /// <summary>Human-readable message describing the event.</summary>
    public string Message { get; init; } = "";

    /// <summary>Additional details about the event.</summary>
    public Dictionary<string, object>? Details { get; init; }

    /// <summary>User agent string (for web clients).</summary>
    public string? UserAgent { get; init; }

    /// <summary>Request ID for tracing.</summary>
    public string? RequestId { get; init; }
}

/// <summary>
/// Security audit logger interface.
/// </summary>
public interface ISecurityAuditLogger
{
    void Log(SecurityAuditEvent evt);
    void LogLogin(string username, string ipAddress, bool success, string? reason = null);
    void LogLogout(string username, string ipAddress);
    void LogAccountLocked(string username, string ipAddress, int failedAttempts);
    void LogPasswordChange(string username, string ipAddress, bool success);
    void LogAccessDenied(string username, string ipAddress, string resource, string action);
    void LogSuspiciousActivity(string? username, string ipAddress, string description);
    void LogAdminAction(string adminUsername, string ipAddress, string action, string? targetUsername = null);
    Task FlushAsync();
}

/// <summary>
/// Security audit logger that writes to both structured logs and a dedicated audit file.
/// </summary>
public sealed class SecurityAuditLogger : ISecurityAuditLogger, IAsyncDisposable
{
    private readonly ILogger<SecurityAuditLogger> _logger;
    private readonly SecuritySettings _settings;
    private readonly ConcurrentQueue<SecurityAuditEvent> _eventQueue = new();
    private readonly SemaphoreSlim _flushLock = new(1, 1);
    private readonly CancellationTokenSource _cts = new();
    private readonly Task _backgroundTask;

    private StreamWriter? _auditWriter;
    private bool _disposed;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        WriteIndented = false
    };

    public SecurityAuditLogger(
        ILogger<SecurityAuditLogger> logger,
        IOptions<SecuritySettings> settings)
    {
        _logger = logger;
        _settings = settings.Value;

        if (_settings.EnableSecurityAuditLog)
        {
            InitializeAuditFile();
            _backgroundTask = Task.Run(BackgroundFlushLoop);
        }
        else
        {
            _backgroundTask = Task.CompletedTask;
        }
    }

    private void InitializeAuditFile()
    {
        try
        {
            var directory = Path.GetDirectoryName(_settings.SecurityAuditLogPath);
            if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
            }

            _auditWriter = new StreamWriter(_settings.SecurityAuditLogPath, append: true)
            {
                AutoFlush = false
            };

            _logger.LogInformation("Security audit log initialized: {Path}", _settings.SecurityAuditLogPath);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to initialize security audit log file");
        }
    }

    private async Task BackgroundFlushLoop()
    {
        while (!_cts.Token.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(5), _cts.Token);
                await FlushAsync();
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in security audit background flush");
            }
        }
    }

    public void Log(SecurityAuditEvent evt)
    {
        // Log to structured logger
        var logLevel = evt.Severity switch
        {
            SecurityEventSeverity.Alert => LogLevel.Critical,
            SecurityEventSeverity.Critical => LogLevel.Error,
            SecurityEventSeverity.Warning => LogLevel.Warning,
            _ => LogLevel.Information
        };

        _logger.Log(logLevel,
            "[Security] {EventType} - {Message} | User={Username} IP={IpAddress}",
            evt.EventType, evt.Message, evt.Username ?? "anonymous", evt.IpAddress ?? "unknown");

        // Queue for file logging
        if (_settings.EnableSecurityAuditLog)
        {
            _eventQueue.Enqueue(evt);
        }
    }

    public void LogLogin(string username, string ipAddress, bool success, string? reason = null)
    {
        Log(new SecurityAuditEvent
        {
            EventType = success ? SecurityEventType.LoginSuccess : SecurityEventType.LoginFailed,
            Severity = success ? SecurityEventSeverity.Info : SecurityEventSeverity.Warning,
            Username = username,
            IpAddress = ipAddress,
            Success = success,
            Message = success
                ? $"User '{username}' logged in successfully"
                : $"Login failed for user '{username}': {reason ?? "Invalid credentials"}",
            Details = reason != null ? new() { ["reason"] = reason } : null
        });
    }

    public void LogLogout(string username, string ipAddress)
    {
        Log(new SecurityAuditEvent
        {
            EventType = SecurityEventType.LogoutSuccess,
            Severity = SecurityEventSeverity.Info,
            Username = username,
            IpAddress = ipAddress,
            Success = true,
            Message = $"User '{username}' logged out"
        });
    }

    public void LogAccountLocked(string username, string ipAddress, int failedAttempts)
    {
        Log(new SecurityAuditEvent
        {
            EventType = SecurityEventType.AccountLocked,
            Severity = SecurityEventSeverity.Critical,
            Username = username,
            IpAddress = ipAddress,
            Success = false,
            Message = $"Account '{username}' locked after {failedAttempts} failed login attempts",
            Details = new() { ["failedAttempts"] = failedAttempts }
        });
    }

    public void LogPasswordChange(string username, string ipAddress, bool success)
    {
        Log(new SecurityAuditEvent
        {
            EventType = SecurityEventType.PasswordChanged,
            Severity = success ? SecurityEventSeverity.Info : SecurityEventSeverity.Warning,
            Username = username,
            IpAddress = ipAddress,
            Success = success,
            Message = success
                ? $"Password changed for user '{username}'"
                : $"Password change failed for user '{username}'"
        });
    }

    public void LogAccessDenied(string username, string ipAddress, string resource, string action)
    {
        Log(new SecurityAuditEvent
        {
            EventType = SecurityEventType.AccessDenied,
            Severity = SecurityEventSeverity.Warning,
            Username = username,
            IpAddress = ipAddress,
            Resource = resource,
            Action = action,
            Success = false,
            Message = $"Access denied for user '{username}' to {action} on {resource}"
        });
    }

    public void LogSuspiciousActivity(string? username, string ipAddress, string description)
    {
        Log(new SecurityAuditEvent
        {
            EventType = SecurityEventType.SuspiciousActivity,
            Severity = SecurityEventSeverity.Alert,
            Username = username,
            IpAddress = ipAddress,
            Success = false,
            Message = $"Suspicious activity detected: {description}"
        });
    }

    public void LogAdminAction(string adminUsername, string ipAddress, string action, string? targetUsername = null)
    {
        Log(new SecurityAuditEvent
        {
            EventType = SecurityEventType.AdminAction,
            Severity = SecurityEventSeverity.Info,
            Username = adminUsername,
            IpAddress = ipAddress,
            Action = action,
            Success = true,
            Message = targetUsername != null
                ? $"Admin '{adminUsername}' performed '{action}' on user '{targetUsername}'"
                : $"Admin '{adminUsername}' performed '{action}'",
            Details = targetUsername != null ? new() { ["targetUsername"] = targetUsername } : null
        });
    }

    public async Task FlushAsync()
    {
        if (_auditWriter is null || _eventQueue.IsEmpty)
            return;

        await _flushLock.WaitAsync();
        try
        {
            while (_eventQueue.TryDequeue(out var evt))
            {
                var json = JsonSerializer.Serialize(evt, JsonOptions);
                await _auditWriter.WriteLineAsync(json);
            }

            await _auditWriter.FlushAsync();
        }
        finally
        {
            _flushLock.Release();
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;

        await _cts.CancelAsync();

        try
        {
            await _backgroundTask;
        }
        catch
        {
            // Ignore cancellation exceptions
        }

        // Final flush
        await FlushAsync();

        _auditWriter?.Dispose();
        _cts.Dispose();
        _flushLock.Dispose();
    }
}

/// <summary>
/// Null implementation for when audit logging is disabled.
/// </summary>
public sealed class NullSecurityAuditLogger : ISecurityAuditLogger
{
    public static readonly NullSecurityAuditLogger Instance = new();

    public void Log(SecurityAuditEvent evt) { }
    public void LogLogin(string username, string ipAddress, bool success, string? reason = null) { }
    public void LogLogout(string username, string ipAddress) { }
    public void LogAccountLocked(string username, string ipAddress, int failedAttempts) { }
    public void LogPasswordChange(string username, string ipAddress, bool success) { }
    public void LogAccessDenied(string username, string ipAddress, string resource, string action) { }
    public void LogSuspiciousActivity(string? username, string ipAddress, string description) { }
    public void LogAdminAction(string adminUsername, string ipAddress, string action, string? targetUsername = null) { }
    public Task FlushAsync() => Task.CompletedTask;
}
