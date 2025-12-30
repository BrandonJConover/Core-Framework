package com.openrsc.server.model.entity.update;

import com.openrsc.server.model.entity.Mob;

/**
 * Represents a skill bubble displayed above an NPC.
 * Modernized to Java 16+ record for immutability.
 */
public record BubbleNpc(
	Mob owner,
	int itemID
) {
	// Legacy getter aliases for backwards compatibility
	public int getID() { return itemID; }
	public Mob getOwner() { return owner; }
}
