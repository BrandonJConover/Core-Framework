using System.Reflection;
using Microsoft.Extensions.Logging;

namespace OpenRSC.Server.Network;

/// <summary>
/// Dispatches incoming packets to registered handlers.
/// Uses reflection to discover handlers at startup for clean architecture.
/// </summary>
public sealed class PacketDispatcher
{
    private readonly ILogger<PacketDispatcher> _logger;
    private readonly Dictionary<OpcodeIn, Func<IGameClient, Packet, Task>> _handlers = new();
    private readonly IServiceProvider _serviceProvider;

    public PacketDispatcher(
        ILogger<PacketDispatcher> logger,
        IServiceProvider serviceProvider)
    {
        _logger = logger;
        _serviceProvider = serviceProvider;
    }

    /// <summary>
    /// Registers all packet handlers from the specified assemblies.
    /// </summary>
    public void RegisterHandlers(params Assembly[] assemblies)
    {
        foreach (var assembly in assemblies)
        {
            RegisterHandlersFromAssembly(assembly);
        }

        _logger.LogInformation("Registered {Count} packet handlers", _handlers.Count);
    }

    private void RegisterHandlersFromAssembly(Assembly assembly)
    {
        var handlerTypes = assembly.GetTypes()
            .Where(t => t.GetCustomAttribute<PacketHandlerClassAttribute>() != null);

        foreach (var handlerType in handlerTypes)
        {
            var instance = ActivatorUtilities.CreateInstance(_serviceProvider, handlerType);

            var methods = handlerType.GetMethods()
                .Where(m => m.GetCustomAttribute<PacketHandlerAttribute>() != null);

            foreach (var method in methods)
            {
                var attr = method.GetCustomAttribute<PacketHandlerAttribute>()!;
                var handler = CreateHandler(instance, method);

                if (_handlers.TryAdd(attr.Opcode, handler))
                {
                    _logger.LogDebug("Registered handler for {Opcode}: {Type}.{Method}",
                        attr.Opcode, handlerType.Name, method.Name);
                }
                else
                {
                    _logger.LogWarning("Duplicate handler for {Opcode}", attr.Opcode);
                }
            }
        }
    }

    private static Func<IGameClient, Packet, Task> CreateHandler(object instance, MethodInfo method)
    {
        return (client, packet) =>
        {
            var result = method.Invoke(instance, new object[] { client, packet });
            return result is Task task ? task : Task.CompletedTask;
        };
    }

    /// <summary>
    /// Registers a handler delegate directly.
    /// </summary>
    public void RegisterHandler(OpcodeIn opcode, Func<IGameClient, Packet, Task> handler)
    {
        _handlers[opcode] = handler;
    }

    /// <summary>
    /// Handles an incoming packet from a client.
    /// </summary>
    public async Task HandlePacketAsync(IGameClient client, Packet packet)
    {
        var opcode = (OpcodeIn)packet.Opcode;

        if (_handlers.TryGetValue(opcode, out var handler))
        {
            try
            {
                await handler(client, packet);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error handling packet {Opcode} from {ClientId}",
                    opcode, client.Id);
            }
        }
        else
        {
            _logger.LogDebug("Unhandled packet opcode: {Opcode} (0x{OpcodeHex:X2})",
                opcode, packet.Opcode);
        }
    }
}

/// <summary>
/// Marks a class as containing packet handlers.
/// </summary>
[AttributeUsage(AttributeTargets.Class)]
public sealed class PacketHandlerClassAttribute : Attribute
{
}
