using System.Reflection;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Plugins;

/// <summary>
/// Plugin metadata.
/// </summary>
[AttributeUsage(AttributeTargets.Class)]
public sealed class PluginAttribute : Attribute
{
    public required string Name { get; init; }
    public string Version { get; init; } = "1.0.0";
    public string Author { get; init; } = "Unknown";
    public string Description { get; init; } = "";
    public string[] Dependencies { get; init; } = Array.Empty<string>();
}

/// <summary>
/// Base interface for all plugins.
/// </summary>
public interface IPlugin
{
    /// <summary>
    /// Called when the plugin is loaded.
    /// </summary>
    Task OnLoadAsync();

    /// <summary>
    /// Called when the plugin is unloaded.
    /// </summary>
    Task OnUnloadAsync();

    /// <summary>
    /// Called when the server starts.
    /// </summary>
    Task OnServerStartAsync();

    /// <summary>
    /// Called when the server stops.
    /// </summary>
    Task OnServerStopAsync();
}

/// <summary>
/// Base class for plugins with default implementations.
/// </summary>
public abstract class PluginBase : IPlugin
{
    protected ILogger Logger { get; private set; } = null!;
    protected IServiceProvider Services { get; private set; } = null!;

    internal void Initialize(ILogger logger, IServiceProvider services)
    {
        Logger = logger;
        Services = services;
    }

    public virtual Task OnLoadAsync() => Task.CompletedTask;
    public virtual Task OnUnloadAsync() => Task.CompletedTask;
    public virtual Task OnServerStartAsync() => Task.CompletedTask;
    public virtual Task OnServerStopAsync() => Task.CompletedTask;
}

/// <summary>
/// Plugin for handling NPC interactions.
/// </summary>
public interface INpcInteractionPlugin : IPlugin
{
    /// <summary>
    /// Handles NPC interaction.
    /// </summary>
    bool OnNpcInteraction(Player player, Npc npc, string option);
}

/// <summary>
/// Plugin for handling object interactions.
/// </summary>
public interface IObjectInteractionPlugin : IPlugin
{
    /// <summary>
    /// Handles object interaction.
    /// </summary>
    bool OnObjectInteraction(Player player, int objectId, int x, int y, string option);
}

/// <summary>
/// Plugin for handling item interactions.
/// </summary>
public interface IItemInteractionPlugin : IPlugin
{
    /// <summary>
    /// Handles item use.
    /// </summary>
    bool OnItemUse(Player player, int itemId);

    /// <summary>
    /// Handles item on item.
    /// </summary>
    bool OnItemOnItem(Player player, int itemId1, int itemId2);

    /// <summary>
    /// Handles item on object.
    /// </summary>
    bool OnItemOnObject(Player player, int itemId, int objectId);

    /// <summary>
    /// Handles item on NPC.
    /// </summary>
    bool OnItemOnNpc(Player player, int itemId, Npc npc);
}

/// <summary>
/// Plugin for handling commands.
/// </summary>
public interface ICommandPlugin : IPlugin
{
    /// <summary>
    /// Gets the commands this plugin handles.
    /// </summary>
    IReadOnlyList<string> Commands { get; }

    /// <summary>
    /// Handles a command.
    /// </summary>
    bool OnCommand(Player player, string command, string[] args);
}

/// <summary>
/// Plugin for handling player events.
/// </summary>
public interface IPlayerEventPlugin : IPlugin
{
    /// <summary>
    /// Called when a player logs in.
    /// </summary>
    Task OnPlayerLoginAsync(Player player);

    /// <summary>
    /// Called when a player logs out.
    /// </summary>
    Task OnPlayerLogoutAsync(Player player);

    /// <summary>
    /// Called when a player dies.
    /// </summary>
    Task OnPlayerDeathAsync(Player player, Mob? killer);

    /// <summary>
    /// Called when a player gains experience.
    /// </summary>
    void OnExperienceGain(Player player, Skills.Skill skill, int amount);

    /// <summary>
    /// Called when a player levels up.
    /// </summary>
    void OnLevelUp(Player player, Skills.Skill skill, int newLevel);
}

/// <summary>
/// Plugin for handling combat events.
/// </summary>
public interface ICombatPlugin : IPlugin
{
    /// <summary>
    /// Called before damage is dealt.
    /// </summary>
    int OnDamageDealt(Mob attacker, Mob defender, int damage);

    /// <summary>
    /// Called when an NPC is killed.
    /// </summary>
    Task OnNpcKilledAsync(Player killer, Npc npc);
}

