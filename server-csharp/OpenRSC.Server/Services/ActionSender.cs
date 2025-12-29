using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Network;
using OpenRSC.Server.Skills;

namespace OpenRSC.Server.Services;

/// <summary>
/// Sends packets to players. Provides a high-level API for client communication.
/// </summary>
public sealed class ActionSender
{
    private readonly GameClient _client;
    private readonly Player _player;

    public ActionSender(GameClient client, Player player)
    {
        _client = client;
        _player = player;
    }

    /// <summary>
    /// Sends a server message to the player's chat.
    /// </summary>
    public async Task SendMessageAsync(string message)
    {
        if (!_client.IsConnected) return;

        using var packet = PacketBuilder.ServerMessage(message);
        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends a private message to the player.
    /// </summary>
    public async Task SendPrivateMessageAsync(long senderHash, string message)
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.PrivateMessageReceived);
        packet.WriteLong(senderHash);
        packet.WriteString(message);
        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends the player's full inventory.
    /// </summary>
    public async Task SendInventoryAsync()
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.PlayerInventory);

        var items = _player.Inventory.GetItems().ToList();
        packet.WriteByte((byte)items.Count);

        foreach (var item in items)
        {
            var id = item.CatalogId;
            if (item.IsEquipped)
            {
                id += 32768; // Equipped flag
            }

            if (item.Definition?.IsStackable == true && item.Amount > 1)
            {
                packet.WriteShort((short)(id + 32768)); // Stackable flag
                packet.WriteInt(item.Amount);
            }
            else
            {
                packet.WriteShort((short)id);
            }
        }

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends the player's stats (levels and experience).
    /// </summary>
    public async Task SendStatsAsync()
    {
        if (!_client.IsConnected) return;

        var skills = _player.Skills;

        using var packet = new Packet((byte)OpcodeOut.PlayerStats);

        // Current levels
        foreach (var skill in Enum.GetValues<Skill>())
        {
            packet.WriteByte((byte)skills.GetCurrentLevel(skill));
        }

        // Max levels
        foreach (var skill in Enum.GetValues<Skill>())
        {
            packet.WriteByte((byte)skills.GetMaxLevel(skill));
        }

        // Experience
        foreach (var skill in Enum.GetValues<Skill>())
        {
            packet.WriteInt(skills.GetExperience(skill));
        }

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends a single stat update.
    /// </summary>
    public async Task SendStatUpdateAsync(Skill skill)
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.PlayerStatExperience);
        packet.WriteByte((byte)skill);
        packet.WriteByte((byte)_player.Skills.GetCurrentLevel(skill));
        packet.WriteByte((byte)_player.Skills.GetMaxLevel(skill));
        packet.WriteInt(_player.Skills.GetExperience(skill));

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends equipment stat bonuses.
    /// </summary>
    public async Task SendEquipmentBonusesAsync()
    {
        if (!_client.IsConnected) return;

        var bonuses = _player.Equipment.GetTotalBonuses();

        using var packet = new Packet((byte)OpcodeOut.PlayerStatEquipmentBonus);
        packet.WriteByte((byte)bonuses.AttackStab);
        packet.WriteByte((byte)bonuses.AttackSlash);
        packet.WriteByte((byte)bonuses.AttackCrush);
        packet.WriteByte((byte)bonuses.AttackMagic);
        packet.WriteByte((byte)bonuses.AttackRanged);
        packet.WriteByte((byte)bonuses.DefenseStab);
        packet.WriteByte((byte)bonuses.DefenseSlash);
        packet.WriteByte((byte)bonuses.DefenseCrush);
        packet.WriteByte((byte)bonuses.DefenseMagic);
        packet.WriteByte((byte)bonuses.DefenseRanged);
        packet.WriteByte((byte)bonuses.Strength);
        packet.WriteByte((byte)bonuses.Prayer);

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends fatigue level.
    /// </summary>
    public async Task SendFatigueAsync()
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.PlayerStatFatigue);
        packet.WriteShort((short)_player.Fatigue.Current);

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Plays a sound effect.
    /// </summary>
    public async Task SendSoundAsync(string soundName)
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.PlaySound);
        packet.WriteString(soundName);

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Teleports the player visually.
    /// </summary>
    public async Task SendTeleportAsync()
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.Teleport);
        packet.WriteShort((short)_player.Location.X);
        packet.WriteShort((short)_player.Location.Y);

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends a death notification.
    /// </summary>
    public async Task SendDeathAsync()
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.PlayerDied);
        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends logout packet.
    /// </summary>
    public async Task SendLogoutAsync()
    {
        if (!_client.IsConnected) return;

        using var packet = PacketBuilder.Logout();
        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends logout denied packet.
    /// </summary>
    public async Task SendLogoutDeniedAsync()
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.LogoutDeny);
        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Opens the bank interface.
    /// </summary>
    public async Task SendOpenBankAsync()
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.ShowBank);

        var bankItems = _player.Bank.GetItems().ToList();
        packet.WriteByte((byte)bankItems.Count);
        packet.WriteByte((byte)_player.Bank.MaxSize);

        foreach (var item in bankItems)
        {
            packet.WriteShort((short)item.CatalogId);
            packet.WriteInt(item.Amount);
        }

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Closes the bank interface.
    /// </summary>
    public async Task SendCloseBankAsync()
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.HideBank);
        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends friend list.
    /// </summary>
    public async Task SendFriendListAsync()
    {
        if (!_client.IsConnected) return;

        var friends = _player.Social?.GetFriends() ?? Array.Empty<long>();

        using var packet = new Packet((byte)OpcodeOut.FriendList);
        packet.WriteByte((byte)friends.Length);

        foreach (var friendHash in friends)
        {
            packet.WriteLong(friendHash);
            packet.WriteByte(1); // Online status placeholder
        }

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends ignore list.
    /// </summary>
    public async Task SendIgnoreListAsync()
    {
        if (!_client.IsConnected) return;

        var ignores = _player.Social?.GetIgnores() ?? Array.Empty<long>();

        using var packet = new Packet((byte)OpcodeOut.IgnoreList);
        packet.WriteByte((byte)ignores.Length);

        foreach (var ignoreHash in ignores)
        {
            packet.WriteLong(ignoreHash);
        }

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends damage update to the player (for their own damage display).
    /// The actual visual hit splat is sent via WorldUpdateService as part of player updates.
    /// </summary>
    public async Task SendDamageAsync(int damage, int currentHp, int maxHp)
    {
        if (!_client.IsConnected) return;

        // Send stat update for hits (index 3 in RSC)
        using var packet = new Packet((byte)OpcodeOut.PlayerStatExperience);
        packet.WriteByte(3); // Hits skill index
        packet.WriteByte((byte)currentHp);
        packet.WriteByte((byte)maxHp);
        packet.WriteInt(0); // Experience unchanged

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends a self-damage notification with visual feedback.
    /// </summary>
    public async Task SendSelfDamageAsync(int damage)
    {
        if (!_client.IsConnected) return;

        // Use player stats packet to update health display
        await SendDamageAsync(damage, _player.CurrentHitpoints, _player.MaxHitpoints);
    }

    /// <summary>
    /// Generic packet send for custom packets.
    /// </summary>
    public async Task SendPacketAsync(Packet packet)
    {
        if (!_client.IsConnected) return;
        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Opens the trade interface with a partner.
    /// </summary>
    public async Task SendTradeOpenAsync(Player partner)
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.TradeOpen);
        packet.WriteShort((short)partner.Index);

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends the player's own trade offer.
    /// </summary>
    public async Task SendTradeOwnOfferAsync(IEnumerable<Items.Item> items)
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.TradeOwnOffer);

        var itemList = items.ToList();
        packet.WriteByte((byte)itemList.Count);

        foreach (var item in itemList)
        {
            packet.WriteShort((short)item.CatalogId);
            packet.WriteInt(item.Amount);
        }

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends the partner's trade offer.
    /// </summary>
    public async Task SendTradeOtherOfferAsync(IEnumerable<Items.Item> items)
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.TradeOtherOffer);

        var itemList = items.ToList();
        packet.WriteByte((byte)itemList.Count);

        foreach (var item in itemList)
        {
            packet.WriteShort((short)item.CatalogId);
            packet.WriteInt(item.Amount);
        }

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Sends the trade confirmation screen.
    /// </summary>
    public async Task SendTradeConfirmationAsync(Player partner, IEnumerable<Items.Item> ourOffer, IEnumerable<Items.Item> theirOffer)
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.TradeConfirmation);
        packet.WriteLong(partner.UsernameHash);

        // Our offer
        var ourItems = ourOffer.ToList();
        packet.WriteByte((byte)ourItems.Count);
        foreach (var item in ourItems)
        {
            packet.WriteShort((short)item.CatalogId);
            packet.WriteInt(item.Amount);
        }

        // Their offer
        var theirItems = theirOffer.ToList();
        packet.WriteByte((byte)theirItems.Count);
        foreach (var item in theirItems)
        {
            packet.WriteShort((short)item.CatalogId);
            packet.WriteInt(item.Amount);
        }

        await _client.SendAsync(packet);
    }

    /// <summary>
    /// Closes the trade interface.
    /// </summary>
    public async Task SendTradeCloseAsync()
    {
        if (!_client.IsConnected) return;

        using var packet = new Packet((byte)OpcodeOut.TradeClose);
        await _client.SendAsync(packet);
    }
}
