package com.openrsc.server.model.action;

import com.openrsc.server.model.Point;
import com.openrsc.server.model.entity.player.Player;

public abstract class WalkToAction {

	private Player player;
	private Point location;
	private volatile boolean executed;

	// Retry mechanism fields
	private int retryAttempts;
	private int maxRetries;
	private long lastAttemptTick;
	private boolean retryEnabled;

	public WalkToAction(final Player player, final Point location) {
		this.player = player;
		this.location = location;
		this.executed = false;
		this.retryAttempts = 0;
		this.maxRetries = player.getConfig().ACTION_MAX_RETRIES;
		this.lastAttemptTick = 0;
		this.retryEnabled = player.getConfig().ACTION_RETRY_ENABLED;
	}

	public void execute() {
		executeInternal();
		finishExecution();
	}

	public void finishExecution() {
		setExecuted(true);
		player.setLastExecutedWalkToAction(this);
	}

	public final boolean shouldExecute() {
		return !isExecuted() && shouldExecuteInternal();
	}

	protected abstract void executeInternal();

	protected abstract boolean shouldExecuteInternal();

	public Player getPlayer() {
		return player;
	}

	public Point getLocation() {
		return location;
	}

	public synchronized boolean isExecuted() {
		return executed;
	}

	protected synchronized void setExecuted(boolean executed) {
		this.executed = executed;
	}

	public boolean isPvPAttack() {
		return false;
	}

	// Retry mechanism methods

	/**
	 * Called when shouldExecute returns false. Increments attempt counter.
	 * @param currentTick The current game tick
	 * @return true if action should be retried, false if max retries exceeded
	 */
	public boolean onAttemptFailed(final long currentTick) {
		if (!retryEnabled) {
			return false;
		}
		this.lastAttemptTick = currentTick;
		this.retryAttempts++;
		return retryAttempts < maxRetries;
	}

	/**
	 * Checks if this action has exceeded its retry limit
	 * @return true if max retries have been exceeded
	 */
	public boolean hasExceededRetryLimit() {
		return retryEnabled && retryAttempts >= maxRetries;
	}

	/**
	 * Checks if retry is enabled for this action
	 * @return true if retry is enabled
	 */
	public boolean isRetryEnabled() {
		return retryEnabled;
	}

	/**
	 * Sets whether retry is enabled for this action
	 * @param retryEnabled true to enable retry
	 */
	public void setRetryEnabled(boolean retryEnabled) {
		this.retryEnabled = retryEnabled;
	}

	/**
	 * Gets the number of retry attempts made
	 * @return the number of retry attempts
	 */
	public int getRetryAttempts() {
		return retryAttempts;
	}

	/**
	 * Gets the maximum number of retries allowed
	 * @return the maximum retries
	 */
	public int getMaxRetries() {
		return maxRetries;
	}

	/**
	 * Sets the maximum number of retries allowed
	 * @param maxRetries the maximum retries
	 */
	public void setMaxRetries(int maxRetries) {
		this.maxRetries = maxRetries;
	}

	/**
	 * Resets the retry counter (useful if conditions improve)
	 */
	public void resetRetryAttempts() {
		this.retryAttempts = 0;
	}

	/**
	 * Gets the last tick when an attempt was made
	 * @return the last attempt tick
	 */
	public long getLastAttemptTick() {
		return lastAttemptTick;
	}

	/**
	 * Override this method to provide a custom failure message when max retries are exceeded.
	 * @return the failure message to display to the player
	 */
	public String getFailureMessage() {
		return "You are unable to reach your target.";
	}
}
