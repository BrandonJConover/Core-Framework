package com.openrsc.server.event.rsc.impl.combat;

/**
 * Selects the damage-randomization formula used in player-vs-player combat.
 * Configured with {@code pvp_combat_formula_type}.
 */
public enum PVPCombatFormulaType {
	STORMY,
	AUTHENTIC,
	OSRS;

	public static PVPCombatFormulaType fromString(final String value) {
		if (value == null) return STORMY;
		return switch (value.trim().toLowerCase()) {
			case "authentic" -> AUTHENTIC;
			case "osrs" -> OSRS;
			default -> STORMY;
		};
	}
}
