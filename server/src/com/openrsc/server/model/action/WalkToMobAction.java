package com.openrsc.server.model.action;

import com.openrsc.server.model.PathValidation;
import com.openrsc.server.model.Point;
import com.openrsc.server.model.entity.Mob;
import com.openrsc.server.model.entity.player.Player;

public abstract class WalkToMobAction extends WalkToAction {

	protected final Mob mob;
	private final int radius;
	private final boolean ignoreProjectileAllowed;
	private final ActionType actionType;

	public WalkToMobAction(final Player owner, final Mob mob, final int radius) {
		this(owner, mob, radius, true, ActionType.OTHER);
	}

	public WalkToMobAction(final Player owner, final Mob mob, final int radius, final boolean ignoreProjectileAllowed, final ActionType actionType) {
		super(owner, mob.getLocation());
		this.mob = mob;
		this.radius = radius;
		this.ignoreProjectileAllowed = ignoreProjectileAllowed;
		this.actionType = actionType;
	}

	public Mob getMob() {
		return mob;
	}

	public ActionType getActionType() {
		return actionType;
	}

	@Override
	public boolean shouldExecuteInternal() {
		/*
		This was seriously weird in RSC. Interactions were 1 tile, but the game would check one tile ahead to see if that point is in range.
		However, the pathing validation didn't consider diagonal blocking for non-projectile based actions.
		This causes authentic weird behaviour like being able to walk through scenery if there is a gap one tile either side of the mob for attacking.
		Some interactions work like this in RS2 as well.
		 */
		Point checkedPoint = ignoreProjectileAllowed ? getPlayer().getWalkingQueue().getNextMovement() : getPlayer().getLocation();
		boolean pathingCheckPassed = PathValidation.checkAdjacentDistance(getPlayer().getWorld(), checkedPoint, mob.getLocation(), ignoreProjectileAllowed, !ignoreProjectileAllowed);
		boolean actionExecutedThisTick = checkedPoint.withinRange(mob.getLocation(), radius) && pathingCheckPassed;

		// Magic attack handling - only clear immediately if retry is disabled
		// Otherwise, let the retry mechanism handle the failure
		if (actionType == ActionType.ATTACKMAGIC && getPlayer().inCombat() && !actionExecutedThisTick) {
			if (!isRetryEnabled()) {
				// Legacy behavior: clear action immediately if retry is disabled
				getPlayer().setWalkToAction(null);
			}
			// If retry is enabled, let GameStateUpdater handle the retry logic
		}
		return actionExecutedThisTick;
	}

	@Override
	public String getFailureMessage() {
		if (actionType == ActionType.ATTACK || actionType == ActionType.ATTACKMAGIC) {
			return "You are unable to reach your target to attack.";
		}
		return "You are unable to reach the " + (mob.isPlayer() ? "player" : "NPC") + ".";
	}

	@Override
	public boolean isPvPAttack() {
		return mob.isPlayer() && (actionType == ActionType.ATTACK || actionType == ActionType.ATTACKMAGIC);
	}
}

