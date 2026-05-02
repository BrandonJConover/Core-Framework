# Implementation plan handoffs

Each plan in this folder is a self-contained ChatGPT brief for one tier of the rev-530 web client port. Order matters — later tiers assume earlier tiers landed. A second agent (or the same agent on the next turn) can pick up the next plan while the previous one is being implemented.

## Pick-up order

| # | Plan | Why this order |
|---|---|---|
| 1 | [tier5a — zone-update opcodes](web-client-tier5a-zone-state.md) | World state stays in sync after REBUILD_NORMAL. Highest impact, smallest risk. |
| 2 | [tier5b — player + chat state](web-client-tier5b-player-chat-state.md) | Teleports stop racing. PMs/clan chat appear. |
| 3 | [tier5c — interface drain](web-client-tier5c-interface-drain.md) | Defensive — keep the byte stream aligned even before widgets exist. |
| 4 | [tier6a — renderer probe](web-client-tier6a-renderer-probe.md) | Diagnostic-only. Gives us the data Tier 6b will use. |
| 5 | (tier 6b — renderer fix) | **Unwritten.** Conditioned on tier 6a output. Don't write ahead of the data. |
| 6 | [tier7 — widget skeleton](web-client-tier7-widget-skeleton.md) | Hooks the Tier 5c flight recorder onto a real component tree. |
| 7 | (tier 7b — widget renderer) | **Unwritten.** Render the widget tree the skeleton built. |
| 8 | [tier8 — textures (idx26 + TextureOps)](web-client-tier8-textures.md) | Last visible-rendering tier; depends on verified rasterizer (Tier 6). |
| 9 | [tier9 — BAS skeletons + skin transforms](web-client-tier9-bas-skeletons.md) | Animations (walk / idle / attack). Comes after textures so debugging splits cleanly between "is the model on screen?" and "is it animating?". |
| 5d | [tier5d — audio (SoundBank + 2 opcodes)](web-client-tier5d-audio.md) | Independent of 5a/b/c — can run in parallel with any of them. |

## Conventions every plan follows

- **Hand-off note** at the top — repo root + which file lists are off-limits.
- **Goal** in 1–3 sentences.
- **Why this matters** — gives the implementer a model of where this fits.
- **Scope (files you may edit)** + **Out of scope (do NOT touch)**.
- **Reference** — exact rt4-client file:line so the implementer can read source-of-truth before writing TS.
- **Implementation** with step numbers; each step does one thing.
- **Self-test** — a paste-ready shell block plus the success line to look for.
- **Acceptance criteria** — checked-off form, including a "tick the corresponding `docs/web-client-plan.md` entry" item.
- **Out of scope clarifications** — anti-patterns the implementer is most likely to drift into.
- **Commit guidance** — one commit per logical group, prefix `2009scape-web: tierNX — `, push nothing.

## When a plan finishes

The implementer must:

1. Build green (per the plan's self-test block).
2. Tick the matching checkbox in [`docs/web-client-plan.md`](../web-client-plan.md), append the commit SHA inline.
3. Stop. Do **not** start the next tier — that's a separate plan's job.

## Adding a new plan

When a plan is done and we need the next one, follow the existing skeleton (any of tier5a/b/c is a good template). Save under this folder with the name pattern `web-client-tierN<letter>-<topic>.md`. Update the table above.

For *iOS* parity work, mirror the same convention into `docs/plans/ios-*` — that side is mostly converging onto polish work, but a few structural items (3D models for trees / use-on workflow) deserve the same handoff format. None are written yet; pick them up after the web-client backlog is unblocked.
