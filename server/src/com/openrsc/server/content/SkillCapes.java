package com.openrsc.server.content;

import com.openrsc.server.constants.ItemId;
import com.openrsc.server.model.entity.player.Player;
import com.openrsc.server.util.rsc.DataConversions;

public class SkillCapes {

	public static boolean shouldActivate(Player player, ItemId cape, boolean parameter) {
		if (!player.getConfig().WANT_CUSTOM_SPRITES || player.getConfig().WANT_OPENPK_POINTS)
			return false;

		if (!player.getCarriedItems().getEquipment().hasEquipped(cape.id()))
			return false;

		return switch (cape) {
			case ATTACK_CAPE -> attackCape(parameter);
			case THIEVING_CAPE -> thievingCape(parameter);
			case STRENGTH_CAPE -> strengthCape(parameter);
			default -> false;
		};
	}

	public static boolean shouldActivate(Player player, ItemId cape) {
		if (!player.getConfig().WANT_CUSTOM_SPRITES || player.getConfig().WANT_OPENPK_POINTS)
			return false;

		if (!player.getCarriedItems().getEquipment().hasEquipped(cape.id()))
			return false;

		return switch (cape) {
			case MINING_CAPE -> miningCape();
			case FLETCHING_CAPE -> fletchingCape();
			case MAGIC_CAPE -> magicCape();
			case SMITHING_CAPE -> smithingCape();
			case DEFENSE_CAPE -> defenseCape();
			case HERBLAW_CAPE -> herblawCape();
			case PRAYER_CAPE -> prayerCape();
			case WOODCUTTING_CAPE -> woodcuttingCape();
			case RANGED_CAPE -> rangedCape();
			case HARVESTING_CAPE -> harvestingCape();
			case FIREMAKING_CAPE -> true;
			default -> false;
		};
	}

	public static int shouldActivateInt(Player player, ItemId cape) {
		if (!player.getConfig().WANT_CUSTOM_SPRITES || player.getConfig().WANT_OPENPK_POINTS)
			return -1;

		if (!player.getCarriedItems().getEquipment().hasEquipped(cape.id()))
			return -1;

		return switch (cape) {
			case HITS_CAPE -> hitsCape();
			default -> -1;
		};
	}

	private static boolean attackCape(boolean isHit) {
		double rerollPercent = 35;
		if (!isHit) {
			if (rand1to100() <= rerollPercent) {
				return true;
			}
		}
		return false;
	}

	private static boolean thievingCape(boolean succeededPickpocket) {
		double rerollPercent = 15;
		if (!succeededPickpocket) {
			if (rand1to100() <= rerollPercent) {
				return true;
			}
		}
		return false;
	}

	private static boolean miningCape() {
		double rerollPercent = 8;
		if (rand1to100() <= rerollPercent) {
			return true;
		}
		return false;
	}

	private static boolean fletchingCape() {
		double rerollPercent = 20;
		if (rand1to100() <= rerollPercent) {
			return true;
		}
		return false;
	}

	private static boolean magicCape() {
		double noRunesChance = 10;
		if (rand1to100() <= noRunesChance) {
			return true;
		}
		return false;
	}

	private static boolean strengthCape(boolean isHit) {
		double hitChance = 35;
		if (rand1to100() <= hitChance && isHit) {
			return true;
		}
		return false;
	}

	private static boolean defenseCape() {
		final int hitChance = 35;
		if (rand1to100() <= hitChance) {
			return true;
		}
		return false;
	}

	private static boolean herblawCape() {
		final int saveChance = 10;
		if (rand1to100() <= saveChance) {
			return true;
		}
		return false;
	}

	private static boolean prayerCape() {
		final int pointsChance = 100;
		if (rand1to100() <= pointsChance) {
			return true;
		}
		return false;
	}

	private static boolean woodcuttingCape() {
		final int noFellChance = 35;
		if (rand1to100() <= noFellChance) {
			return true;
		}
		return false;
	}

	private static boolean rangedCape() {
		final int doubleShotChance = 10;
		if (rand1to100() <= doubleShotChance) {
			return true;
		}
		return false;
	}

	private static boolean harvestingCape() {
		final int doubleYieldChance = 20;
		if (rand1to100() <= doubleYieldChance) {
			return true;
		}
		return false;
	}

	private static boolean smithingCape() {
		double noCoalChance = 25;
		if (rand1to100() <= noCoalChance) {
			return true;
		}
		return false;
	}

	private static int hitsCape() {
		final int rand = rand1to100();
		if (rand >= 75) {
			return 3;
		} else if (rand >= 50) {
			return 2;
		} else if (rand >= 25) {
			return 1;
		} else {
			return 0;
		}
	}

	private static int rand1to100() {
		return (int)(DataConversions.getRandom().nextDouble() * 99) + 1;
	}
}