/// <summary>
/// Information about a loaded plugin.
/// </summary>
public sealed class LoadedPlugin
{
    public required IPlugin Instance { get; init; }
    public required PluginAttribute Metadata { get; init; }
    public required Assembly Assembly { get; init; }
    public required Type Type { get; init; }
    public bool IsEnabled { get; set; } = true;
}

/// <summary>
/// Manages plugin loading and lifecycle.
/// </summary>
public sealed class PluginManager
{
    private readonly IServiceProvider _services;
    private readonly ILogger<PluginManager> _logger;
    private readonly Dictionary<string, LoadedPlugin> _plugins = new();
    private readonly List<INpcInteractionPlugin> _npcPlugins = new();
    private readonly List<IObjectInteractionPlugin> _objectPlugins = new();
    private readonly List<IItemInteractionPlugin> _itemPlugins = new();
    private readonly List<ICommandPlugin> _commandPlugins = new();
    private readonly List<IPlayerEventPlugin> _playerPlugins = new();
    private readonly List<ICombatPlugin> _combatPlugins = new();

    public IReadOnlyDictionary<string, LoadedPlugin> Plugins => _plugins;

    public PluginManager(IServiceProvider services, ILogger<PluginManager> logger)
    {
        _services = services;
        _logger = logger;
    }

    /// <summary>
    /// Loads plugins from a directory.
    /// </summary>
    public async Task LoadPluginsFromDirectoryAsync(string directory)
    {
        if (!Directory.Exists(directory))
        {
            _logger.LogWarning("Plugin directory does not exist: {Directory}", directory);
            return;
        }

        var files = Directory.GetFiles(directory, "*.dll");
        foreach (var file in files)
        {
            try
            {
                await LoadPluginFromFileAsync(file);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to load plugin from {File}", file);
            }
        }
    }

    /// <summary>
    /// Loads a plugin from a DLL file.
    /// </summary>
    public async Task LoadPluginFromFileAsync(string path)
    {
        var assembly = Assembly.LoadFrom(path);
        await LoadPluginsFromAssemblyAsync(assembly);
    }

    /// <summary>
    /// Loads plugins from an assembly.
    /// </summary>
    public async Task LoadPluginsFromAssemblyAsync(Assembly assembly)
    {
        var pluginTypes = assembly.GetTypes()
            .Where(t => t.IsClass && !t.IsAbstract && typeof(IPlugin).IsAssignableFrom(t))
            .ToList();

        foreach (var type in pluginTypes)
        {
            try
            {
                await LoadPluginAsync(type, assembly);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to load plugin type {Type}", type.FullName);
            }
        }
    }

    private async Task LoadPluginAsync(Type type, Assembly assembly)
    {
        var attribute = type.GetCustomAttribute<PluginAttribute>();
        if (attribute is null)
        {
            _logger.LogWarning("Plugin type {Type} does not have PluginAttribute", type.FullName);
            return;
        }

        if (_plugins.ContainsKey(attribute.Name))
        {
            _logger.LogWarning("Plugin {Name} is already loaded", attribute.Name);
            return;
        }

        // Check dependencies
        foreach (var dep in attribute.Dependencies)
        {
            if (!_plugins.ContainsKey(dep))
            {
                _logger.LogError("Plugin {Name} requires dependency {Dependency} which is not loaded", attribute.Name, dep);
                return;
            }
        }

        // Create instance
        var instance = (IPlugin)ActivatorUtilities.CreateInstance(_services, type);

        // Initialize if it's a PluginBase
        if (instance is PluginBase pluginBase)
        {
            var logger = _services.GetRequiredService<ILoggerFactory>().CreateLogger(type);
            pluginBase.Initialize(logger, _services);
        }

        // Register plugin
        var loadedPlugin = new LoadedPlugin
        {
            Instance = instance,
            Metadata = attribute,
            Assembly = assembly,
            Type = type
        };
        _plugins[attribute.Name] = loadedPlugin;

        // Register interface-specific handlers
        RegisterPluginHandlers(instance);

        // Call OnLoad
        await instance.OnLoadAsync();

        _logger.LogInformation("Loaded plugin: {Name} v{Version} by {Author}",
            attribute.Name, attribute.Version, attribute.Author);
    }

