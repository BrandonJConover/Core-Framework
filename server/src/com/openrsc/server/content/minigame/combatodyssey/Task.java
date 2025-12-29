package com.openrsc.server.content.minigame.combatodyssey;

/**
 * Represents a combat odyssey task.
 * Modernized to Java 16+ record for immutability.
 */
public record Task(
	int taskId,
	String description,
	int[] npcIds,
	int kills,
	String[] monsterInfoDialog
) {
	// Legacy getter aliases for backwards compatibility
	public int getTaskId() { return taskId; }
	public String getDescription() { return description; }
	public int[] getNpcIds() { return npcIds; }
	public int getKills() { return kills; }
	public String[] getMonsterInfoDialog() { return monsterInfoDialog; }
}
