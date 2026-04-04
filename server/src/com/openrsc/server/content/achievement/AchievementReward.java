package com.openrsc.server.content.achievement;

import com.openrsc.server.content.achievement.Achievement.TaskReward;

/**
 * Represents a reward for completing an achievement.
 * Modernized to Java 16+ record for immutability.
 */
public record AchievementReward(
	TaskReward rewardType,
	int id,
	int amount,
	boolean guaranteed
) {
	/**
	 * Creates an AchievementReward (backwards compatibility factory method).
	 */
	public static AchievementReward of(TaskReward rewardType, int id, int amount, boolean guaranteed) {
		return new AchievementReward(rewardType, id, amount, guaranteed);
	}

	// Legacy getter aliases for backwards compatibility
	public TaskReward getRewardType() { return rewardType; }
	public int getId() { return id; }
	public int getAmount() { return amount; }
	public boolean isGuaranteed() { return guaranteed; }
}
