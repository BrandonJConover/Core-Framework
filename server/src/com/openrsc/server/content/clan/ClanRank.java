package com.openrsc.server.content.clan;

/**
 * Clan member rank enumeration.
 * Modernized with private final field.
 */
public enum ClanRank {
	NORMAL(0),
	LEADER(1),
	GENERAL(2);

	private final int rankIndex;

	ClanRank(int id) {
		this.rankIndex = id;
	}

	public static ClanRank getRankFor(int rankID) {
		var values = values();
		if (rankID >= 0 && rankID < values.length) {
			return values[rankID];
		}
		return NORMAL;
	}

	public int getRankIndex() {
		return rankIndex;
	}
}
