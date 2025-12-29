using Microsoft.Extensions.Logging;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Items;
using OpenRSC.Server.Skilling;

namespace OpenRSC.Server.Network.Handlers;

/// <summary>
/// Handles object interactions for skilling.
/// </summary>
[PacketHandler(PacketOpcode.ObjectInteraction)]
public sealed class ObjectInteractionHandler : IPacketHandler
{
    private readonly ILogger<ObjectInteractionHandler> _logger;
    private readonly IItemFactory _itemFactory;

    public ObjectInteractionHandler(ILogger<ObjectInteractionHandler> logger, IItemFactory itemFactory)
    {
        _logger = logger;
        _itemFactory = itemFactory;
    }

    public async ValueTask HandleAsync(Player player, PacketReader reader)
    {
        var objectId = reader.ReadInt16();
        var x = reader.ReadInt16();
        var y = reader.ReadInt16();
        var option = reader.ReadByte();

        _logger.LogDebug("Player {Username} interacting with object {ObjectId} at ({X}, {Y}), option {Option}",
            player.Username, objectId, x, y, option);

        // Handle various skilling objects
        var result = objectId switch
        {
            // Mining rocks
            >= 100 and <= 110 => HandleMining(player, objectId),

            // Trees
            >= 0 and <= 10 => HandleWoodcutting(player, objectId),

            // Furnaces
            118 or 119 => HandleFurnace(player),

            // Anvils
            50 or 51 => HandleAnvil(player),

            // Fishing spots
            >= 192 and <= 195 => HandleFishing(player, objectId),

            // Cooking ranges
            11 or 119 => HandleCooking(player),

            // Altars (prayer)
            >= 38 and <= 41 => HandleAltar(player),

            // Runecraft altars
            >= 1190 and <= 1200 => HandleRunecraftAltar(player, objectId),

            // Banks
            >= 60 and <= 64 => HandleBank(player),

            // Default
            _ => SkillActionResult.Fail("Nothing interesting happens.")
        };

        if (!result.Success && result.Message is not null)
        {
            player.Message(result.Message);
        }
        else if (result.Action is not null)
        {
            // Would queue the skill action
            player.CurrentAction = result.Action;
        }

        await ValueTask.CompletedTask;
    }

    private SkillActionResult HandleMining(Player player, int objectId)
    {
        // Map object ID to ore ID
        var oreId = objectId switch
        {
            100 => 150, // Clay
            101 => 202, // Copper
            102 => 203, // Tin
            103 => 151, // Iron
            104 => 155, // Silver
            105 => 153, // Coal
            106 => 154, // Gold
            107 => 152, // Mithril
            108 => 409, // Adamant
            109 => 410, // Runite
            _ => 0
        };

        if (oreId == 0)
            return SkillActionResult.Fail("You can't mine this rock.");

        return MiningManager.StartMining(player, oreId, _itemFactory);
    }

    private SkillActionResult HandleWoodcutting(Player player, int objectId)
    {
        var logId = objectId switch
        {
            0 => 14,   // Tree -> Logs
            1 => 632,  // Oak
            2 => 633,  // Willow
            3 => 634,  // Maple
            4 => 635,  // Yew
            5 => 636,  // Magic
            _ => 0
        };

        if (logId == 0)
            return SkillActionResult.Fail("You can't chop this tree.");

        return WoodcuttingManager.StartWoodcutting(player, logId, _itemFactory);
    }

    private SkillActionResult HandleFurnace(Player player)
    {
        // Would show smelting interface
        player.Message("You examine the furnace.");
        return SkillActionResult.Fail(null);
    }

    private SkillActionResult HandleAnvil(Player player)
    {
        // Would show smithing interface
        player.Message("You examine the anvil.");
        return SkillActionResult.Fail(null);
    }

