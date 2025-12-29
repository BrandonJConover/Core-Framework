using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Database;

namespace OpenRSC.Server.Security;

/// <summary>
/// Device attributes collected for fingerprinting.
/// </summary>
public sealed class DeviceAttributes
{
    /// <summary>Platform (ios, android, web, windows, macos, linux).</summary>
    [JsonPropertyName("platform")]
    public string? Platform { get; set; }

    /// <summary>Operating system version.</summary>
    [JsonPropertyName("osVersion")]
    public string? OsVersion { get; set; }

    /// <summary>Device model (iPhone14,2, Pixel 7, etc.).</summary>
    [JsonPropertyName("deviceModel")]
    public string? DeviceModel { get; set; }

    /// <summary>Device manufacturer.</summary>
    [JsonPropertyName("manufacturer")]
    public string? Manufacturer { get; set; }

    /// <summary>Browser name (for web).</summary>
    [JsonPropertyName("browser")]
    public string? Browser { get; set; }

    /// <summary>Browser version.</summary>
    [JsonPropertyName("browserVersion")]
    public string? BrowserVersion { get; set; }

    /// <summary>User agent string.</summary>
    [JsonPropertyName("userAgent")]
    public string? UserAgent { get; set; }

    /// <summary>Screen width.</summary>
    [JsonPropertyName("screenWidth")]
    public int? ScreenWidth { get; set; }

    /// <summary>Screen height.</summary>
    [JsonPropertyName("screenHeight")]
    public int? ScreenHeight { get; set; }

    /// <summary>Screen pixel density.</summary>
    [JsonPropertyName("pixelRatio")]
    public float? PixelRatio { get; set; }

    /// <summary>Device timezone.</summary>
    [JsonPropertyName("timezone")]
    public string? Timezone { get; set; }

    /// <summary>Device language.</summary>
    [JsonPropertyName("language")]
    public string? Language { get; set; }

    /// <summary>Number of CPU cores.</summary>
    [JsonPropertyName("cpuCores")]
    public int? CpuCores { get; set; }

    /// <summary>Device memory in GB (approximate).</summary>
    [JsonPropertyName("deviceMemory")]
    public int? DeviceMemory { get; set; }

    /// <summary>WebGL renderer (for web).</summary>
    [JsonPropertyName("webglRenderer")]
    public string? WebGLRenderer { get; set; }

    /// <summary>WebGL vendor (for web).</summary>
    [JsonPropertyName("webglVendor")]
    public string? WebGLVendor { get; set; }

    /// <summary>Canvas fingerprint hash (for web).</summary>
    [JsonPropertyName("canvasHash")]
    public string? CanvasHash { get; set; }

    /// <summary>Audio context fingerprint (for web).</summary>
    [JsonPropertyName("audioHash")]
    public string? AudioHash { get; set; }

    /// <summary>Installed fonts hash (for web).</summary>
    [JsonPropertyName("fontsHash")]
    public string? FontsHash { get; set; }

    /// <summary>iOS Vendor ID or Android ID.</summary>
    [JsonPropertyName("vendorId")]
    public string? VendorId { get; set; }

    /// <summary>App version.</summary>
    [JsonPropertyName("appVersion")]
    public string? AppVersion { get; set; }

    /// <summary>App build number.</summary>
    [JsonPropertyName("appBuild")]
    public string? AppBuild { get; set; }

    /// <summary>Whether device is jailbroken/rooted.</summary>
    [JsonPropertyName("isCompromised")]
    public bool? IsCompromised { get; set; }

    /// <summary>Whether running in emulator/simulator.</summary>
    [JsonPropertyName("isEmulator")]
    public bool? IsEmulator { get; set; }

    /// <summary>Additional custom attributes.</summary>
    [JsonPropertyName("custom")]
    public Dictionary<string, string>? Custom { get; set; }
}

