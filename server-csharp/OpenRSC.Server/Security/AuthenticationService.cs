using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Database;

namespace OpenRSC.Server.Security;

/// <summary>
/// Authentication method types.
/// </summary>
public enum AuthMethod
{
    Password,
    Email,
    RefreshToken,
    GoogleIdToken,
    AppleIdToken,
    DiscordOAuth
}

/// <summary>
/// Authentication request from client.
/// </summary>
public sealed class AuthRequest
{
    /// <summary>Authentication method being used.</summary>
    public AuthMethod Method { get; init; }

    /// <summary>Username (for password auth).</summary>
    public string? Username { get; init; }

    /// <summary>Email (for email-based auth).</summary>
    public string? Email { get; init; }

    /// <summary>Password (for password/email auth).</summary>
    public string? Password { get; init; }

    /// <summary>Refresh token (for token auth).</summary>
    public string? RefreshToken { get; init; }

    /// <summary>OAuth ID token (for Google/Apple mobile).</summary>
    public string? IdToken { get; init; }

    /// <summary>OAuth authorization code (for web flow).</summary>
    public string? AuthCode { get; init; }

    /// <summary>Device identifier for token binding.</summary>
    public string? DeviceId { get; init; }

    /// <summary>Device name for session display.</summary>
    public string? DeviceName { get; init; }

    /// <summary>Platform (ios, android, web).</summary>
    public string? Platform { get; init; }

    /// <summary>Client IP address.</summary>
    public string? IpAddress { get; init; }

    /// <summary>Client version.</summary>
    public int? ClientVersion { get; init; }
}

/// <summary>
/// Authentication result.
/// </summary>
public sealed class AuthResult
{
    /// <summary>Whether authentication succeeded.</summary>
    public bool Success { get; init; }

    /// <summary>Authenticated username.</summary>
    public string? Username { get; init; }

    /// <summary>Whether this is a new account.</summary>
    public bool IsNewAccount { get; init; }

    /// <summary>Access token for the session.</summary>
    public string? AccessToken { get; init; }

    /// <summary>Refresh token for persistent login.</summary>
    public string? RefreshToken { get; init; }

    /// <summary>Token expiration in seconds.</summary>
    public int ExpiresIn { get; init; }

    /// <summary>Error code.</summary>
    public string? Error { get; init; }

    /// <summary>Error description.</summary>
    public string? ErrorDescription { get; init; }

    /// <summary>Whether username selection is required (for OAuth).</summary>
    public bool RequiresUsername { get; init; }

    /// <summary>Suggested username (for OAuth).</summary>
    public string? SuggestedUsername { get; init; }

    /// <summary>OAuth profile (for account creation).</summary>
    public OAuthProfile? OAuthProfile { get; init; }

    public static AuthResult Failure(string error, string? description = null) => new()
    {
        Success = false,
        Error = error,
        ErrorDescription = description
    };

    public static AuthResult Ok(string username, string accessToken, string? refreshToken = null, int expiresIn = 3600) => new()
    {
        Success = true,
        Username = username,
        AccessToken = accessToken,
        RefreshToken = refreshToken,
        ExpiresIn = expiresIn
    };
}

/// <summary>
/// OAuth account link.
/// </summary>
public sealed class OAuthAccountLink
{
    public required string Username { get; init; }
    public required OAuthProvider Provider { get; init; }
    public required string ProviderId { get; init; }
    public string? Email { get; init; }
    public DateTime LinkedAt { get; init; } = DateTime.UtcNow;
}

/// <summary>
/// Unified authentication service supporting multiple methods.
/// </summary>
public sealed class AuthenticationService
{
    private readonly ILogger<AuthenticationService> _logger;
    private readonly OAuthSettings _oauthSettings;
    private readonly SecuritySettings _securitySettings;
    private readonly AuthTokenSettings _tokenSettings;
    private readonly OAuthService _oauthService;
    private readonly RefreshTokenManager _refreshTokenManager;
    private readonly AccountLockoutManager _lockoutManager;
    private readonly ISecurityAuditLogger _auditLogger;
    private readonly IPlayerRepository _playerRepository;

