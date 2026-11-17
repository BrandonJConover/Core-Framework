package content.global.bots.companion.quest

import content.data.Quests
import core.game.node.entity.player.Player
import core.game.world.map.Location
import org.rs09.consts.Items
import org.rs09.consts.Scenery

/**
 * Cook's Assistant, following the same steps as Quest Helper's CooksAssistant helper
 * (Zoinkwiz/quest-helper, BSD-2-Clause), with targets mapped to rev-530 names and ids.
 */
object CooksAssistantPlan {
    private const val EGG = Items.EGG_1944
    private const val MILK = Items.BUCKET_OF_MILK_1927
    private const val FLOUR = Items.POT_OF_FLOUR_1933
    private const val POT = Items.EMPTY_POT_1931
    private const val BUCKET = Items.BUCKET_1925
    private const val GRAIN = Items.GRAIN_1947

    private val KITCHEN = Location(3208, 3214, 0)
    private val COOK_OPTIONS = listOf(
        "What's wrong?",
        "always happy to help",
        "know where to find this stuff",
        "all the information I need",
        "I'll get right on it",
    )

    private fun stage(p: Player) = p.questRepository.getStage(Quests.COOKS_ASSISTANT)
    private fun has(p: Player, item: Int) = p.inventory.contains(item, 1)
    private fun handedIn(p: Player, what: String) =
        p.getAttribute("cooks_assistant:all_submitted", false) || p.getAttribute("cooks_assistant:${what}_submitted", false)

    private fun milkDone(p: Player) = handedIn(p, "milk") || has(p, MILK)
    private fun flourDone(p: Player) = handedIn(p, "flour") || has(p, FLOUR)
    private fun eggDone(p: Player) = handedIn(p, "egg") || has(p, EGG)

    val plan = questPlan(Quests.COOKS_ASSISTANT, "cook", "cooks", "cooks assistant", "ca") {
        step({ stage(it) == 0 },
            QuestStep.TalkTo(named("Cook"), KITCHEN, COOK_OPTIONS, "Let's talk to the Cook in Lumbridge Castle's kitchen."))
        step({ milkDone(it) && flourDone(it) && eggDone(it) },
            QuestStep.TalkTo(named("Cook"), KITCHEN, COOK_OPTIONS, "We have everything. Back to the Cook!"))
        step({ !flourDone(it) && !has(it, POT) },
            QuestStep.TakeGroundItem(POT, Location(3209, 3214, 0), "I'll grab the pot on the kitchen table."))
        step({ !milkDone(it) && !has(it, BUCKET) },
            QuestStep.BuyFromShop(Target(listOf("Shop keeper", "Shop assistant"), setOf(520, 521)), BUCKET, Location(3212, 3246, 0), "I need a bucket for the milk. I'll buy one at the general store."))
        step({ !eggDone(it) },
            QuestStep.TakeGroundItem(EGG, Location(3228, 3299, 0), "Now an egg from the chicken pen."))
        step({ !milkDone(it) },
            QuestStep.Interact(named("Dairy cow"), "Milk", Location(3254, 3272, 0), "Off to milk the dairy cow."))
        step({ !flourDone(it) && it.getAttribute("milling:grain", 0) > 0 },
            QuestStep.UseItemOn(POT, Target(listOf("Flour bin"), setOf(Scenery.FLOUR_BIN_36878, Scenery.FLOUR_BIN_1782)), Location(3166, 3306, 0), "Collecting the flour from the bin downstairs."))
        step({ !flourDone(it) && it.getAttribute("milling:hopper", 0) == GRAIN },
            QuestStep.Interact(Target(listOf("Hopper controls"), setOf(Scenery.HOPPER_CONTROLS_2718, Scenery.HOPPER_CONTROLS_2721)), "Operate", Location(3166, 3305, 2), "Operating the hopper controls."))
        step({ !flourDone(it) && has(it, GRAIN) },
            QuestStep.UseItemOn(GRAIN, Target(listOf("Hopper"), setOf(Scenery.HOPPER_36881, Scenery.HOPPER_2717, Scenery.HOPPER_2716)), Location(3166, 3307, 2), "Putting the grain in the hopper at the top of the mill."))
        step({ !flourDone(it) },
            QuestStep.Interact(named("Wheat"), "Pick", Location(3161, 3294, 0), "Picking some wheat by the mill."))
    }
}