/// <summary>
/// A registered/known device for a user.
/// </summary>
public sealed class KnownDevice
{
    /// <summary>Unique device ID.</summary>
    public required string DeviceId { get; init; }

    /// <summary>Device fingerprint hash.</summary>
    public required string FingerprintHash { get; init; }

    /// <summary>Associated username.</summary>
    public required string Username { get; init; }

    /// <summary>User-friendly device name.</summary>
    public string? DeviceName { get; set; }

    /// <summary>Platform (ios, android, web).</summary>
    public string? Platform { get; init; }

    /// <summary>Device model.</summary>
    public string? DeviceModel { get; init; }

    /// <summary>Operating system.</summary>
    public string? OperatingSystem { get; init; }

    /// <summary>Browser (for web).</summary>
    public string? Browser { get; init; }

    /// <summary>When the device was first seen.</summary>
    public DateTime FirstSeenAt { get; init; } = DateTime.UtcNow;

    /// <summary>When the device was last used.</summary>
    public DateTime LastUsedAt { get; set; } = DateTime.UtcNow;

    /// <summary>Last IP address used with this device.</summary>
    public string? LastIpAddress { get; set; }

    /// <summary>Last location (approximate, from IP).</summary>
    public string? LastLocation { get; set; }

    /// <summary>Number of times this device has been used.</summary>
    public int UseCount { get; set; } = 1;

    /// <summary>Whether the device is trusted by the user.</summary>
    public bool IsTrusted { get; set; }

    /// <summary>Whether the device is blocked.</summary>
    public bool IsBlocked { get; set; }

    /// <summary>Reason for blocking.</summary>
    public string? BlockReason { get; set; }
}

/// <summary>
/// Device verification result.
/// </summary>
public sealed class DeviceVerificationResult
{
    /// <summary>Whether the device is recognized.</summary>
    public bool IsKnownDevice { get; init; }

    /// <summary>Whether the device is trusted.</summary>
    public bool IsTrusted { get; init; }

    /// <summary>Whether the device is blocked.</summary>
    public bool IsBlocked { get; init; }

    /// <summary>The known device record (if found).</summary>
    public KnownDevice? Device { get; init; }

    /// <summary>Computed fingerprint hash.</summary>
    public required string FingerprintHash { get; init; }

    /// <summary>Risk score (0-100, higher = more suspicious).</summary>
    public int RiskScore { get; init; }

    /// <summary>Risk factors identified.</summary>
    public List<string> RiskFactors { get; init; } = [];

    /// <summary>Whether additional verification is recommended.</summary>
    public bool RequiresVerification { get; init; }
}

/// <summary>
/// Device fingerprinting and management service.
/// </summary>
public sealed class DeviceFingerprintService
{
    private readonly ILogger<DeviceFingerprintService> _logger;
    private readonly DeviceSettings _settings;
    private readonly ISecurityAuditLogger _auditLogger;
    private readonly RedisCacheService? _redis;

    // In-memory storage (use database in production)
    private readonly ConcurrentDictionary<string, List<KnownDevice>> _userDevices = new();
    private readonly ConcurrentDictionary<string, KnownDevice> _deviceById = new();

    private readonly byte[] _fingerprintKey;

    public DeviceFingerprintService(
        ILogger<DeviceFingerprintService> logger,
        IOptions<DeviceSettings> settings,
        IOptions<SecuritySettings> securitySettings,
        ISecurityAuditLogger auditLogger,
        RedisCacheService? redis = null)
    {
        _logger = logger;
        _settings = settings.Value;
        _auditLogger = auditLogger;
        _redis = redis;

        // Derive fingerprint key from master key
        if (!string.IsNullOrEmpty(securitySettings.Value.MasterEncryptionKey))
        {
            var masterKey = Convert.FromBase64String(securitySettings.Value.MasterEncryptionKey);
            using var hmac = new HMACSHA256(masterKey);
            _fingerprintKey = hmac.ComputeHash(Encoding.UTF8.GetBytes("device-fingerprint"));
        }
        else
        {
            _fingerprintKey = RandomNumberGenerator.GetBytes(32);
        }
    }

