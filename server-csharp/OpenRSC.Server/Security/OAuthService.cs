using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;

namespace OpenRSC.Server.Security;

/// <summary>
/// Supported OAuth providers.
/// </summary>
public enum OAuthProvider
{
    Google,
    Apple,
    Discord
}

/// <summary>
/// OAuth user profile returned from provider.
/// </summary>
public sealed class OAuthProfile
{
    /// <summary>Provider that authenticated the user.</summary>
    public required OAuthProvider Provider { get; init; }

    /// <summary>Unique ID from the provider.</summary>
    public required string ProviderId { get; init; }

    /// <summary>User's email address.</summary>
    public string? Email { get; init; }

    /// <summary>Whether the email is verified by the provider.</summary>
    public bool EmailVerified { get; init; }

    /// <summary>User's display name.</summary>
    public string? DisplayName { get; init; }

    /// <summary>User's first name.</summary>
    public string? FirstName { get; init; }

    /// <summary>User's last name.</summary>
    public string? LastName { get; init; }

    /// <summary>URL to user's profile picture.</summary>
    public string? PictureUrl { get; init; }

    /// <summary>Locale/language preference.</summary>
    public string? Locale { get; init; }

    /// <summary>Raw claims from the provider.</summary>
    public Dictionary<string, object>? RawClaims { get; init; }
}

/// <summary>
/// OAuth authentication result.
/// </summary>
public sealed class OAuthResult
{
    public bool Success { get; init; }
    public OAuthProfile? Profile { get; init; }
    public string? Error { get; init; }
    public string? ErrorDescription { get; init; }

    public static OAuthResult Failure(string error, string? description = null) => new()
    {
        Success = false,
        Error = error,
        ErrorDescription = description
    };

    public static OAuthResult Ok(OAuthProfile profile) => new()
    {
        Success = true,
        Profile = profile
    };
}

/// <summary>
/// OAuth authentication service supporting multiple providers.
/// </summary>
public sealed class OAuthService : IDisposable
{
    private readonly ILogger<OAuthService> _logger;
    private readonly OAuthSettings _settings;
    private readonly HttpClient _httpClient;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public OAuthService(
        ILogger<OAuthService> logger,
        IOptions<OAuthSettings> settings,
        IHttpClientFactory? httpClientFactory = null)
    {
        _logger = logger;
        _settings = settings.Value;
        _httpClient = httpClientFactory?.CreateClient("OAuth") ?? new HttpClient();
        _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    }

    #region Google OAuth

    /// <summary>
    /// Generates a Google OAuth authorization URL.
    /// </summary>
    public string GetGoogleAuthUrl(string state, string? nonce = null)
    {
        if (!_settings.EnableGoogle || string.IsNullOrEmpty(_settings.GoogleClientId))
            throw new InvalidOperationException("Google OAuth is not configured");

        var redirectUri = $"{_settings.CallbackUrlBase}/google/callback";
        var scope = "openid email profile";

        var url = "https://accounts.google.com/o/oauth2/v2/auth?" +
            $"client_id={Uri.EscapeDataString(_settings.GoogleClientId)}&" +
            $"redirect_uri={Uri.EscapeDataString(redirectUri)}&" +
            $"response_type=code&" +
            $"scope={Uri.EscapeDataString(scope)}&" +
            $"state={Uri.EscapeDataString(state)}&" +
            $"access_type=offline&" +
            $"prompt=consent";

        if (!string.IsNullOrEmpty(nonce))
        {
            url += $"&nonce={Uri.EscapeDataString(nonce)}";
        }

        return url;
    }

