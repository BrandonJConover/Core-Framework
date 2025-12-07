namespace OpenRSC.Server.Network;

/// <summary>
/// Interface for handling incoming packets.
/// </summary>
public interface IPacketHandler
{
    /// <summary>
    /// Handles an incoming packet from a client.
    /// </summary>
    Task HandlePacketAsync(GameClient client, Packet packet);
}

/// <summary>
/// Attribute to mark a method as a packet handler.
/// </summary>
[AttributeUsage(AttributeTargets.Method)]
public sealed class PacketHandlerAttribute : Attribute
{
    public OpcodeIn Opcode { get; }

    public PacketHandlerAttribute(OpcodeIn opcode)
    {
        Opcode = opcode;
    }
}
