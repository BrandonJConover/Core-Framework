package com.openrsc.server.model;

import com.openrsc.server.model.entity.player.Player;

/**
 * Represents a global chat message.
 * Modernized to Java 16+ record for immutability.
 */
public record GlobalMessage(
	Player player,
	String message
) {
	// Legacy getter aliases for backwards compatibility
	public Player getPlayer() { return player; }
	public String getMessage() { return message; }
}
