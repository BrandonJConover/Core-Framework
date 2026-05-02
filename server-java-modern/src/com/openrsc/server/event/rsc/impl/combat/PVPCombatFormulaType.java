package com.openrsc.server.event.rsc.impl.combat;

/**
 * Selects the melee/ranged damage-randomization formula applied in Player vs
 * Player (PvP) encounters.  Configured via {@code pvp_combat_formula_type} in
 * the server config file.
 *
 * <ul>
 *   <li><b>STORMY</b> — OpenRSC default: {@code (rand(maxRoll) + 320) / 640},
 *       which biases away from 0 and max, producing more "stormy" mid-range
 *       hits.  This is also the formula used for all PvE (mob vs mob)
 *       encounters, so selecting STORMY gives uniform behaviour across all
 *       combat contexts.</li>
 *   <li><b>AUTHENTIC</b> — Authentic RSC distribution: uniform random integer
 *       in {@code [0, maxHit]}, matching the original client's simple damage
 *       roll.  Produces lower average hits than STORMY.</li>
 *   <li><b>OSRS</b> — OSRS-inspired formula: same uniform range as AUTHENTIC
 *       for RSC stat values; reserved for future OSRS-flavoured refinements
 *       once those formulas are fully researched.</li>
 * </ul>
 */
public enum PVPCombatFormulaType {
    STORMY,
    AUTHENTIC,
    OSRS;

    /**
     * Parses a config-file string (case-insensitive) into a formula type.
     * Unknown values fall back to {@link #STORMY}.
     *
     * @param value Raw string from the config file (may be {@code null}).
     * @return The matching {@link PVPCombatFormulaType}, never {@code null}.
     */
    public static PVPCombatFormulaType fromString(final String value) {
        if (value == null) return STORMY;
        return switch (value.trim().toLowerCase()) {
            case "authentic" -> AUTHENTIC;
            case "osrs"      -> OSRS;
            default          -> STORMY;
        };
    }
}