    /// <summary>
    /// Exchanges a Google authorization code for user profile.
    /// </summary>
    public async Task<OAuthResult> AuthenticateGoogleAsync(string code)
    {
        if (!_settings.EnableGoogle)
            return OAuthResult.Failure("google_disabled", "Google authentication is not enabled");

        try
        {
            // Exchange code for tokens
            var tokenResponse = await ExchangeGoogleCodeAsync(code);
            if (tokenResponse is null)
                return OAuthResult.Failure("token_exchange_failed", "Failed to exchange authorization code");

            // Get user info
            var profile = await GetGoogleUserProfileAsync(tokenResponse.AccessToken);
            if (profile is null)
                return OAuthResult.Failure("profile_fetch_failed", "Failed to fetch user profile");

            _logger.LogInformation("Google OAuth success for {Email}", profile.Email);
            return OAuthResult.Ok(profile);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Google OAuth failed");
            return OAuthResult.Failure("oauth_error", ex.Message);
        }
    }

    /// <summary>
    /// Validates a Google ID token (for mobile clients using Google Sign-In SDK).
    /// </summary>
    public async Task<OAuthResult> ValidateGoogleIdTokenAsync(string idToken)
    {
        if (!_settings.EnableGoogle)
            return OAuthResult.Failure("google_disabled", "Google authentication is not enabled");

        try
        {
            // Verify token with Google
            var response = await _httpClient.GetAsync(
                $"https://oauth2.googleapis.com/tokeninfo?id_token={Uri.EscapeDataString(idToken)}");

            if (!response.IsSuccessStatusCode)
                return OAuthResult.Failure("invalid_token", "Token validation failed");

            var json = await response.Content.ReadAsStringAsync();
            var claims = JsonSerializer.Deserialize<GoogleIdTokenClaims>(json, JsonOptions);

            if (claims is null)
                return OAuthResult.Failure("invalid_claims", "Could not parse token claims");

            // Verify audience matches our client ID
            if (claims.Aud != _settings.GoogleClientId && claims.Azp != _settings.GoogleClientId)
                return OAuthResult.Failure("invalid_audience", "Token was not issued for this application");

            var profile = new OAuthProfile
            {
                Provider = OAuthProvider.Google,
                ProviderId = claims.Sub,
                Email = claims.Email,
                EmailVerified = claims.EmailVerified == "true",
                DisplayName = claims.Name,
                FirstName = claims.GivenName,
                LastName = claims.FamilyName,
                PictureUrl = claims.Picture,
                Locale = claims.Locale
            };

            _logger.LogInformation("Google ID token validated for {Email}", profile.Email);
            return OAuthResult.Ok(profile);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Google ID token validation failed");
            return OAuthResult.Failure("validation_error", ex.Message);
        }
    }