    /// <summary>
    /// Computes a fingerprint hash from device attributes.
    /// </summary>
    public string ComputeFingerprint(DeviceAttributes attributes)
    {
        // Collect stable attributes for fingerprinting
        var components = new List<string>();

        // High-entropy attributes (more unique)
        if (!string.IsNullOrEmpty(attributes.VendorId))
            components.Add($"vendor:{attributes.VendorId}");

        if (!string.IsNullOrEmpty(attributes.CanvasHash))
            components.Add($"canvas:{attributes.CanvasHash}");

        if (!string.IsNullOrEmpty(attributes.WebGLRenderer))
            components.Add($"webgl:{attributes.WebGLRenderer}");

        if (!string.IsNullOrEmpty(attributes.AudioHash))
            components.Add($"audio:{attributes.AudioHash}");

        // Medium-entropy attributes
        if (!string.IsNullOrEmpty(attributes.Platform))
            components.Add($"platform:{attributes.Platform}");

        if (!string.IsNullOrEmpty(attributes.DeviceModel))
            components.Add($"model:{attributes.DeviceModel}");

        if (!string.IsNullOrEmpty(attributes.OsVersion))
            components.Add($"os:{attributes.OsVersion}");

        if (!string.IsNullOrEmpty(attributes.Browser))
            components.Add($"browser:{attributes.Browser}:{attributes.BrowserVersion}");

        if (attributes.ScreenWidth.HasValue && attributes.ScreenHeight.HasValue)
            components.Add($"screen:{attributes.ScreenWidth}x{attributes.ScreenHeight}");

        if (attributes.PixelRatio.HasValue)
            components.Add($"dpr:{attributes.PixelRatio:F1}");

        // Low-entropy but still useful
        if (!string.IsNullOrEmpty(attributes.Timezone))
            components.Add($"tz:{attributes.Timezone}");

        if (!string.IsNullOrEmpty(attributes.Language))
            components.Add($"lang:{attributes.Language}");

        if (attributes.CpuCores.HasValue)
            components.Add($"cpu:{attributes.CpuCores}");

        if (attributes.DeviceMemory.HasValue)
            components.Add($"mem:{attributes.DeviceMemory}");

        // Sort for consistency
        components.Sort();

        // Hash the combined components
        var data = string.Join("|", components);
        using var hmac = new HMACSHA256(_fingerprintKey);
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(data));