    // In-memory OAuth link storage (use database in production)
    private readonly Dictionary<string, List<OAuthAccountLink>> _oauthLinks = new();
    private readonly Dictionary<(OAuthProvider, string), string> _oauthToUsername = new();

    public AuthenticationService(
        ILogger<AuthenticationService> logger,
        IOptions<OAuthSettings> oauthSettings,
        IOptions<SecuritySettings> securitySettings,
        IOptions<AuthTokenSettings> tokenSettings,
        OAuthService oauthService,
        RefreshTokenManager refreshTokenManager,
        AccountLockoutManager lockoutManager,
        ISecurityAuditLogger auditLogger,
        IPlayerRepository playerRepository)
    {
        _logger = logger;
        _oauthSettings = oauthSettings.Value;
        _securitySettings = securitySettings.Value;
        _tokenSettings = tokenSettings.Value;
        _oauthService = oauthService;
        _refreshTokenManager = refreshTokenManager;
        _lockoutManager = lockoutManager;
        _auditLogger = auditLogger;
        _playerRepository = playerRepository;
    }

    /// <summary>
    /// Authenticates a user using the specified method.
    /// </summary>
    public async Task<AuthResult> AuthenticateAsync(AuthRequest request)
    {
        return request.Method switch
        {
            AuthMethod.Password => await AuthenticateWithPasswordAsync(request),
            AuthMethod.Email => await AuthenticateWithEmailAsync(request),
            AuthMethod.RefreshToken => await AuthenticateWithRefreshTokenAsync(request),
            AuthMethod.GoogleIdToken => await AuthenticateWithGoogleAsync(request),
            AuthMethod.AppleIdToken => await AuthenticateWithAppleAsync(request),
            AuthMethod.DiscordOAuth => await AuthenticateWithDiscordAsync(request),
            _ => AuthResult.Failure("invalid_method", "Unknown authentication method")
        };
    }

    #region Password Authentication

    private async Task<AuthResult> AuthenticateWithPasswordAsync(AuthRequest request)
    {
        if (string.IsNullOrEmpty(request.Username) || string.IsNullOrEmpty(request.Password))
            return AuthResult.Failure("invalid_request", "Username and password are required");

        var username = request.Username.Trim().ToLowerInvariant();

        // Check lockout
        if (_lockoutManager.IsLockedOut(username))
        {
            var remaining = _lockoutManager.GetRemainingLockoutTime(username);
            _auditLogger.LogLogin(username, request.IpAddress ?? "unknown", false, "Account locked");
            return AuthResult.Failure("account_locked",
                $"Account is locked. Try again in {remaining?.TotalMinutes:F0} minutes.");
        }

        // Load player
        var player = await _playerRepository.LoadPlayerAsync(username);
        if (player is null)
        {
            // Don't reveal whether account exists
            _lockoutManager.RecordFailedAttempt(username);
            _auditLogger.LogLogin(username, request.IpAddress ?? "unknown", false, "Account not found");
            return AuthResult.Failure("invalid_credentials", "Invalid username or password");
        }

        // Verify password
        if (string.IsNullOrEmpty(player.PasswordHash) ||
            !PasswordHasher.VerifyPassword(request.Password, player.PasswordHash))
        {
            var isLocked = _lockoutManager.RecordFailedAttempt(username);
            _auditLogger.LogLogin(username, request.IpAddress ?? "unknown", false,
                isLocked ? "Locked after failed attempt" : "Invalid password");

            if (isLocked)
            {
                _auditLogger.LogAccountLocked(username, request.IpAddress ?? "unknown",
                    _securitySettings.MaxFailedLoginAttempts);
            }

            return AuthResult.Failure("invalid_credentials", "Invalid username or password");
        }

        // Clear lockout on success
        _lockoutManager.ClearLockout(username);

        // Check if password needs upgrade
        if (PasswordHasher.NeedsRehash(player.PasswordHash))
        {
            player.PasswordHash = PasswordHasher.HashPassword(request.Password);
            await _playerRepository.SavePlayerAsync(player);
            _logger.LogInformation("Upgraded password hash for {Username}", username);
        }

        // Create tokens
        var tokens = await _refreshTokenManager.CreateTokenPairAsync(
            username,
            request.DeviceId,
            request.DeviceName,
            request.Platform,
            request.IpAddress);

        _auditLogger.LogLogin(username, request.IpAddress ?? "unknown", true);

        return new AuthResult
        {
            Success = true,
            Username = username,
            AccessToken = tokens.AccessToken,
            RefreshToken = tokens.RefreshToken,
            ExpiresIn = tokens.ExpiresIn
        };
    }

