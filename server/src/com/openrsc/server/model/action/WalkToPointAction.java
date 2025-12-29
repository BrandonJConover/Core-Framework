package com.openrsc.server.model.action;

import com.openrsc.server.model.Point;
import com.openrsc.server.model.entity.player.Player;

public abstract class WalkToPointAction extends WalkToAction {

	private final int radius;

	public WalkToPointAction(final Player owner, final Point actionLocation, final int radius) {
		super(owner, actionLocation);
		this.radius = radius;
	}

	public int getRadius() {
		return radius;
	}

	@Override
	public boolean shouldExecuteInternal() {
		return getPlayer().getLocation().getDistancePythagoras(getLocation()) <= radius;
	}

	@Override
	public String getFailureMessage() {
		return "You are unable to reach that location.";
	}
}
