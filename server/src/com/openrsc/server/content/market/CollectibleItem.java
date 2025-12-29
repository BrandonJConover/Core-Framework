package com.openrsc.server.content.market;

/**
 * Represents an item that can be collected from the market.
 * Modernized to Java 16+ record for immutability and conciseness.
 */
public record CollectibleItem(
	int claimId,
	String explanation,
	int itemAmount,
	int itemId,
	int playerId
) {
	/**
	 * Creates a CollectibleItem with default explanation.
	 */
	public static CollectibleItem of(int claimId, int itemId, int itemAmount, int playerId) {
		return new CollectibleItem(claimId, "", itemAmount, itemId, playerId);
	}
}