        return Convert.ToBase64String(hash)
            .Replace("+", "-")
            .Replace("/", "_")
            .TrimEnd('=');
    }

    /// <summary>
    /// Verifies a device and returns the verification result.
    /// </summary>
    public async Task<DeviceVerificationResult> VerifyDeviceAsync(
        string username,
        DeviceAttributes attributes,
        string? ipAddress = null)
    {
        var fingerprintHash = ComputeFingerprint(attributes);
        var riskFactors = new List<string>();
        var riskScore = 0;

        // Check for compromised/emulator
        if (attributes.IsCompromised == true)
        {
            riskFactors.Add("Device appears to be jailbroken/rooted");
            riskScore += 30;
        }

        if (attributes.IsEmulator == true)
        {
            riskFactors.Add("Running in emulator/simulator");
            riskScore += 20;
        }

        // Look up known devices
        var knownDevice = await FindDeviceAsync(username, fingerprintHash);

        if (knownDevice is not null)
        {
            // Known device
            if (knownDevice.IsBlocked)
            {
                _logger.LogWarning("Blocked device attempted login: {DeviceId} for {Username}",
                    knownDevice.DeviceId, username);

                return new DeviceVerificationResult
                {
                    IsKnownDevice = true,
                    IsTrusted = false,
                    IsBlocked = true,
                    Device = knownDevice,
                    FingerprintHash = fingerprintHash,
                    RiskScore = 100,
                    RiskFactors = ["Device is blocked: " + (knownDevice.BlockReason ?? "No reason given")]
                };
            }

            // Update last used
            knownDevice.LastUsedAt = DateTime.UtcNow;
            knownDevice.LastIpAddress = ipAddress;
            knownDevice.UseCount++;
            await UpdateDeviceAsync(knownDevice);

            return new DeviceVerificationResult
            {
                IsKnownDevice = true,
                IsTrusted = knownDevice.IsTrusted,
                IsBlocked = false,
                Device = knownDevice,
                FingerprintHash = fingerprintHash,
                RiskScore = riskScore,
                RiskFactors = riskFactors
            };
        }

        // New device
        riskFactors.Add("New device");
        riskScore += _settings.NewDeviceRiskScore;

        // Check if user has too many devices
        var userDevices = await GetUserDevicesAsync(username);
        if (userDevices.Count >= _settings.MaxDevicesPerUser)
        {
            riskFactors.Add($"User has {userDevices.Count} devices (max: {_settings.MaxDevicesPerUser})");
            riskScore += 15;
        }

        // Check for device attribute anomalies
        if (string.IsNullOrEmpty(attributes.Platform))
        {
            riskFactors.Add("Missing platform information");
            riskScore += 10;
        }

        if (attributes.Platform == "web" && string.IsNullOrEmpty(attributes.UserAgent))
        {
            riskFactors.Add("Web client without user agent");
            riskScore += 15;
        }

        var requiresVerification = riskScore >= _settings.VerificationThreshold;

        _logger.LogInformation(
            "New device for {Username}: platform={Platform}, model={Model}, risk={Risk}",
            username, attributes.Platform, attributes.DeviceModel, riskScore);

        return new DeviceVerificationResult
        {
            IsKnownDevice = false,
            IsTrusted = false,
            IsBlocked = false,
            Device = null,
            FingerprintHash = fingerprintHash,
            RiskScore = riskScore,
            RiskFactors = riskFactors,
            RequiresVerification = requiresVerification
        };
    }

    /// <summary>
    /// Registers a new device for a user.
    /// </summary>
    public async Task<KnownDevice> RegisterDeviceAsync(
        string username,
        DeviceAttributes attributes,
        string? deviceName = null,
        string? ipAddress = null,
        bool trusted = false)
    {
        var fingerprintHash = ComputeFingerprint(attributes);
        var deviceId = GenerateDeviceId();

        var device = new KnownDevice
        {
            DeviceId = deviceId,
            FingerprintHash = fingerprintHash,
            Username = username,
            DeviceName = deviceName ?? GenerateDeviceName(attributes),
            Platform = attributes.Platform,
            DeviceModel = attributes.DeviceModel,
            OperatingSystem = $"{attributes.Platform} {attributes.OsVersion}".Trim(),
            Browser = attributes.Browser,
            LastIpAddress = ipAddress,
            IsTrusted = trusted
        };

        await StoreDeviceAsync(device);

        // Enforce max devices
        await EnforceMaxDevicesAsync(username);

        _auditLogger.Log(new SecurityAuditEvent
        {
            EventType = SecurityEventType.SessionCreated,
            Severity = SecurityEventSeverity.Info,
            Username = username,
            IpAddress = ipAddress,
            Success = true,
            Message = $"New device registered: {device.DeviceName}",
            Details = new Dictionary<string, object>
            {
                ["deviceId"] = deviceId,
                ["platform"] = attributes.Platform ?? "unknown",
                ["model"] = attributes.DeviceModel ?? "unknown"
            }
        });

        _logger.LogInformation("Registered new device {DeviceId} for {Username}: {DeviceName}",
            deviceId, username, device.DeviceName);

        return device;
    }

    /// <summary>
    /// Gets all devices for a user.
    /// </summary>
    public async Task<List<KnownDevice>> GetUserDevicesAsync(string username)
    {
        var key = username.ToLowerInvariant();

        if (_userDevices.TryGetValue(key, out var devices))
        {
            return devices.Where(d => !d.IsBlocked).OrderByDescending(d => d.LastUsedAt).ToList();
        }

        // Try Redis
        if (_redis?.IsConnected == true)
        {
            var cached = await _redis.GetAsync<List<KnownDevice>>($"devices:{key}");
            if (cached is not null)
            {
                _userDevices[key] = cached;
                foreach (var d in cached)
                {
                    _deviceById[d.DeviceId] = d;
                }
                return cached.Where(d => !d.IsBlocked).OrderByDescending(d => d.LastUsedAt).ToList();
            }
        }

        return [];
    }

    /// <summary>
    /// Gets a device by ID.
    /// </summary>
    public async Task<KnownDevice?> GetDeviceAsync(string deviceId)
    {
        if (_deviceById.TryGetValue(deviceId, out var device))
            return device;

        if (_redis?.IsConnected == true)
        {
            device = await _redis.GetAsync<KnownDevice>($"device:{deviceId}");
            if (device is not null)
            {
                _deviceById[deviceId] = device;
            }
        }

        return device;
    }

    /// <summary>
    /// Trusts a device.
    /// </summary>
    public async Task<bool> TrustDeviceAsync(string username, string deviceId)
    {
        var device = await GetDeviceAsync(deviceId);
        if (device is null || device.Username.ToLowerInvariant() != username.ToLowerInvariant())
            return false;

        device.IsTrusted = true;
        await UpdateDeviceAsync(device);

        _logger.LogInformation("Device {DeviceId} trusted for {Username}", deviceId, username);
        return true;
    }

    /// <summary>
    /// Untrusts a device.
    /// </summary>
    public async Task<bool> UntrustDeviceAsync(string username, string deviceId)
    {
        var device = await GetDeviceAsync(deviceId);
        if (device is null || device.Username.ToLowerInvariant() != username.ToLowerInvariant())
            return false;

        device.IsTrusted = false;
        await UpdateDeviceAsync(device);

        _logger.LogInformation("Device {DeviceId} untrusted for {Username}", deviceId, username);
        return true;
    }

    /// <summary>
    /// Blocks a device.
    /// </summary>
    public async Task<bool> BlockDeviceAsync(string username, string deviceId, string? reason = null)
    {
        var device = await GetDeviceAsync(deviceId);
        if (device is null || device.Username.ToLowerInvariant() != username.ToLowerInvariant())
            return false;

        device.IsBlocked = true;
        device.BlockReason = reason;
        device.IsTrusted = false;
        await UpdateDeviceAsync(device);

        _auditLogger.Log(new SecurityAuditEvent
        {
            EventType = SecurityEventType.SuspiciousActivity,
            Severity = SecurityEventSeverity.Warning,
            Username = username,
            Success = true,
            Message = $"Device blocked: {device.DeviceName}",
            Details = new Dictionary<string, object>
            {
                ["deviceId"] = deviceId,
                ["reason"] = reason ?? "User requested"
            }
        });

        _logger.LogWarning("Device {DeviceId} blocked for {Username}: {Reason}",
            deviceId, username, reason ?? "User requested");

        return true;
    }

    /// <summary>
    /// Removes a device.
    /// </summary>
    public async Task<bool> RemoveDeviceAsync(string username, string deviceId)
    {
        var key = username.ToLowerInvariant();

        if (_userDevices.TryGetValue(key, out var devices))
        {
            var device = devices.FirstOrDefault(d => d.DeviceId == deviceId);
            if (device is not null)
            {
                devices.Remove(device);
                _deviceById.TryRemove(deviceId, out _);

                if (_redis?.IsConnected == true)
                {
                    await _redis.DeleteAsync($"device:{deviceId}");
                    await _redis.SetAsync($"devices:{key}", devices);
                }

                _logger.LogInformation("Device {DeviceId} removed for {Username}", deviceId, username);
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// Removes all devices for a user.
    /// </summary>
    public async Task<int> RemoveAllDevicesAsync(string username)
    {
        var key = username.ToLowerInvariant();
        var count = 0;

        if (_userDevices.TryRemove(key, out var devices))
        {
            count = devices.Count;
            foreach (var device in devices)
            {
                _deviceById.TryRemove(device.DeviceId, out _);

                if (_redis?.IsConnected == true)
                {
                    await _redis.DeleteAsync($"device:{device.DeviceId}");
                }
            }

            if (_redis?.IsConnected == true)
            {
                await _redis.DeleteAsync($"devices:{key}");
            }
        }

        _logger.LogInformation("Removed {Count} devices for {Username}", count, username);
        return count;
    }

    #region Private Methods

    private async Task<KnownDevice?> FindDeviceAsync(string username, string fingerprintHash)
    {
        var devices = await GetUserDevicesAsync(username);
        return devices.FirstOrDefault(d => d.FingerprintHash == fingerprintHash);
    }

    private async Task StoreDeviceAsync(KnownDevice device)
    {
        var key = device.Username.ToLowerInvariant();

        _deviceById[device.DeviceId] = device;

        _userDevices.AddOrUpdate(
            key,
            _ => [device],
            (_, list) => { list.Add(device); return list; });

        if (_redis?.IsConnected == true)
        {
            await _redis.SetAsync($"device:{device.DeviceId}", device, TimeSpan.FromDays(365));

            if (_userDevices.TryGetValue(key, out var devices))
            {
                await _redis.SetAsync($"devices:{key}", devices, TimeSpan.FromDays(365));
            }
        }
    }

    private async Task UpdateDeviceAsync(KnownDevice device)
    {
        _deviceById[device.DeviceId] = device;

        if (_redis?.IsConnected == true)
        {
            await _redis.SetAsync($"device:{device.DeviceId}", device, TimeSpan.FromDays(365));

            var key = device.Username.ToLowerInvariant();
            if (_userDevices.TryGetValue(key, out var devices))
            {
                await _redis.SetAsync($"devices:{key}", devices, TimeSpan.FromDays(365));
            }
        }
    }

    private async Task EnforceMaxDevicesAsync(string username)
    {
        var devices = await GetUserDevicesAsync(username);

        if (devices.Count <= _settings.MaxDevicesPerUser)
            return;

        // Remove oldest non-trusted devices
        var toRemove = devices
            .Where(d => !d.IsTrusted)
            .OrderBy(d => d.LastUsedAt)
            .Take(devices.Count - _settings.MaxDevicesPerUser)
            .ToList();

        foreach (var device in toRemove)
        {
            await RemoveDeviceAsync(username, device.DeviceId);
        }
    }

    private static string GenerateDeviceId()
    {
        return Convert.ToBase64String(RandomNumberGenerator.GetBytes(16))
            .Replace("+", "-")
            .Replace("/", "_")
            .TrimEnd('=');
    }

    private static string GenerateDeviceName(DeviceAttributes attributes)
    {
        var parts = new List<string>();

        if (!string.IsNullOrEmpty(attributes.DeviceModel))
        {
            parts.Add(attributes.DeviceModel);
        }
        else if (!string.IsNullOrEmpty(attributes.Manufacturer))
        {
            parts.Add(attributes.Manufacturer);
        }

        if (!string.IsNullOrEmpty(attributes.Platform))
        {
            parts.Add(attributes.Platform switch
            {
                "ios" => "iOS",
                "android" => "Android",
                "web" => attributes.Browser ?? "Web",
                "windows" => "Windows",
                "macos" => "macOS",
                "linux" => "Linux",
                _ => attributes.Platform
            });
        }

        return parts.Count > 0 ? string.Join(" ", parts) : "Unknown Device";
    }

    #endregion
}
