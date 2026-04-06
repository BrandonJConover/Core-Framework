package com.openrsc.server.content.market;

/**
 * Mutable market collectible item shape kept compatible with the existing
 * database/task code while the rest of the server modernization settles.
 */
public class CollectibleItem {
	public int claim_id;
	public String explanation = "";
	public int item_amount;
	public int item_id;
	public int playerID;

	public CollectibleItem() {
	}

	public CollectibleItem(int claimId, String explanation, int itemAmount, int itemId, int playerId) {
		this.claim_id = claimId;
		this.explanation = explanation;
		this.item_amount = itemAmount;
		this.item_id = itemId;
		this.playerID = playerId;
	}

	public static CollectibleItem of(int claimId, int itemId, int itemAmount, int playerId) {
		return new CollectibleItem(claimId, "", itemAmount, itemId, playerId);
	}
}
