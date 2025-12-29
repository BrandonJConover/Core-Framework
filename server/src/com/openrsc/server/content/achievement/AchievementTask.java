package com.openrsc.server.content.achievement;

import com.openrsc.server.content.achievement.Achievement.TaskType;

/**
 * Represents a task within an achievement.
 * Modernized to Java 16+ record for immutability.
 */
public record AchievementTask(
	TaskType task,
	int id,
	int amount
) {
	/**
	 * Factory method for backwards compatibility.
	 */
	public static AchievementTask of(TaskType task, int id, int amount) {
		return new AchievementTask(task, id, amount);
	}

	// Legacy getter aliases for backwards compatibility
	public TaskType getTask() { return task; }
	public int getId() { return id; }
	public int getAmount() { return amount; }

	@Override
	public String toString() {
		return "%s_id:%d_amount:%d".formatted(task.name(), id, amount);
	}
}
