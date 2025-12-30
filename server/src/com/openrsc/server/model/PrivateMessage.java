package com.openrsc.server.model;

import com.openrsc.server.model.entity.player.Player;

/**
 * Represents a private message between players.
 * Modernized to Java 16+ record for immutability.
 */
public record PrivateMessage(
	Player player,
	String message,
	long friend
) {
	/**
	 * Compact constructor with validation.
	 */
	public PrivateMessage {
		if (message == null) {
			message = "";
		}
	}

	// Legacy getter aliases for backwards compatibility
	public Player getPlayer() { return player; }
	public String getMessage() { return message; }
	public long getFriend() { return friend; }
}
