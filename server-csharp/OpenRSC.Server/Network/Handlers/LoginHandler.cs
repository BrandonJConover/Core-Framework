using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Security;
using OpenRSC.Server.Services;

namespace OpenRSC.Server.Network.Handlers;

/// <summary>
/// Handles login-related packets.
/// </summary>
[PacketHandlerClass]
public sealed class LoginHandler
{
    private readonly ILogger<LoginHandler> _logger;
    private readonly IWorldService _worldService;
    private readonly IPlayerRepository _playerRepository;
    private readonly ServerSettings _serverSettings;
    private readonly ActionRetrySettings _actionRetrySettings;
    private readonly IOptions<ServerSettings> _serverSettingsOptions;
    private readonly IOptions<ActionRetrySettings> _actionRetryOptions;
    private readonly AccountLockoutManager _lockoutManager;

    public LoginHandler(
        ILogger<LoginHandler> logger,
        IWorldService worldService,
        IPlayerRepository playerRepository,
        IOptions<ServerSettings> serverSettings,
        IOptions<ActionRetrySettings> actionRetrySettings,
        AccountLockoutManager lockoutManager)
    {
        _logger = logger;
        _worldService = worldService;
        _playerRepository = playerRepository;
        _serverSettings = serverSettings.Value;
        _actionRetrySettings = actionRetrySettings.Value;
        _serverSettingsOptions = serverSettings;
        _actionRetryOptions = actionRetrySettings;
        _lockoutManager = lockoutManager;
    }

    [PacketHandler(OpcodeIn.Login)]
    public async Task HandleLogin(GameClient client, Packet packet)
    {
        // Read login data
        var reconnecting = packet.ReadByte() == 1;
        var clientVersion = packet.ReadShort();
        var username = packet.ReadString().Trim().ToLowerInvariant();
        var password = packet.ReadString();

        _logger.LogInformation("Login attempt: {Username} (v{Version}, reconnect={Reconnect})",
            username, clientVersion, reconnecting);

        // Validate username format
        if (string.IsNullOrEmpty(username) || username.Length < 2 || username.Length > 12)
        {
            await SendLoginResponse(client, LoginResponse.InvalidCredentials);
            return;
        }

        // Check for account lockout (brute-force protection)
        if (_lockoutManager.IsLockedOut(username))
        {
            var remaining = _lockoutManager.GetRemainingLockoutTime(username);
            _logger.LogWarning("Login blocked for locked account: {Username} (remaining: {Remaining})",
                username, remaining);
            await SendLoginResponse(client, LoginResponse.AccountLocked);
            return;
        }

        // Check if already logged in
        var existingPlayer = _worldService.GetPlayer(username);
        if (existingPlayer != null)
        {
            await SendLoginResponse(client, LoginResponse.AlreadyLoggedIn);
            return;
        }

        // Load or create player
        var playerData = await _playerRepository.LoadPlayerAsync(username);
        var isNewPlayer = playerData == null;

        if (isNewPlayer)
        {
            // Create new player with hashed password
            playerData = new PlayerData
            {
                Username = username,
                PasswordHash = PasswordHasher.HashPassword(password),
                X = 120,
                Y = 648, // Lumbridge spawn
                CombatLevel = 3
            };
            await _playerRepository.SavePlayerAsync(playerData);
            _logger.LogInformation("Created new player account: {Username}", username);
        }
        else
        {
            // Verify password against stored hash
            if (!string.IsNullOrEmpty(playerData.PasswordHash) &&
                !PasswordHasher.VerifyPassword(password, playerData.PasswordHash))
            {
                var isLockedOut = _lockoutManager.RecordFailedAttempt(username);
                _logger.LogWarning("Failed login attempt for: {Username} (locked: {Locked})",
                    username, isLockedOut);
                await SendLoginResponse(client, LoginResponse.InvalidCredentials);
                return;
            }

            // Check if password hash needs upgrade (e.g., iterations increased)
            if (!string.IsNullOrEmpty(playerData.PasswordHash) &&
                PasswordHasher.NeedsRehash(playerData.PasswordHash))
            {
                playerData.PasswordHash = PasswordHasher.HashPassword(password);
                await _playerRepository.SavePlayerAsync(playerData);
                _logger.LogInformation("Upgraded password hash for: {Username}", username);
            }
        }

        // Clear any previous lockout on successful login
        _lockoutManager.ClearLockout(username);

        // Create player entity
        var player = new Player(
            username,
            new Models.Point(playerData.X, playerData.Y),
            _serverSettingsOptions,
            _actionRetryOptions);

        // Register in world
        if (!_worldService.RegisterPlayer(player))
        {
            await SendLoginResponse(client, LoginResponse.WorldFull);
            return;
        }

        // Associate player with client
        client.Player = player;
        player.Login();

        // Send success response
        await SendLoginResponse(client, LoginResponse.Success);

        // Send initial state
        await SendInitialState(client, player);

        _logger.LogInformation("Player {Username} logged in successfully", username);
    }

    [PacketHandler(OpcodeIn.Logout)]
    public async Task HandleLogout(GameClient client, Packet packet)
    {
        if (client.Player == null)
        {
            await client.SendAsync(PacketBuilder.Logout());
            return;
        }

        var player = client.Player;

        // Check if player can logout (not in combat, etc.)
        if (player.InCombat)
        {
            using var denyPacket = new Packet((byte)OpcodeOut.LogoutDeny);
            await client.SendAsync(denyPacket);
            return;
        }

        // Save player data
        await SavePlayerAsync(player);

        // Unregister from world
        _worldService.UnregisterPlayer(player);
        player.Logout();
        client.Player = null;

        // Send logout confirmation
        await client.SendAsync(PacketBuilder.Logout());

        _logger.LogInformation("Player {Username} logged out", player.Username);
    }

    private async Task SendLoginResponse(GameClient client, LoginResponse response)
    {
        using var packet = new Packet((byte)OpcodeOut.WorldInfo);
        packet.WriteByte((byte)response);

        if (response == LoginResponse.Success)
        {
            packet.WriteShort((short)client.Player!.Index);
            packet.WriteByte((byte)(_serverSettings.MembersWorld ? 1 : 0));
        }

        await client.SendAsync(packet);
    }

    private async Task SendInitialState(GameClient client, Player player)
    {
        // Send player stats, inventory, etc.
        // This is simplified - full implementation would send all player state

        // Send welcome message
        await client.SendAsync(PacketBuilder.ServerMessage(_serverSettings.WelcomeText));
    }

    private async Task SavePlayerAsync(Player player)
    {
        var data = new PlayerData
        {
            Username = player.Username,
            X = player.Location.X,
            Y = player.Location.Y,
            CombatLevel = player.CombatLevel
        };

        await _playerRepository.SavePlayerAsync(data);
    }
}

/// <summary>
/// Login response codes.
/// </summary>
public enum LoginResponse : byte
{
    Success = 0,
    InvalidCredentials = 1,
    AlreadyLoggedIn = 2,
    UpdateRequired = 3,
    WorldFull = 4,
    LoginServerDown = 5,
    Banned = 6,
    AccountLocked = 7
}