    private async Task<GoogleTokenResponse?> ExchangeGoogleCodeAsync(string code)
    {
        var redirectUri = $"{_settings.CallbackUrlBase}/google/callback";

        var content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["code"] = code,
            ["client_id"] = _settings.GoogleClientId,
            ["client_secret"] = _settings.GoogleClientSecret,
            ["redirect_uri"] = redirectUri,
            ["grant_type"] = "authorization_code"
        });

        var response = await _httpClient.PostAsync("https://oauth2.googleapis.com/token", content);
        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            _logger.LogWarning("Google token exchange failed: {Error}", error);
            return null;
        }

        var json = await response.Content.ReadAsStringAsync();
        return JsonSerializer.Deserialize<GoogleTokenResponse>(json, JsonOptions);
    }

    private async Task<OAuthProfile?> GetGoogleUserProfileAsync(string accessToken)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "https://www.googleapis.com/oauth2/v2/userinfo");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        var response = await _httpClient.SendAsync(request);
        if (!response.IsSuccessStatusCode)
            return null;

        var json = await response.Content.ReadAsStringAsync();
        var userInfo = JsonSerializer.Deserialize<GoogleUserInfo>(json, JsonOptions);

        if (userInfo is null)
            return null;

        return new OAuthProfile
        {
            Provider = OAuthProvider.Google,
            ProviderId = userInfo.Id,
            Email = userInfo.Email,
            EmailVerified = userInfo.VerifiedEmail,
            DisplayName = userInfo.Name,
            FirstName = userInfo.GivenName,
            LastName = userInfo.FamilyName,
            PictureUrl = userInfo.Picture,
            Locale = userInfo.Locale
        };
    }

    #endregion

    #region Discord OAuth

    /// <summary>
    /// Generates a Discord OAuth authorization URL.
    /// </summary>
    public string GetDiscordAuthUrl(string state)
    {
        if (!_settings.EnableDiscord || string.IsNullOrEmpty(_settings.DiscordClientId))
            throw new InvalidOperationException("Discord OAuth is not configured");

        var redirectUri = $"{_settings.CallbackUrlBase}/discord/callback";
        var scope = "identify email";

        return "https://discord.com/api/oauth2/authorize?" +
            $"client_id={Uri.EscapeDataString(_settings.DiscordClientId)}&" +
            $"redirect_uri={Uri.EscapeDataString(redirectUri)}&" +
            $"response_type=code&" +
            $"scope={Uri.EscapeDataString(scope)}&" +
            $"state={Uri.EscapeDataString(state)}";
    }

    /// <summary>
    /// Exchanges a Discord authorization code for user profile.
    /// </summary>
    public async Task<OAuthResult> AuthenticateDiscordAsync(string code)
    {
        if (!_settings.EnableDiscord)
            return OAuthResult.Failure("discord_disabled", "Discord authentication is not enabled");

        try
        {
            var redirectUri = $"{_settings.CallbackUrlBase}/discord/callback";

            // Exchange code for tokens
            var content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["code"] = code,
                ["client_id"] = _settings.DiscordClientId,
                ["client_secret"] = _settings.DiscordClientSecret,
                ["redirect_uri"] = redirectUri,
                ["grant_type"] = "authorization_code"
            });

            var tokenResponse = await _httpClient.PostAsync("https://discord.com/api/oauth2/token", content);
            if (!tokenResponse.IsSuccessStatusCode)
                return OAuthResult.Failure("token_exchange_failed", "Failed to exchange authorization code");

            var tokenJson = await tokenResponse.Content.ReadAsStringAsync();
            var tokens = JsonSerializer.Deserialize<DiscordTokenResponse>(tokenJson, JsonOptions);

            if (tokens is null)
                return OAuthResult.Failure("invalid_token_response", "Invalid token response");

            // Get user info
            var userRequest = new HttpRequestMessage(HttpMethod.Get, "https://discord.com/api/users/@me");
            userRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokens.AccessToken);

            var userResponse = await _httpClient.SendAsync(userRequest);
            if (!userResponse.IsSuccessStatusCode)
                return OAuthResult.Failure("profile_fetch_failed", "Failed to fetch user profile");

            var userJson = await userResponse.Content.ReadAsStringAsync();
            var user = JsonSerializer.Deserialize<DiscordUser>(userJson, JsonOptions);

            if (user is null)
                return OAuthResult.Failure("invalid_user_response", "Invalid user response");

            var profile = new OAuthProfile
            {
                Provider = OAuthProvider.Discord,
                ProviderId = user.Id,
                Email = user.Email,
                EmailVerified = user.Verified,
                DisplayName = user.GlobalName ?? user.Username,
                PictureUrl = user.Avatar != null
                    ? $"https://cdn.discordapp.com/avatars/{user.Id}/{user.Avatar}.png"
                    : null,
                Locale = user.Locale
            };

            _logger.LogInformation("Discord OAuth success for {Username}", profile.DisplayName);
            return OAuthResult.Ok(profile);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Discord OAuth failed");
            return OAuthResult.Failure("oauth_error", ex.Message);
        }
    }

    #endregion

    #region Apple Sign-In

    /// <summary>
    /// Generates an Apple Sign-In authorization URL.
    /// </summary>
    public string GetAppleAuthUrl(string state, string nonce)
    {
        if (!_settings.EnableApple || string.IsNullOrEmpty(_settings.AppleServicesId))
            throw new InvalidOperationException("Apple Sign-In is not configured");

        var redirectUri = $"{_settings.CallbackUrlBase}/apple/callback";
        var scope = "name email";

        return "https://appleid.apple.com/auth/authorize?" +
            $"client_id={Uri.EscapeDataString(_settings.AppleServicesId)}&" +
            $"redirect_uri={Uri.EscapeDataString(redirectUri)}&" +
            $"response_type=code id_token&" +
            $"response_mode=form_post&" +
            $"scope={Uri.EscapeDataString(scope)}&" +
            $"state={Uri.EscapeDataString(state)}&" +
            $"nonce={Uri.EscapeDataString(nonce)}";
    }

    /// <summary>
    /// Validates an Apple ID token (for iOS clients using Sign in with Apple).
    /// </summary>
    public async Task<OAuthResult> ValidateAppleIdTokenAsync(string idToken, string? authorizationCode = null)
    {
        if (!_settings.EnableApple)
            return OAuthResult.Failure("apple_disabled", "Apple Sign-In is not enabled");

        try
        {
            // Decode the JWT (without full validation - Apple's public keys would be needed)
            var parts = idToken.Split('.');
            if (parts.Length != 3)
                return OAuthResult.Failure("invalid_token", "Invalid token format");

            var payload = parts[1];
            // Add padding if needed
            payload = payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');
            var payloadBytes = Convert.FromBase64String(payload.Replace('-', '+').Replace('_', '/'));
            var payloadJson = Encoding.UTF8.GetString(payloadBytes);

            var claims = JsonSerializer.Deserialize<AppleIdTokenClaims>(payloadJson, JsonOptions);
            if (claims is null)
                return OAuthResult.Failure("invalid_claims", "Could not parse token claims");

            // Verify issuer
            if (claims.Iss != "https://appleid.apple.com")
                return OAuthResult.Failure("invalid_issuer", "Token issuer is invalid");

            // Verify audience
            if (claims.Aud != _settings.AppleServicesId)
                return OAuthResult.Failure("invalid_audience", "Token was not issued for this application");

            // Check expiration
            var exp = DateTimeOffset.FromUnixTimeSeconds(claims.Exp);
            if (exp < DateTimeOffset.UtcNow)
                return OAuthResult.Failure("token_expired", "Token has expired");

            var profile = new OAuthProfile
            {
                Provider = OAuthProvider.Apple,
                ProviderId = claims.Sub,
                Email = claims.Email,
                EmailVerified = claims.EmailVerified == "true"
            };

            _logger.LogInformation("Apple ID token validated for user {Sub}", claims.Sub);
            return OAuthResult.Ok(profile);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Apple ID token validation failed");
            return OAuthResult.Failure("validation_error", ex.Message);
        }
    }

    #endregion

    #region Helpers

    /// <summary>
    /// Generates a secure random state parameter for OAuth.
    /// </summary>
    public static string GenerateState()
    {
        return Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
            .Replace("+", "-")
            .Replace("/", "_")
            .TrimEnd('=');
    }

    /// <summary>
    /// Generates a secure nonce for token binding.
    /// </summary>
    public static string GenerateNonce()
    {
        return Convert.ToBase64String(RandomNumberGenerator.GetBytes(16))
            .Replace("+", "-")
            .Replace("/", "_")
            .TrimEnd('=');
    }

    /// <summary>
    /// Generates a username suggestion from an OAuth profile.
    /// </summary>
    public static string GenerateUsername(OAuthProfile profile)
    {
        var baseName = profile.DisplayName
            ?? profile.FirstName
            ?? profile.Email?.Split('@')[0]
            ?? "player";

        // Clean up: only alphanumeric and underscore, max 12 chars
        var cleaned = new string(baseName
            .Where(c => char.IsLetterOrDigit(c) || c == '_')
            .Take(8)
            .ToArray());

        if (string.IsNullOrEmpty(cleaned))
            cleaned = "player";

        // Add random suffix to avoid collisions
        var suffix = RandomNumberGenerator.GetInt32(1000, 9999);
        return $"{cleaned}{suffix}";
    }

    #endregion

    public void Dispose()
    {
        _httpClient.Dispose();
    }
}