    private SkillActionResult HandleFishing(Player player, int objectId)
    {
        var spotType = objectId switch
        {
            192 => "Net",
            193 => "Bait",
            194 => "Cage",
            195 => "Harpoon",
            _ => null
        };

        if (spotType is null)
            return SkillActionResult.Fail("There are no fish here.");

        // Would start fishing based on spot type
        player.Message($"You attempt to catch a fish... ({spotType})");
        return SkillActionResult.Fail(null);
    }

    private SkillActionResult HandleCooking(Player player)
    {
        // Would show cooking interface
        player.Message("You examine the cooking range.");
        return SkillActionResult.Fail(null);
    }

    private SkillActionResult HandleAltar(Player player)
    {
        // Restore prayer points
        var maxPrayer = player.Skills.GetMaxLevel(Skills.Skill.Prayer);
        player.CurrentPrayerPoints = maxPrayer;
        player.Message("You recharge your prayer points.");
        return SkillActionResult.Fail(null);
    }

    private SkillActionResult HandleRunecraftAltar(Player player, int objectId)
    {
        return RunecraftingManager.CraftRunes(player, objectId, _itemFactory);
    }

    private SkillActionResult HandleBank(Player player)
    {
        // Would open bank interface
        player.Message("You access your bank account.");
        return SkillActionResult.Fail(null);
    }
}

/// <summary>
/// Handles item on item interactions.
/// </summary>
[PacketHandler(PacketOpcode.ItemOnItem)]
public sealed class ItemOnItemHandler : IPacketHandler
{
    private readonly ILogger<ItemOnItemHandler> _logger;
    private readonly IItemFactory _itemFactory;

    public ItemOnItemHandler(ILogger<ItemOnItemHandler> logger, IItemFactory itemFactory)
    {
        _logger = logger;
        _itemFactory = itemFactory;
    }

    public async ValueTask HandleAsync(Player player, PacketReader reader)
    {
        var slot1 = reader.ReadInt16();
        var slot2 = reader.ReadInt16();

        var item1 = player.Inventory.GetItemAt(slot1);
        var item2 = player.Inventory.GetItemAt(slot2);

        if (item1 is null || item2 is null)
        {
            player.Message("Nothing interesting happens.");
            return;
        }

        var id1 = item1.CatalogId;
        var id2 = item2.CatalogId;

        _logger.LogDebug("Player {Username} used item {Item1} on item {Item2}",
            player.Username, id1, id2);

        // Handle various item combinations
        var result = HandleItemCombination(player, id1, id2);

        if (!result.Success && result.Message is not null)
        {
            player.Message(result.Message);
        }
        else if (result.Action is not null)
        {
            player.CurrentAction = result.Action;
        }

        await ValueTask.CompletedTask;
    }

    private SkillActionResult HandleItemCombination(Player player, int id1, int id2)
    {
        // Knife on logs -> Arrow shafts / Bows
        if ((id1 == FletchingItems.Knife && IsLog(id2)) || (id2 == FletchingItems.Knife && IsLog(id1)))
        {
            var logId = IsLog(id1) ? id1 : id2;
            return FletchingManager.CutArrowShafts(player, logId, _itemFactory);
        }

        // Feather on arrow shafts
        if ((id1 == FletchingItems.Feather && id2 == FletchingItems.ArrowShaft) ||
            (id2 == FletchingItems.Feather && id1 == FletchingItems.ArrowShaft))
        {
            return FletchingManager.FeatherArrows(player, _itemFactory);
        }

        // Bowstring on unstrung bow
        if (id1 == FletchingItems.Bowstring || id2 == FletchingItems.Bowstring)
        {
            var bowId = id1 == FletchingItems.Bowstring ? id2 : id1;
            return FletchingManager.StringBow(player, bowId, _itemFactory);
        }

        // Tinderbox on logs -> Firemaking
        if ((id1 == FiremakingItems.TinderboxId && IsLog(id2)) || (id2 == FiremakingItems.TinderboxId && IsLog(id1)))
        {
            var logId = IsLog(id1) ? id1 : id2;
            return FiremakingManager.StartFiremaking(player, logId);
        }

        // Chisel on uncut gem -> Gem cutting
        if (id1 == CraftingItems.Chisel || id2 == CraftingItems.Chisel)
        {
            var gemId = id1 == CraftingItems.Chisel ? id2 : id1;
            return CraftingManager.CutGem(player, gemId, _itemFactory);
        }

        // Needle on leather -> Leather crafting
        if (id1 == CraftingItems.Needle || id2 == CraftingItems.Needle)
        {
            if (id1 == CraftingItems.Leather || id2 == CraftingItems.Leather)
            {
                // Would show leather crafting menu
                player.Message("What would you like to make?");
                return SkillActionResult.Fail(null);
            }
        }

        // Vial of water on herb -> Unfinished potion
        if (id1 == HerbloreItems.VialOfWater || id2 == HerbloreItems.VialOfWater)
        {
            var herbId = id1 == HerbloreItems.VialOfWater ? id2 : id1;
            return HerbloreManager.MakeUnfinishedPotion(player, herbId, _itemFactory);
        }

        return SkillActionResult.Fail("Nothing interesting happens.");
    }

