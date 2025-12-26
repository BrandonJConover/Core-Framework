using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Inventory;
using OpenRSC.Server.Models;
using OpenRSC.Server.Network;

namespace OpenRSC.Server.Services;

/// <summary>
/// Service responsible for sending world state updates to players.
/// This includes player positions, NPC positions, ground items, and scenery.
/// </summary>
public sealed class WorldUpdateService
{
    private readonly ILogger<WorldUpdateService> _logger;
    private readonly IWorldService _worldService;

    /// <summary>
    /// View distance in tiles.
    /// </summary>
    private const int ViewDistance = 16;

    public WorldUpdateService(
        ILogger<WorldUpdateService> logger,
        IWorldService worldService)
    {
        _logger = logger;
        _worldService = worldService;
    }

    /// <summary>
    /// Sends all world updates to a player.
    /// </summary>
    public async Task SendWorldUpdateAsync(Player player)
    {
        if (player.Client is null || !player.IsLoggedIn)
            return;

        // Send updates in parallel for efficiency
        await Task.WhenAll(
            SendPlayerCoordsAsync(player),
            SendNpcCoordsAsync(player),
            SendPlayerUpdatesAsync(player),
            SendNpcUpdatesAsync(player)
        );
    }

    /// <summary>
    /// Sends the player's own coordinates.
    /// </summary>
    private async Task SendPlayerCoordsAsync(Player player)
    {
        if (player.ActionSender is null) return;

        using var packet = new Packet((byte)OpcodeOut.PlayerCoords);

        // Write the player's sector position (relative to region)
        var sectorX = player.Location.X % 48;
        var sectorY = player.Location.Y % 48;

        packet.WriteShort((short)player.Location.X);
        packet.WriteShort((short)player.Location.Y);
        packet.WriteByte((byte)sectorX);
        packet.WriteByte((byte)sectorY);

        // Direction player is facing
        var direction = CalculateDirection(player);
        packet.WriteByte((byte)direction);

        await player.ActionSender.SendPacketAsync(packet);
    }

    /// <summary>
    /// Sends updates about nearby NPCs' coordinates.
    /// </summary>
    private async Task SendNpcCoordsAsync(Player player)
    {
        if (player.ActionSender is null) return;

        var nearbyNpcs = _worldService.GetNpcsInRange(player.Location, ViewDistance).ToList();

        using var packet = new Packet((byte)OpcodeOut.NpcCoords);

        // Number of NPCs in view
        packet.WriteByte((byte)nearbyNpcs.Count);

        foreach (var npc in nearbyNpcs)
        {
            packet.WriteShort((short)npc.Index);
            packet.WriteShort((short)npc.Location.X);
            packet.WriteShort((short)npc.Location.Y);

            // NPC direction and movement
            var direction = CalculateDirection(npc);
            packet.WriteByte((byte)direction);
        }

        await player.ActionSender.SendPacketAsync(packet);
    }

    /// <summary>
    /// Sends updates about nearby players (appearance, chat, damage, etc).
    /// </summary>
    private async Task SendPlayerUpdatesAsync(Player player)
    {
        if (player.ActionSender is null) return;

        var nearbyPlayers = _worldService.GetPlayersInRange(player.Location, ViewDistance)
            .Where(p => p != player)
            .ToList();

        using var packet = new Packet((byte)OpcodeOut.UpdatePlayers);

        // Count of players being updated
        packet.WriteShort((short)nearbyPlayers.Count);

        foreach (var nearbyPlayer in nearbyPlayers)
        {
            // Player index
            packet.WriteShort((short)nearbyPlayer.Index);

            // Position relative to viewer
            var dx = nearbyPlayer.Location.X - player.Location.X;
            var dy = nearbyPlayer.Location.Y - player.Location.Y;
            packet.WriteByte((byte)(dx + 32)); // Offset to keep positive
            packet.WriteByte((byte)(dy + 32));

            // Direction
            var direction = CalculateDirection(nearbyPlayer);
            packet.WriteByte((byte)direction);

            // Update flags
            byte updateFlags = 0;
            if (nearbyPlayer.HasMoved)
                updateFlags |= 0x01;
            if (nearbyPlayer.HasChangedAppearance)
                updateFlags |= 0x02;
            if (nearbyPlayer.InCombat)
                updateFlags |= 0x04;
            if (nearbyPlayer.IsSkulled)
                updateFlags |= 0x08;
            if (nearbyPlayer.HasTakenDamage)
                updateFlags |= 0x10;

            packet.WriteByte(updateFlags);

            // If appearance update needed, include appearance data
            if (nearbyPlayer.HasChangedAppearance)
            {
                WritePlayerAppearance(packet, nearbyPlayer);
            }

            // If took damage, include hit splat data
            if (nearbyPlayer.HasTakenDamage)
            {
                packet.WriteByte((byte)nearbyPlayer.LastDamage);
                packet.WriteByte((byte)nearbyPlayer.CurrentHitpoints);
                packet.WriteByte((byte)nearbyPlayer.MaxHitpoints);
            }

            // Combat level
            packet.WriteByte((byte)nearbyPlayer.CombatLevel);
        }

        await player.ActionSender.SendPacketAsync(packet);
    }