    private void RegisterPluginHandlers(IPlugin plugin)
    {
        if (plugin is INpcInteractionPlugin npcPlugin)
            _npcPlugins.Add(npcPlugin);

        if (plugin is IObjectInteractionPlugin objectPlugin)
            _objectPlugins.Add(objectPlugin);

        if (plugin is IItemInteractionPlugin itemPlugin)
            _itemPlugins.Add(itemPlugin);

        if (plugin is ICommandPlugin commandPlugin)
            _commandPlugins.Add(commandPlugin);

        if (plugin is IPlayerEventPlugin playerPlugin)
            _playerPlugins.Add(playerPlugin);

        if (plugin is ICombatPlugin combatPlugin)
            _combatPlugins.Add(combatPlugin);
    }

    /// <summary>
    /// Unloads a plugin.
    /// </summary>
    public async Task UnloadPluginAsync(string name)
    {
        if (!_plugins.TryGetValue(name, out var plugin))
            return;

        // Check if other plugins depend on this
        var dependents = _plugins.Values
            .Where(p => p.Metadata.Dependencies.Contains(name))
            .Select(p => p.Metadata.Name)
            .ToList();

        if (dependents.Count > 0)
        {
            _logger.LogWarning("Cannot unload {Name}, it is required by: {Dependents}",
                name, string.Join(", ", dependents));
            return;
        }

        // Unregister handlers
        UnregisterPluginHandlers(plugin.Instance);

        // Call OnUnload
        await plugin.Instance.OnUnloadAsync();

        _plugins.Remove(name);
        _logger.LogInformation("Unloaded plugin: {Name}", name);
    }

    private void UnregisterPluginHandlers(IPlugin plugin)
    {
        if (plugin is INpcInteractionPlugin npcPlugin)
            _npcPlugins.Remove(npcPlugin);

        if (plugin is IObjectInteractionPlugin objectPlugin)
            _objectPlugins.Remove(objectPlugin);

        if (plugin is IItemInteractionPlugin itemPlugin)
            _itemPlugins.Remove(itemPlugin);

        if (plugin is ICommandPlugin commandPlugin)
            _commandPlugins.Remove(commandPlugin);

        if (plugin is IPlayerEventPlugin playerPlugin)
            _playerPlugins.Remove(playerPlugin);

        if (plugin is ICombatPlugin combatPlugin)
            _combatPlugins.Remove(combatPlugin);
    }

    /// <summary>
    /// Calls OnServerStart for all plugins.
    /// </summary>
    public async Task OnServerStartAsync()
    {
        foreach (var plugin in _plugins.Values.Where(p => p.IsEnabled))
        {
            try
            {
                await plugin.Instance.OnServerStartAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in {Plugin}.OnServerStart", plugin.Metadata.Name);
            }
        }
    }

    /// <summary>
    /// Calls OnServerStop for all plugins.
    /// </summary>
    public async Task OnServerStopAsync()
    {
        foreach (var plugin in _plugins.Values.Where(p => p.IsEnabled).Reverse())
        {
            try
            {
                await plugin.Instance.OnServerStopAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in {Plugin}.OnServerStop", plugin.Metadata.Name);
            }
        }
    }

    // Event dispatch methods

    public bool HandleNpcInteraction(Player player, Npc npc, string option)
    {
        foreach (var plugin in _npcPlugins)
        {
            if (plugin.OnNpcInteraction(player, npc, option))
                return true;
        }
        return false;
    }

    public bool HandleObjectInteraction(Player player, int objectId, int x, int y, string option)
    {
        foreach (var plugin in _objectPlugins)
        {
            if (plugin.OnObjectInteraction(player, objectId, x, y, option))
                return true;
        }
        return false;
    }

    public bool HandleCommand(Player player, string command, string[] args)
    {
        foreach (var plugin in _commandPlugins)
        {
            if (plugin.Commands.Contains(command, StringComparer.OrdinalIgnoreCase))
            {
                if (plugin.OnCommand(player, command, args))
                    return true;
            }
        }
        return false;
    }

    public async Task OnPlayerLoginAsync(Player player)
    {
        foreach (var plugin in _playerPlugins)
        {
            await plugin.OnPlayerLoginAsync(player);
        }
    }

    public async Task OnPlayerLogoutAsync(Player player)
    {
        foreach (var plugin in _playerPlugins)
        {
            await plugin.OnPlayerLogoutAsync(player);
        }
    }

    public int OnDamageDealt(Mob attacker, Mob defender, int damage)
    {
        foreach (var plugin in _combatPlugins)
        {
            damage = plugin.OnDamageDealt(attacker, defender, damage);
        }
        return damage;
    }
}