    private static bool IsLog(int itemId) => itemId is 14 or 632 or 633 or 634 or 635 or 636;
}

/// <summary>
/// Handles clicking on inventory items.
/// </summary>
[PacketHandler(PacketOpcode.ItemClick)]
public sealed class ItemClickHandler : IPacketHandler
{
    private readonly ILogger<ItemClickHandler> _logger;
    private readonly IItemFactory _itemFactory;

    public ItemClickHandler(ILogger<ItemClickHandler> logger, IItemFactory itemFactory)
    {
        _logger = logger;
        _itemFactory = itemFactory;
    }

    public async ValueTask HandleAsync(Player player, PacketReader reader)
    {
        var slot = reader.ReadInt16();
        var item = player.Inventory.GetItemAt(slot);

        if (item is null)
        {
            return;
        }

        var itemId = item.CatalogId;
        _logger.LogDebug("Player {Username} clicked item {ItemId} in slot {Slot}",
            player.Username, itemId, slot);

        // Handle item clicks based on type
        if (IsGrimyHerb(itemId))
        {
            var result = HerbloreManager.CleanHerb(player, itemId, _itemFactory);
            HandleResult(player, result);
        }
        else if (IsPotion(itemId))
        {
            DrinkPotion(player, itemId, slot);
        }
        else if (IsTeleportTab(itemId))
        {
            UseTeleportTab(player, itemId, slot);
        }
        else if (IsBuryableBone(itemId))
        {
            BuryBones(player, itemId, slot);
        }

        await ValueTask.CompletedTask;
    }

    private void HandleResult(Player player, SkillActionResult result)
    {
        if (!result.Success && result.Message is not null)
        {
            player.Message(result.Message);
        }
        else if (result.Action is not null)
        {
            player.CurrentAction = result.Action;
        }
    }

    private static bool IsGrimyHerb(int itemId) => HerbDefinition.All.ContainsKey(itemId);

    private static bool IsPotion(int itemId) => itemId is >= 474 and <= 500;

    private static bool IsTeleportTab(int itemId) => itemId is >= 8007 and <= 8015;

    private static bool IsBuryableBone(int itemId) => itemId is 20 or 413 or 814;

    private void DrinkPotion(Player player, int itemId, int slot)
    {
        // Would apply potion effect
        player.Message("You drink the potion.");
        player.Inventory.RemoveAt(slot);
    }

    private void UseTeleportTab(Player player, int itemId, int slot)
    {
        player.Message("You break the tablet and teleport.");
        player.Inventory.RemoveAt(slot);
        // Would teleport player
    }

    private void BuryBones(Player player, int itemId, int slot)
    {
        var xp = itemId switch
        {
            20 => 4,    // Regular bones
            413 => 15,  // Big bones
            814 => 72,  // Dragon bones
            _ => 4
        };

        player.Inventory.RemoveAt(slot);
        player.Skills.AddExperience(Skills.Skill.Prayer, xp);
        player.Message("You bury the bones.");
    }
}
