using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Network;

/// <summary>
/// Interface for handling incoming packets (legacy method-based).
/// </summary>
public interface IPacketHandlerLegacy
{
    /// <summary>
    /// Handles an incoming packet from a client.
    /// </summary>
    Task HandlePacketAsync(GameClient client, Packet packet);
}

/// <summary>
/// Interface for class-based packet handlers.
/// </summary>
public interface IPacketHandler
{
    /// <summary>
    /// Handles an incoming packet from a player.
    /// </summary>
    ValueTask HandleAsync(Player player, PacketReader reader);
}

/// <summary>
/// Packet opcodes for the handler attribute system.
/// Maps to OpcodeIn but with game-action naming.
/// </summary>
public enum PacketOpcode
{
    // Movement
    WalkToPoint = 16,
    WalkToEntity = 187,

    // Combat
    AttackPlayer = 171,
    AttackNpc = 190,
    CombatStyle = 29,
    PrayerToggle = 60,
    CastSpell = 137,
    EatFood = 91,

    // Interactions
    ObjectInteraction = 136,
    ItemOnItem = 91,
    ItemClick = 169,

    // Chat
    Command = 38,

    // NPCs
    NpcTalk = 153,

    // Trade
    TradeRequest = 142,

    // Duel
    DuelRequest = 103
}

/// <summary>
/// Attribute to mark a class as a packet handler.
/// </summary>
[AttributeUsage(AttributeTargets.Class)]
public sealed class PacketHandlerAttribute : Attribute
{
    public PacketOpcode Opcode { get; }

    public PacketHandlerAttribute(PacketOpcode opcode)
    {
        Opcode = opcode;
    }
}

/// <summary>
/// Attribute to mark a method as a packet handler (legacy).
/// </summary>
[AttributeUsage(AttributeTargets.Method)]
public sealed class PacketHandlerMethodAttribute : Attribute
{
    public OpcodeIn Opcode { get; }

    public PacketHandlerMethodAttribute(OpcodeIn opcode)
    {
        Opcode = opcode;
    }
}

/// <summary>
/// Reader wrapper for packets with convenient methods.
/// </summary>
public sealed class PacketReader
{
    private readonly Packet _packet;

    public PacketReader(Packet packet)
    {
        _packet = packet;
    }

    public byte ReadByte() => _packet.ReadByte();
    public sbyte ReadSByte() => _packet.ReadSByte();
    public short ReadInt16() => _packet.ReadShort();
    public ushort ReadUInt16() => _packet.ReadUShort();
    public int ReadInt32() => _packet.ReadInt();
    public long ReadInt64() => _packet.ReadLong();
    public string ReadString() => _packet.ReadString();
    public byte[] ReadBytes(int count) => _packet.ReadBytes(count);

    public int Remaining => _packet.Remaining;
}
