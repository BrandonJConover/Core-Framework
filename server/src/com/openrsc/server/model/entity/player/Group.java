package com.openrsc.server.model.entity.player;

import com.openrsc.server.model.world.World;

import java.util.Map;

/**
 * Player group/rank definitions.
 * Modernized to use Java 9+ Map.of() and Java 14+ switch expressions.
 */
public final class Group {
	public static final int OWNER = 0;
	public static final int ADMIN = 1;
	public static final int SUPER_MOD = 2;
	public static final int MOD = 3;
	public static final int DEV = 5;
	public static final int EVENT = 7;
	public static final int PLAYER_MOD = 8;
	private static final int TESTER = 9;
	public static final int USER = 10;

	public static final int DEFAULT_GROUP = Group.USER;

	public static final Map<Integer, String> GROUP_NAMES = Map.ofEntries(
		Map.entry(OWNER, "Owner"),
		Map.entry(ADMIN, "Admin"),
		Map.entry(SUPER_MOD, "Super Moderator"),
		Map.entry(MOD, "Moderator"),
		Map.entry(DEV, "Developer"),
		Map.entry(EVENT, "Event"),
		Map.entry(PLAYER_MOD, "Player Moderator"),
		Map.entry(TESTER, "Tester"),
		Map.entry(USER, "User")
	);

	private Group() {} // Prevent instantiation

	public static String getGlobalMessageName(int groupID) {
		return switch (groupID) {
			case OWNER, ADMIN -> "Admin";
			case SUPER_MOD, MOD -> "Mod";
			case DEV, EVENT -> "Event";
			case PLAYER_MOD -> "Pmod";
			case TESTER, USER -> "";
			default -> "";
		};
	}

	public static String getNameColour(World world, int groupID) {
		if (!world.getServer().getConfig().WANT_CUSTOM_RANK_DISPLAY) {
			return "";
		}

		return switch (groupID) {
			case OWNER -> "@dcy@";
			case ADMIN -> "@gre@";
			case SUPER_MOD -> "@blu@";
			case MOD -> "@bl1@";
			case DEV -> "@red@";
			case EVENT -> "@eve@";
			case PLAYER_MOD, TESTER, USER -> "";
			default -> "";
		};
	}

	public static String getNameSprite(int groupID) {
		return "";
	}

	public static String getStaffPrefix(World world, int groupID) {
		return getNameSprite(groupID) + getNameColour(world, groupID);
	}
}