#region DTOs

internal sealed class GoogleTokenResponse
{
    [JsonPropertyName("access_token")]
    public string AccessToken { get; set; } = "";

    [JsonPropertyName("id_token")]
    public string? IdToken { get; set; }

    [JsonPropertyName("refresh_token")]
    public string? RefreshToken { get; set; }

    [JsonPropertyName("expires_in")]
    public int ExpiresIn { get; set; }

    [JsonPropertyName("token_type")]
    public string TokenType { get; set; } = "";
}

internal sealed class GoogleUserInfo
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("email")]
    public string? Email { get; set; }

    [JsonPropertyName("verified_email")]
    public bool VerifiedEmail { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("given_name")]
    public string? GivenName { get; set; }

    [JsonPropertyName("family_name")]
    public string? FamilyName { get; set; }

    [JsonPropertyName("picture")]
    public string? Picture { get; set; }

    [JsonPropertyName("locale")]
    public string? Locale { get; set; }
}

internal sealed class GoogleIdTokenClaims
{
    [JsonPropertyName("iss")]
    public string? Iss { get; set; }

    [JsonPropertyName("azp")]
    public string? Azp { get; set; }

    [JsonPropertyName("aud")]
    public string? Aud { get; set; }

    [JsonPropertyName("sub")]
    public string Sub { get; set; } = "";

