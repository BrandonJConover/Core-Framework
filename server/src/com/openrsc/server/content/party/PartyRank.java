package com.openrsc.server.content.party;

/**
 * Party member rank enumeration.
 * Modernized with private final field.
 */
public enum PartyRank {
	NORMAL(0),
	LEADER(1),
	GENERAL(2);

	private final int rankIndex;

	PartyRank(int id) {
		this.rankIndex = id;
	}

	public static PartyRank getRankFor(int rankID) {
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
