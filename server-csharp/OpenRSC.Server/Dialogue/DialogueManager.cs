using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Network;

namespace OpenRSC.Server.Dialogue;

/// <summary>
/// Manages NPC dialogues and conversation state.
/// </summary>
public sealed class DialogueManager
{
    private readonly ILogger<DialogueManager> _logger;
    private readonly Dictionary<int, DialogueTree> _dialogueTrees = new();
    private readonly Dictionary<Player, DialogueState> _activeDialogues = new();

    public DialogueManager(ILogger<DialogueManager> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Registers a dialogue tree for an NPC.
    /// </summary>
    public void RegisterDialogue(int npcId, DialogueTree tree)
    {
        _dialogueTrees[npcId] = tree;
        _logger.LogDebug("Registered dialogue for NPC {NpcId}", npcId);
    }

    /// <summary>
    /// Starts a dialogue with an NPC.
    /// </summary>
    public bool StartDialogue(Player player, Npc npc)
    {
        // Check if player is already in a dialogue
        if (_activeDialogues.ContainsKey(player))
        {
            EndDialogue(player);
        }

        // Get dialogue tree for this NPC
        if (!_dialogueTrees.TryGetValue(npc.Id, out var tree))
        {
            // No specific dialogue - use generic greeting
            SendNpcMessage(player, npc, $"Hello, adventurer!");
            return false;
        }

        // Start the dialogue
        var state = new DialogueState(npc, tree, tree.RootNode);
        _activeDialogues[player] = state;

        // Send the first node
        ProcessNode(player, state);

        _logger.LogDebug("{Username} started dialogue with {NpcName}",
            player.Username, npc.Name);

        return true;
    }

    /// <summary>
    /// Processes a player's dialogue option selection.
    /// </summary>
    public void SelectOption(Player player, int optionIndex)
    {
        if (!_activeDialogues.TryGetValue(player, out var state))
        {
            return;
        }

        var currentNode = state.CurrentNode;

        // Validate option index
        if (currentNode.Options is null || optionIndex < 0 || optionIndex >= currentNode.Options.Count)
        {
            _logger.LogWarning("{Username} selected invalid dialogue option {Index}",
                player.Username, optionIndex);
            return;
        }

        var selectedOption = currentNode.Options[optionIndex];

        // Execute any action associated with the option
        selectedOption.OnSelect?.Invoke(player, state.Npc);

        // Move to next node
        if (selectedOption.NextNodeId is not null)
        {
            var nextNode = state.Tree.GetNode(selectedOption.NextNodeId);
            if (nextNode is not null)
            {
                state.CurrentNode = nextNode;
                ProcessNode(player, state);
                return;
            }
        }

        // No next node - end dialogue
        EndDialogue(player);
    }

    /// <summary>
    /// Continues a dialogue (for "Click to continue" prompts).
    /// </summary>
    public void ContinueDialogue(Player player)
    {
        if (!_activeDialogues.TryGetValue(player, out var state))
        {
            return;
        }

        var currentNode = state.CurrentNode;

        // Move to next node if specified
        if (currentNode.NextNodeId is not null)
        {
            var nextNode = state.Tree.GetNode(currentNode.NextNodeId);
            if (nextNode is not null)
            {
                state.CurrentNode = nextNode;
                ProcessNode(player, state);
                return;
            }
        }

        // No next node - end dialogue
        EndDialogue(player);
    }

    /// <summary>
    /// Ends the current dialogue.
    /// </summary>
    public void EndDialogue(Player player)
    {
        if (_activeDialogues.Remove(player))
        {
            SendHideDialogue(player);
            _logger.LogDebug("{Username} ended dialogue", player.Username);
        }
    }

    /// <summary>
    /// Checks if a player is in an active dialogue.
    /// </summary>
    public bool IsInDialogue(Player player)
    {
        return _activeDialogues.ContainsKey(player);
    }

    /// <summary>
    /// Gets the current dialogue state for a player.
    /// </summary>
    public DialogueState? GetDialogueState(Player player)
    {
        return _activeDialogues.TryGetValue(player, out var state) ? state : null;
    }

    private void ProcessNode(Player player, DialogueState state)
    {
        var node = state.CurrentNode;

        // Execute any action on entering this node
        node.OnEnter?.Invoke(player, state.Npc);

        // Check conditions
        if (node.Condition is not null && !node.Condition(player, state.Npc))
        {
            // Condition failed - try alternate node or end
            if (node.FailNodeId is not null)
            {
                var failNode = state.Tree.GetNode(node.FailNodeId);
                if (failNode is not null)
                {
                    state.CurrentNode = failNode;
                    ProcessNode(player, state);
                    return;
                }
            }
            EndDialogue(player);
            return;
        }

        // Send appropriate dialogue UI based on node type
        switch (node.Type)
        {
            case DialogueNodeType.NpcMessage:
                SendNpcMessage(player, state.Npc, node.Text);
                break;

            case DialogueNodeType.PlayerMessage:
                SendPlayerMessage(player, node.Text);
                break;

            case DialogueNodeType.Options:
                SendOptions(player, node.Options ?? new List<DialogueOption>());
                break;

            case DialogueNodeType.Action:
                // Just execute and move to next
                ContinueDialogue(player);
                break;
        }
    }

    private void SendNpcMessage(Player player, Npc npc, string message)
    {
        using var packet = new Packet((byte)OpcodeOut.ShowDialogue);
        packet.WriteByte(0); // NPC message type
        packet.WriteShort((short)npc.Id);
        packet.WriteString(npc.Name);
        packet.WriteString(message);

        _ = player.ActionSender?.SendPacketAsync(packet);
    }

    private void SendPlayerMessage(Player player, string message)
    {
        using var packet = new Packet((byte)OpcodeOut.ShowDialogue);
        packet.WriteByte(1); // Player message type
        packet.WriteString(message);

        _ = player.ActionSender?.SendPacketAsync(packet);
    }

    private void SendOptions(Player player, List<DialogueOption> options)
    {
        using var packet = new Packet((byte)OpcodeOut.ShowMenu);
        packet.WriteByte((byte)options.Count);

        foreach (var option in options)
        {
            packet.WriteString(option.Text);
        }

        _ = player.ActionSender?.SendPacketAsync(packet);
    }

    private void SendHideDialogue(Player player)
    {
        using var packet = new Packet((byte)OpcodeOut.HideDialogue);
        _ = player.ActionSender?.SendPacketAsync(packet);
    }
}

/// <summary>
/// Represents a dialogue tree for an NPC.
/// </summary>
public sealed class DialogueTree
{
    private readonly Dictionary<string, DialogueNode> _nodes = new();

