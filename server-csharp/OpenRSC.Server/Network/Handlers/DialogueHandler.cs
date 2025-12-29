using Microsoft.Extensions.Logging;
using OpenRSC.Server.Dialogue;
using OpenRSC.Server.Entities;

namespace OpenRSC.Server.Network.Handlers;

/// <summary>
/// Handles dialogue-related packets.
/// </summary>
public sealed class DialogueHandler : IPacketHandler
{
    private const int OpDialogueOption = 116;
    private const int OpDialogueContinue = 117;
    private const int OpDialogueClose = 118;

    private readonly ILogger<DialogueHandler> _logger;
    private readonly DialogueManager _dialogueManager;

    public int[] Opcodes => new[]
    {
        OpDialogueOption,
        OpDialogueContinue,
        OpDialogueClose
    };

    public DialogueHandler(
        ILogger<DialogueHandler> logger,
        DialogueManager dialogueManager)
    {
        _logger = logger;
        _dialogueManager = dialogueManager;
    }

    public async Task HandleAsync(GameClient client, Packet packet)
    {
        var player = client.Player;
        if (player is null || !player.IsLoggedIn)
            return;

        switch (packet.Opcode)
        {
            case OpDialogueOption:
                HandleOptionSelect(player, packet);
                break;
            case OpDialogueContinue:
                HandleContinue(player);
                break;
            case OpDialogueClose:
                HandleClose(player);
                break;
        }

        await Task.CompletedTask;
    }

    private void HandleOptionSelect(Player player, Packet packet)
    {
        var optionIndex = packet.ReadByte();

        if (!_dialogueManager.IsInDialogue(player))
        {
            _logger.LogWarning("{Username} tried to select dialogue option but not in dialogue",
                player.Username);
            return;
        }

        _dialogueManager.SelectOption(player, optionIndex);

        _logger.LogDebug("{Username} selected dialogue option {Index}",
            player.Username, optionIndex);
    }

    private void HandleContinue(Player player)
    {
        if (!_dialogueManager.IsInDialogue(player))
        {
            return;
        }

        _dialogueManager.ContinueDialogue(player);
    }

    private void HandleClose(Player player)
    {
        _dialogueManager.EndDialogue(player);
    }
}
