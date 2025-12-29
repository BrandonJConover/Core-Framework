using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Network;

/// <summary>
/// Interface for game clients (TCP and WebSocket).
/// </summary>
public interface IGameClient : IAsyncDisposable
{
    /// <summary>
    /// Unique client ID.
    /// </summary>
    Guid Id { get; }

    /// <summary>
    /// Remote endpoint address.
    /// </summary>
    string RemoteAddress { get; }

    /// <summary>
    /// The player associated with this client (null if not logged in).
    /// </summary>
    Player? Player { get; set; }

    /// <summary>
    /// Whether the client is currently connected.
    /// </summary>
    bool IsConnected { get; }

    /// <summary>
    /// Time of connection.
    /// </summary>
    DateTime ConnectedAt { get; }

    /// <summary>
    /// Last activity timestamp.
    /// </summary>
    DateTime LastActivity { get; }

    /// <summary>
    /// Whether this is a web client (WebSocket).
    /// </summary>
    bool IsWebClient { get; }

    /// <summary>
    /// Event raised when a packet is received.
    /// </summary>
    event Func<IGameClient, Packet, Task>? PacketReceived;

    /// <summary>
    /// Event raised when the client disconnects.
    /// </summary>
    event Func<IGameClient, Task>? Disconnected;

    /// <summary>
    /// Sends a packet to the client.
    /// </summary>
    Task SendAsync(Packet packet);

    /// <summary>
    /// Starts receiving data from the client.
    /// </summary>
    Task StartReceivingAsync();

    /// <summary>
    /// Disconnects the client.
    /// </summary>
    Task DisconnectAsync();
}
