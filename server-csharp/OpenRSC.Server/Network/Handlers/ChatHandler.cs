using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Services;

namespace OpenRSC.Server.Network.Handlers;

/// <summary>
/// Handles chat-related packets.
/// </summary>
public sealed class ChatHandler : IPacketHandler
{
    private readonly ILogger<ChatHandler> _logger;
    private readonly WorldService _worldService;

    // View distance for public chat
    private const int ChatRadius = 15;

    public int[] Opcodes => new[]
    {
        (int)OpcodeIn.PublicChat,
        (int)OpcodeIn.PrivateMessage
    };

    public ChatHandler(
        ILogger<ChatHandler> logger,
        WorldService worldService)
    {
        _logger = logger;
        _worldService = worldService;
    }

    public async Task HandleAsync(GameClient client, Packet packet)
    {
        var player = client.Player;
        if (player is null || !player.IsLoggedIn)
            return;

        switch ((OpcodeIn)packet.Opcode)
        {
            case OpcodeIn.PublicChat:
                await HandlePublicChatAsync(player, packet);
                break;
            case OpcodeIn.PrivateMessage:
                await HandlePrivateMessageAsync(player, packet);
                break;
        }
    }

    private async Task HandlePublicChatAsync(Player player, Packet packet)
    {
        var message = packet.ReadString();

        // Validate message
        if (string.IsNullOrWhiteSpace(message))
            return;

        // Limit message length
        if (message.Length > 80)
            message = message[..80];

        // Check if player is muted
        if (player.IsMuted)
        {
            player.Message("You are muted and cannot chat.");
            return;
        }

        _logger.LogDebug("[Chat] {Username}: {Message}", player.Username, message);

        // Broadcast to nearby players
        var nearbyPlayers = _worldService.GetPlayersInRange(player.Location, ChatRadius);

        foreach (var nearbyPlayer in nearbyPlayers)
        {
            if (nearbyPlayer == player)
                continue;

            // Check privacy settings
            if (nearbyPlayer.PrivacySettings.PublicChat == PrivacyChatMode.Off)
                continue;

            if (nearbyPlayer.PrivacySettings.PublicChat == PrivacyChatMode.Friends &&
                !nearbyPlayer.Social?.IsFriend(player.UsernameHash) == true)
                continue;

            // Send chat message
            await SendPublicChatAsync(nearbyPlayer, player, message);
        }

        await Task.CompletedTask;
    }

    private async Task HandlePrivateMessageAsync(Player player, Packet packet)
    {
        var recipientHash = packet.ReadLong();
        var message = packet.ReadString();

        // Validate message
        if (string.IsNullOrWhiteSpace(message))
            return;

        // Limit message length
        if (message.Length > 80)
            message = message[..80];

        // Check if player is muted
        if (player.IsMuted)
        {
            player.Message("You are muted and cannot send messages.");
            return;
        }

        // Find recipient
        var recipient = _worldService.GetPlayer(recipientHash);

        if (recipient is null)
        {
            player.Message("That player is not online.");
            return;
        }

        // Check if recipient is ignoring sender
        if (recipient.Social?.IsIgnored(player.UsernameHash) == true)
        {
            player.Message("That player is not accepting messages.");
            return;
        }

        // Check recipient's privacy settings
        if (recipient.PrivacySettings.PrivateChat == PrivacyChatMode.Off)
        {
            player.Message("That player has private chat disabled.");
            return;
        }

        if (recipient.PrivacySettings.PrivateChat == PrivacyChatMode.Friends &&
            !recipient.Social?.IsFriend(player.UsernameHash) == true)
        {
            player.Message("That player is only accepting messages from friends.");
            return;
        }

        // Send the private message
        await SendPrivateMessageAsync(recipient, player, message);

        // Confirm to sender
        await SendPrivateMessageSentAsync(player, recipientHash, message);

        _logger.LogDebug("[PM] {Sender} -> {Recipient}: {Message}",
            player.Username, recipient.Username, message);
    }

    private static async Task SendPublicChatAsync(Player recipient, Player sender, string message)
    {
        using var packet = new Packet((byte)OpcodeOut.Message);
        packet.WriteShort((short)sender.Index);
        packet.WriteString(sender.Username);
        packet.WriteString(message);

        await (recipient.ActionSender?.SendPacketAsync(packet) ?? Task.CompletedTask);
    }

    private static async Task SendPrivateMessageAsync(Player recipient, Player sender, string message)
    {
        using var packet = new Packet((byte)OpcodeOut.PrivateMessageReceived);
        packet.WriteLong(sender.UsernameHash);
        packet.WriteString(message);

        await (recipient.ActionSender?.SendPacketAsync(packet) ?? Task.CompletedTask);
    }

    private static async Task SendPrivateMessageSentAsync(Player sender, long recipientHash, string message)
    {
        using var packet = new Packet((byte)OpcodeOut.PrivateMessageSent);
        packet.WriteLong(recipientHash);
        packet.WriteString(message);

        await (sender.ActionSender?.SendPacketAsync(packet) ?? Task.CompletedTask);
    }
}

/// <summary>
/// Privacy chat mode settings.
/// </summary>
public enum PrivacyChatMode
{
    On = 0,
    Friends = 1,
    Off = 2
}