    #endregion

    #region Email Authentication

    private async Task<AuthResult> AuthenticateWithEmailAsync(AuthRequest request)
    {
        if (string.IsNullOrEmpty(request.Email) || string.IsNullOrEmpty(request.Password))
            return AuthResult.Failure("invalid_request", "Email and password are required");

        var email = request.Email.Trim().ToLowerInvariant();

        // Find player by email
        var player = await FindPlayerByEmailAsync(email);
        if (player is null)
        {
            _auditLogger.LogLogin(email, request.IpAddress ?? "unknown", false, "Email not found");
            return AuthResult.Failure("invalid_credentials", "Invalid email or password");
        }

        // Delegate to password auth with the found username
        var passwordRequest = request with { Username = player.Username };
        return await AuthenticateWithPasswordAsync(passwordRequest);
    }

    private async Task<PlayerData?> FindPlayerByEmailAsync(string email)
    {
        // This would be a database lookup in production
        // For now, load all players and find by email (not efficient, but works for demo)
        // In production, add an index on email column
        return null; // TODO: Implement email lookup in repository
    }

    #endregion

    #region Refresh Token Authentication

    private async Task<AuthResult> AuthenticateWithRefreshTokenAsync(AuthRequest request)
    {
        if (string.IsNullOrEmpty(request.RefreshToken))
            return AuthResult.Failure("invalid_request", "Refresh token is required");

        var tokens = await _refreshTokenManager.RefreshAccessTokenAsync(
            request.RefreshToken,
            request.IpAddress);

        if (tokens is null)
        {
            return AuthResult.Failure("invalid_token", "Refresh token is invalid or expired");
        }

        return new AuthResult
        {
            Success = true,
            Username = tokens.Username,
            AccessToken = tokens.AccessToken,
            RefreshToken = tokens.RefreshToken,
            ExpiresIn = tokens.ExpiresIn
        };
    }

    #endregion

    #region Google Authentication

    private async Task<AuthResult> AuthenticateWithGoogleAsync(AuthRequest request)
    {
        if (!_oauthSettings.EnableGoogle)
            return AuthResult.Failure("oauth_disabled", "Google authentication is not enabled");

        OAuthResult oauthResult;

        if (!string.IsNullOrEmpty(request.IdToken))
        {
            // Mobile: validate ID token directly
            oauthResult = await _oauthService.ValidateGoogleIdTokenAsync(request.IdToken);
        }
        else if (!string.IsNullOrEmpty(request.AuthCode))
        {
            // Web: exchange auth code
            oauthResult = await _oauthService.AuthenticateGoogleAsync(request.AuthCode);
        }
        else
        {
            return AuthResult.Failure("invalid_request", "ID token or auth code is required");
        }

        if (!oauthResult.Success || oauthResult.Profile is null)
        {
            _auditLogger.LogLogin("google_user", request.IpAddress ?? "unknown", false,
                oauthResult.Error ?? "OAuth failed");
            return AuthResult.Failure(oauthResult.Error ?? "oauth_failed", oauthResult.ErrorDescription);
        }

        return await HandleOAuthProfileAsync(oauthResult.Profile, request);
    }

    #endregion

    #region Apple Authentication

    private async Task<AuthResult> AuthenticateWithAppleAsync(AuthRequest request)
    {
        if (!_oauthSettings.EnableApple)
            return AuthResult.Failure("oauth_disabled", "Apple authentication is not enabled");

        if (string.IsNullOrEmpty(request.IdToken))
            return AuthResult.Failure("invalid_request", "ID token is required");

        var oauthResult = await _oauthService.ValidateAppleIdTokenAsync(request.IdToken, request.AuthCode);

        if (!oauthResult.Success || oauthResult.Profile is null)
        {
            _auditLogger.LogLogin("apple_user", request.IpAddress ?? "unknown", false,
                oauthResult.Error ?? "OAuth failed");
            return AuthResult.Failure(oauthResult.Error ?? "oauth_failed", oauthResult.ErrorDescription);
        }

        return await HandleOAuthProfileAsync(oauthResult.Profile, request);
    }