    public DialogueNode RootNode { get; }
    public int NpcId { get; }

    public DialogueTree(int npcId, DialogueNode rootNode)
    {
        NpcId = npcId;
        RootNode = rootNode;
        RegisterNode(rootNode);
    }

    public void RegisterNode(DialogueNode node)
    {
        _nodes[node.Id] = node;
    }

    public DialogueNode? GetNode(string nodeId)
    {
        return _nodes.TryGetValue(nodeId, out var node) ? node : null;
    }
}

/// <summary>
/// Represents a single node in a dialogue tree.
/// </summary>
public sealed class DialogueNode
{
    public required string Id { get; init; }
    public DialogueNodeType Type { get; init; } = DialogueNodeType.NpcMessage;
    public string Text { get; init; } = string.Empty;
    public string? NextNodeId { get; init; }
    public string? FailNodeId { get; init; }
    public List<DialogueOption>? Options { get; init; }

    /// <summary>
    /// Condition that must be true for this node to display.
    /// </summary>
    public Func<Player, Npc, bool>? Condition { get; init; }

    /// <summary>
    /// Action to execute when entering this node.
    /// </summary>
    public Action<Player, Npc>? OnEnter { get; init; }
}

/// <summary>
/// Represents a selectable option in a dialogue.
/// </summary>
public sealed class DialogueOption
{
    public required string Text { get; init; }
    public string? NextNodeId { get; init; }

    /// <summary>
    /// Action to execute when this option is selected.
    /// </summary>
    public Action<Player, Npc>? OnSelect { get; init; }
}

/// <summary>
/// Types of dialogue nodes.
/// </summary>
public enum DialogueNodeType
{
    NpcMessage,
    PlayerMessage,
    Options,
    Action
}

/// <summary>
/// Represents the current state of a player's dialogue.
/// </summary>
public sealed class DialogueState
{
    public Npc Npc { get; }
    public DialogueTree Tree { get; }
    public DialogueNode CurrentNode { get; set; }

    public DialogueState(Npc npc, DialogueTree tree, DialogueNode currentNode)
    {
        Npc = npc;
        Tree = tree;
        CurrentNode = currentNode;
    }
}