    /// <summary>
    /// Sends updates about nearby NPCs (combat, chat bubbles, etc).
    /// </summary>
    private async Task SendNpcUpdatesAsync(Player player)
    {
        if (player.ActionSender is null) return;

        var nearbyNpcs = _worldService.GetNpcsInRange(player.Location, ViewDistance).ToList();

        using var packet = new Packet((byte)OpcodeOut.UpdateNpcs);

        // Count of NPCs being updated
        packet.WriteShort((short)nearbyNpcs.Count);

        foreach (var npc in nearbyNpcs)
        {
            // NPC index
            packet.WriteShort((short)npc.Index);

            // NPC definition ID
            packet.WriteShort((short)npc.DefinitionId);

            // Position
            packet.WriteShort((short)npc.Location.X);
            packet.WriteShort((short)npc.Location.Y);

            // Direction
            var direction = CalculateDirection(npc);
            packet.WriteByte((byte)direction);

            // Update flags
            byte updateFlags = 0;
            if (npc.InCombat)
                updateFlags |= 0x01;
            if (npc.HasMoved)
                updateFlags |= 0x02;
            if (npc.HasTakenDamage)
                updateFlags |= 0x04;

            packet.WriteByte(updateFlags);

            // Combat info if in combat or took damage
            if (npc.InCombat || npc.HasTakenDamage)
            {
                packet.WriteByte((byte)npc.CurrentHitpoints);
                packet.WriteByte((byte)(npc.Definition?.Hitpoints ?? 1));
            }

            // If took damage, include hit splat
            if (npc.HasTakenDamage)
            {
                packet.WriteByte((byte)npc.LastDamage);
            }
        }

        await player.ActionSender.SendPacketAsync(packet);
    }

    /// <summary>
    /// Writes player appearance data to a packet.
    /// </summary>
    private static void WritePlayerAppearance(Packet packet, Player player)
    {
        // Username hash
        packet.WriteLong(player.UsernameHash);

        // Equipment/sprites for 12 slots
        var equipment = player.Equipment;
        for (var slot = 0; slot < 12; slot++)
        {
            var item = equipment.GetSlot((EquipmentSlot)slot);
            if (item is not null)
            {
                packet.WriteShort((short)(item.CatalogId + 1));
            }
            else
            {
                packet.WriteShort(0);
            }
        }

        // Hair/skin colors - RSC has 5 appearance values
        packet.WriteByte(0); // Hair color
        packet.WriteByte(0); // Top color
        packet.WriteByte(0); // Bottom color
        packet.WriteByte(0); // Skin color
        packet.WriteByte(0); // Combat level (placeholder)

        // Skull status
        packet.WriteByte((byte)(player.IsSkulled ? 1 : 0));
    }

    /// <summary>
    /// Calculates the facing direction based on movement.
    /// </summary>
    private static int CalculateDirection(Mob mob)
    {
        if (!mob.HasMoved || mob.PreviousLocation == mob.Location)
            return 0; // Standing still

        var dx = mob.Location.X - mob.PreviousLocation.X;
        var dy = mob.Location.Y - mob.PreviousLocation.Y;

        // RSC uses 8-directional movement
        // 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW
        return (dx, dy) switch
        {
            (0, -1) => 0,  // North
            (1, -1) => 1,  // NE
            (1, 0) => 2,   // East
            (1, 1) => 3,   // SE
            (0, 1) => 4,   // South
            (-1, 1) => 5,  // SW
            (-1, 0) => 6,  // West
            (-1, -1) => 7, // NW
            _ => 0
        };
    }
}