    #endregion

    #region Discord Authentication

    private async Task<AuthResult> AuthenticateWithDiscordAsync(AuthRequest request)
    {
        if (!_oauthSettings.EnableDiscord)
            return AuthResult.Failure("oauth_disabled", "Discord authentication is not enabled");

        if (string.IsNullOrEmpty(request.AuthCode))
            return AuthResult.Failure("invalid_request", "Authorization code is required");

        var oauthResult = await _oauthService.AuthenticateDiscordAsync(request.AuthCode);

        if (!oauthResult.Success || oauthResult.Profile is null)
        {
            _auditLogger.LogLogin("discord_user", request.IpAddress ?? "unknown", false,
                oauthResult.Error ?? "OAuth failed");
            return AuthResult.Failure(oauthResult.Error ?? "oauth_failed", oauthResult.ErrorDescription);
        }

        return await HandleOAuthProfileAsync(oauthResult.Profile, request);
    }

    #endregion

    #region OAuth Account Handling

    private async Task<AuthResult> HandleOAuthProfileAsync(OAuthProfile profile, AuthRequest request)
    {
        // Check if this OAuth account is already linked
        var existingUsername = GetLinkedUsername(profile.Provider, profile.ProviderId);

        if (existingUsername is not null)
        {
            // Existing linked account - create tokens
            var tokens = await _refreshTokenManager.CreateTokenPairAsync(
                existingUsername,
                request.DeviceId,
                request.DeviceName,
                request.Platform,
                request.IpAddress);

            _auditLogger.LogLogin(existingUsername, request.IpAddress ?? "unknown", true,
                $"via {profile.Provider}");

            return new AuthResult
            {
                Success = true,
                Username = existingUsername,
                AccessToken = tokens.AccessToken,
                RefreshToken = tokens.RefreshToken,
                ExpiresIn = tokens.ExpiresIn
            };
        }

        // New OAuth user - check if we should auto-create account
        if (_oauthSettings.AutoGenerateUsername)
        {
            var suggestedUsername = OAuthService.GenerateUsername(profile);

            // Ensure username is unique
            while (await _playerRepository.PlayerExistsAsync(suggestedUsername))
            {
                suggestedUsername = OAuthService.GenerateUsername(profile);
            }

            // Create new account
            var newPlayer = new PlayerData
            {
                Username = suggestedUsername,
                Email = profile.Email,
                X = 120,
                Y = 648,
                CombatLevel = 3
            };

            await _playerRepository.SavePlayerAsync(newPlayer);

            // Link OAuth account
            LinkOAuthAccount(suggestedUsername, profile);

            // Create tokens
            var tokens = await _refreshTokenManager.CreateTokenPairAsync(
                suggestedUsername,
                request.DeviceId,
                request.DeviceName,
                request.Platform,
                request.IpAddress);

            _auditLogger.Log(new SecurityAuditEvent
            {
                EventType = SecurityEventType.AccountCreated,
                Severity = SecurityEventSeverity.Info,
                Username = suggestedUsername,
                IpAddress = request.IpAddress,
                Success = true,
                Message = $"Account created via {profile.Provider} OAuth"
            });

            return new AuthResult
            {
                Success = true,
                Username = suggestedUsername,
                IsNewAccount = true,
                AccessToken = tokens.AccessToken,
                RefreshToken = tokens.RefreshToken,
                ExpiresIn = tokens.ExpiresIn
            };
        }

        // Require username selection
        return new AuthResult
        {
            Success = false,
            RequiresUsername = true,
            SuggestedUsername = OAuthService.GenerateUsername(profile),
            OAuthProfile = profile,
            Error = "username_required",
            ErrorDescription = "Please choose a username for your account"
        };
    }

