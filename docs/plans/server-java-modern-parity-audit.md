# Plan: server-java-modern feature-parity audit

> **Hand-off note for ChatGPT.** Read this whole file first. Touch only files in *Scope*. Repo root is `/Users/brandonjconover/Documents/GitHub/Core-Framework`. This plan is **read-only** — its output is a structured audit document, not code changes. Follow-up plans then implement the gaps the audit surfaces.

## Goal

Produce a single canonical "what's left to port from upstream `server/` (Java 8) into `server-java-modern/` (Java 21)" tracker that's accurate as of the moment it lands. Today the team has three docs (`PROGRESS.md`, `CHERRY_PICKS.md`, `SERVER.md`) that overlap and drift. After this lands, the team has one **at-a-glance** parity table per subsystem (combat, skills, quests, plugins, packet handlers, database).

The audit *does not implement anything*. It produces a structured doc that future plans (one per major gap) can reference as their entry point.

## Why now

The repo's CLAUDE.md identifies `server-java-modern/` as the "active dev target" but the only structured tracker is a date-prefixed changelog. As more agents land work in parallel, "is feature X ported yet?" becomes a 5-minute grep instead of a 5-second lookup. Auditing once now and keeping the table fresh from this point on closes that loop.

## Scope (files you may edit)

- `server-java-modern/PARITY.md` — new file, the canonical tracker (single source of truth).
- `server-java-modern/PROGRESS.md` — add a top banner pointing at PARITY.md and noting that PROGRESS.md is the *changelog*, PARITY.md is the *state*.
- `server-java-modern/CHERRY_PICKS.md` — add a top banner with the same pointer.
- `docs/plans/README.md` — add this plan to the "iOS / Server" section.

## Out of scope (do NOT touch)

- Any `.java` file. **Audit only.**
- The legacy `server/` directory.
- Database files.
- Build scripts.

## Audit method

For each subsystem in the table below, run a small script-shaped check and capture **what exists in `server/` but is missing or stubbed in `server-java-modern/`**. Format every result as a row in PARITY.md with:

```
| <subsystem> | <legacy file> | <modern file> | <status> | <commit / SHA if present> | <notes> |
```

`status` is one of: `parity`, `partial`, `stub`, `missing`, `intentionally diverged` (use this when modern fixes a known bug or hardens a CVE — link the security commit).

### Subsystems to audit

| # | Subsystem | Legacy path glob | Modern path glob |
|---|---|---|---|
| 1 | Packet handlers (incoming) | `server/src/com/openrsc/server/net/rsc/handlers/*.java` | `server-java-modern/src/com/openrsc/server/net/rsc/handlers/*.java` |
| 2 | Packet generators (outgoing) | `server/src/com/openrsc/server/net/rsc/generators/impl/*.java` | `server-java-modern/.../generators/impl/*.java` |
| 3 | Plugins — quests | `server/plugins/com/openrsc/server/plugins/quests/**/*.java` | mirror |
| 4 | Plugins — skills | `server/plugins/com/openrsc/server/plugins/skills/**/*.java` | mirror |
| 5 | Plugins — minigames | `server/plugins/com/openrsc/server/plugins/minigames/**/*.java` | mirror |
| 6 | Plugins — NPC dialogues | `server/plugins/com/openrsc/server/plugins/npcs/**/*.java` | mirror |
| 7 | Database schema | `server/database/{mysql,sqlite}/**/*.sql` | mirror |
| 8 | Configuration files (per-world `.conf`) | `server/*.conf` | mirror (modern adds new keys; flag them) |
| 9 | XML/text data assets | `server/conf/server/**/*` | mirror |
| 10 | Constants / enums (item ids, npc ids, skill ids) | `server/src/com/openrsc/server/constants/*.java` | mirror |

For each, the audit step is:

```bash
# Pseudocode — write a per-subsystem helper if useful
diff <(ls server/src/.../handlers/ | sort) \
     <(ls server-java-modern/src/.../handlers/ | sort) \
     > /tmp/handlers-presence.diff
# For files present in both, compare line counts to spot stubs:
for f in $(comm -12 <(ls server/.../handlers/) <(ls server-java-modern/.../handlers/)); do
  legacy=$(wc -l < server/.../handlers/$f)
  modern=$(wc -l < server-java-modern/.../handlers/$f)
  if (( modern < legacy / 2 )); then
    echo "STUB CANDIDATE  $f  legacy=$legacy modern=$modern"
  fi
done
```