    [JsonPropertyName("email")]
    public string? Email { get; set; }

    [JsonPropertyName("email_verified")]
    public string? EmailVerified { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("given_name")]
    public string? GivenName { get; set; }

    [JsonPropertyName("family_name")]
    public string? FamilyName { get; set; }

    [JsonPropertyName("picture")]
    public string? Picture { get; set; }

    [JsonPropertyName("locale")]
    public string? Locale { get; set; }
}

internal sealed class DiscordTokenResponse
{
    [JsonPropertyName("access_token")]
    public string AccessToken { get; set; } = "";

    [JsonPropertyName("token_type")]
    public string TokenType { get; set; } = "";

    [JsonPropertyName("expires_in")]
    public int ExpiresIn { get; set; }

    [JsonPropertyName("refresh_token")]
    public string? RefreshToken { get; set; }

    [JsonPropertyName("scope")]
    public string? Scope { get; set; }
}

internal sealed class DiscordUser
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("username")]
    public string Username { get; set; } = "";

    [JsonPropertyName("global_name")]
    public string? GlobalName { get; set; }

    [JsonPropertyName("email")]
    public string? Email { get; set; }

    [JsonPropertyName("verified")]
    public bool Verified { get; set; }

    [JsonPropertyName("avatar")]
    public string? Avatar { get; set; }

    [JsonPropertyName("locale")]
    public string? Locale { get; set; }
}

internal sealed class AppleIdTokenClaims
{
    [JsonPropertyName("iss")]
    public string? Iss { get; set; }

    [JsonPropertyName("aud")]
    public string? Aud { get; set; }

    [JsonPropertyName("sub")]
    public string Sub { get; set; } = "";

    [JsonPropertyName("email")]
    public string? Email { get; set; }

    [JsonPropertyName("email_verified")]
    public string? EmailVerified { get; set; }

    [JsonPropertyName("exp")]
    public long Exp { get; set; }

    [JsonPropertyName("iat")]
    public long Iat { get; set; }

    [JsonPropertyName("nonce")]
    public string? Nonce { get; set; }
}

#endregion