    /// <summary>
    /// Links an OAuth account to an existing user.
    /// </summary>
    public void LinkOAuthAccount(string username, OAuthProfile profile)
    {
        var key = username.ToLowerInvariant();

        var link = new OAuthAccountLink
        {
            Username = username,
            Provider = profile.Provider,
            ProviderId = profile.ProviderId,
            Email = profile.Email
        };

        if (!_oauthLinks.ContainsKey(key))
        {
            _oauthLinks[key] = [];
        }

        _oauthLinks[key].Add(link);
        _oauthToUsername[(profile.Provider, profile.ProviderId)] = username;

        _logger.LogInformation("Linked {Provider} account to user {Username}", profile.Provider, username);
    }

    /// <summary>
    /// Gets the username linked to an OAuth account.
    /// </summary>
    public string? GetLinkedUsername(OAuthProvider provider, string providerId)
    {
        return _oauthToUsername.TryGetValue((provider, providerId), out var username) ? username : null;
    }

    /// <summary>
    /// Gets all OAuth accounts linked to a user.
    /// </summary>
    public List<OAuthAccountLink> GetLinkedAccounts(string username)
    {
        var key = username.ToLowerInvariant();
        return _oauthLinks.TryGetValue(key, out var links) ? links : [];
    }

    /// <summary>
    /// Unlinks an OAuth account from a user.
    /// </summary>
    public bool UnlinkOAuthAccount(string username, OAuthProvider provider)
    {
        var key = username.ToLowerInvariant();

        if (!_oauthLinks.TryGetValue(key, out var links))
            return false;

        var link = links.FirstOrDefault(l => l.Provider == provider);
        if (link is null)
            return false;

        links.Remove(link);
        _oauthToUsername.Remove((provider, link.ProviderId));

        _logger.LogInformation("Unlinked {Provider} account from user {Username}", provider, username);
        return true;
    }

    #endregion

    #region Password Management

    /// <summary>
    /// Changes a user's password.
    /// </summary>
    public async Task<bool> ChangePasswordAsync(string username, string currentPassword, string newPassword, string? ipAddress = null)
    {
        var player = await _playerRepository.LoadPlayerAsync(username);
        if (player is null)
            return false;

        // Verify current password
        if (!string.IsNullOrEmpty(player.PasswordHash) &&
            !PasswordHasher.VerifyPassword(currentPassword, player.PasswordHash))
        {
            _auditLogger.LogPasswordChange(username, ipAddress ?? "unknown", false);
            return false;
        }

        // Validate new password
        var validation = PasswordHasher.ValidatePassword(newPassword, PasswordPolicy.Secure, username);
        if (!validation.IsValid)
        {
            _logger.LogWarning("Password change rejected for {Username}: {Errors}",
                username, string.Join(", ", validation.Errors));
            return false;
        }

        // Update password
        player.PasswordHash = PasswordHasher.HashPassword(newPassword);
        await _playerRepository.SavePlayerAsync(player);

        // Revoke all tokens if configured
        if (_tokenSettings.RevokeTokensOnPasswordChange)
        {
            await _refreshTokenManager.RevokeAllUserTokensAsync(username, "Password changed");
        }

        _auditLogger.LogPasswordChange(username, ipAddress ?? "unknown", true);
        _logger.LogInformation("Password changed for {Username}", username);

        return true;
    }

    /// <summary>
    /// Sets a password for an OAuth-only account.
    /// </summary>
    public async Task<bool> SetPasswordAsync(string username, string newPassword, string? ipAddress = null)
    {
        var player = await _playerRepository.LoadPlayerAsync(username);
        if (player is null)
            return false;

        // Only allow if no password is set
        if (!string.IsNullOrEmpty(player.PasswordHash))
        {
            _logger.LogWarning("Attempted to set password on account that already has one: {Username}", username);
            return false;
        }

        // Validate password
        var validation = PasswordHasher.ValidatePassword(newPassword, PasswordPolicy.Secure, username);
        if (!validation.IsValid)
            return false;

        player.PasswordHash = PasswordHasher.HashPassword(newPassword);
        await _playerRepository.SavePlayerAsync(player);

        _auditLogger.LogPasswordChange(username, ipAddress ?? "unknown", true);
        return true;
    }

    #endregion
}