A file present in both with significantly fewer lines on the modern side is a *stub candidate*. Manual confirmation needed before flagging — modern may have legitimately collapsed a verbose pattern.

### Special audits worth doing once

1. **Cherry-pick gap.** `CHERRY_PICKS.md` already lists upstream commits we've pulled. Diff that against `git log upstream/develop -- server/` to find merged-upstream commits we haven't picked up. List the gap as a `Gaps_Versus_Upstream` section in PARITY.md.

2. **CVE backlog.** Search legacy `server/` for any bug-fix commits the modernization missed:
   ```
   git log --all --grep='CVE\|injection\|sanitize\|escape' -- server/
   ```
   Cross-reference each hit against modern; flag misses as `intentionally diverged` if modern already fixed them differently, else `missing` (high priority follow-up).

3. **Per-world config drift.** Diff each `<name>.conf` file pair (`server/local.conf` vs `server-java-modern/local.conf`) and table the new keys, removed keys, and changed defaults.

4. **Database addons.** `server/database/mysql/addons/*.sql` lists optional schema bundles (auctionhouse, clans, runecraft, etc.). Confirm each addon also exists in `server-java-modern/database/`, or document the omission.

## Output structure

`server-java-modern/PARITY.md` should land with this skeleton (filled in):

```markdown
# server-java-modern — feature parity vs upstream `server/`

_Last audited: 2026-05-DD (commit <SHA>)._

## Quick summary

| Subsystem | Parity | Partial | Stub | Missing | Intentionally diverged |
|---|---|---|---|---|---|
| Packet handlers | 84 | 2 | 1 | 0 | 1 |
| Packet generators | 76 | 0 | 0 | 0 | 0 |
| Quests | 31 | 4 | 0 | 1 | 0 |
| ... | | | | | |

## Subsystems

### Packet handlers

| Handler | Legacy LOC | Modern LOC | Status | Notes |
|---|---|---|---|---|
| `ItemDropHandler` | 245 | 248 | parity |  |
| `BankDepositHandler` | 89 | 89 | parity |  |
| `WalkPacketHandler` | 312 | 322 | parity | modern adds path-length sanity guard |
| ... | | | | |

### Plugins — quests

…

### Database addons

…

### Gaps versus upstream develop

Upstream commits merged into `develop` that are not yet ported into modern:

- `abc123def — feat: shop restocking timer fix` (touches `server/plugins/.../shops/`, modern equivalent stale)
- `456fed789 — fix: clan whitelist case sensitivity` (touches `server/.../clan/`)

### Known intentional divergences

- modern's `LoginHandler` rejects passwords > 20 chars where legacy truncated. Documented in `server-java-modern/SERVER.md`.

### Methodology

How rows were generated (re-runnable):
```bash
# 1. ls + diff per subsystem
# 2. wc -l flag stub candidates
# 3. git log on upstream to find unmerged work
```

When a contributor claims feature X is now at parity, they update the row and bump `Last audited` only after re-running the methodology block — don't trust freeform edits.

```

## Self-test

After producing PARITY.md:

1. Spot-check 5 random rows by diffing the legacy + modern files yourself; the row's status field must match what you see.
2. Confirm the **Quick summary** table sums correctly (each row's totals = sum of statuses for that subsystem).
3. Run a fresh `git log upstream/develop -- server/` and confirm the "Gaps versus upstream" list is current (timestamp the audit at the top of the doc).

## Acceptance criteria

1. `server-java-modern/PARITY.md` exists with all 10 subsystem tables filled in.
2. Quick summary table reflects the per-subsystem totals.
3. `server-java-modern/PROGRESS.md` and `server-java-modern/CHERRY_PICKS.md` carry a top banner pointing at PARITY.md.
4. The audit's methodology section is reproducible — running the documented shell snippets produces the same row counts.
5. Spot-checks of 5 random rows pass (status field matches reality).
6. Add this plan link to `docs/plans/README.md`.

## Out of scope clarifications

- **Don't fix anything you find.** Audit only. Each gap turns into its own follow-up plan.
- **Don't widen the audit to plugins' English-language quest dialogues.** Just verify the file exists; line-count comparison is fine.
- **Don't try to match version numbers** between upstream and modern at the file level — many files were renamed during modernization.
- **Don't audit upstream's stable / preservation branches.** Only `upstream/develop` matters.

## Commit guidance

Single commit: `server-java-modern: parity audit doc + status banners`. Push nothing.
