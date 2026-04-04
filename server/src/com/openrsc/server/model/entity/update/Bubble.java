package com.openrsc.server.model.entity.update;

import com.openrsc.server.model.entity.player.Player;

/**
 * Represents a skill bubble displayed above a player.
 * Modernized to Java 16+ record for immutability.
 */
public record Bubble(
	Player owner,
	int itemID
) {
	// Legacy getter aliases for backwards compatibility
	public int getID() { return itemID; }
	public Player getOwner() { return owner; }
}
