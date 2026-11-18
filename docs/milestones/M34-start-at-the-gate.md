# M34 Start at the gate

Status: Built (2026-11-15, v0.21.0), play-test pending (`docs/PLAYTEST.md`).

## Goal

The hub keep is gone. Players join, spawn and respawn at the Barrowlands' arrival gate, a ring of rune stones on the realm itself; that gate is also where the gates to the next realms open once their bosses fall.

## Depends on

M20 (realm, `Layout.arrival_point`, `_home_gate`), M21. Comes after M33 and before M22; M22's boss site and world flags then open gates here instead of at the keep.

## Design

- The arrival gate (`Layout.arrival_gate(realm)`, from `realm.arrival` and the world seed as `_home_gate` does today) is the start of every world: `Layout.spawn_point(peer_id)` is the ring around it on the ground (`arrival_point`). Respawns after death go there too, until M67's bed.
- Terrain must exist under a spawn before the body is placed: the server calls `World.chunks.ensure_around` for the spawn point at join and at respawn, as portals do.
- The keep's training dummies move next to the arrival gate, standing on the ground (`Gravity.up_at`). They stay enemy indices 0 and 1.
- The gate's look: standing rune stones, two torches, the dark stone arch of the current portal. Same art direction as §3.2.
- The old hand-built realm at the origin stays until M22 removes it; a gate next to the arrival leads there ("To the old barrow") and its "Home" gates lead back to the arrival.
- Later briefs that put things "at the keep" move them next to the arrival gate: respec (M57), workbench and smithy (M58).

## Tasks

### 1. Spawn on the realm (Opus)

Files: `sim/layout.gd`, `sim/world.gd`, `sim/sim_player.gd` (respawn), `net/game_server.gd`, `sim/arena.gd`, `client/hud.gd`, `client/player_view.gd`, `client/presence.gd`, `client/sounds.gd`, `boot/bench.gd`, tests that use `Layout.HUB` (`gravity_test`, `realm_gate_test`, `terrain_test`, `combat_test`, the encounter tests), `net/net.gd`.

Steps:

1. `Layout.spawn_point` and respawns use the arrival ring; `ensure_around` before placing; joins wait for the chunks like a gate does.
2. Remove `Layout.HUB`, `HUB_YARD`, `HUB_WALL`, `HUB_PLANET_RADIUS`, `HUB_REACH`, `HUB_PLACE`, `on_hub`, the keep's gates and `Arena._build_hub` with its props. `place_at` returns a realm id or `ORIGIN_PLACE`.
3. `DUMMIES` become points relative to the arrival gate on the ground; the dummies never move, so they need no anchor: the arrival chunks are pinned (`World.build`) and cover them (`Layout.dummy_post`, `World._post_dummies`).
4. The realm's gate behind the arrival (`_home_gate`, now `Layout.arrival_gate(realm)`) becomes "To the old barrow" (`portals()[2]`); the old realm's "Home" gates (`portals()[0]` and the victory one `[1]`) lead to the arrival (`Portal.realm`).
5. Places that branch on `HUB_PLACE` (HUD, presence, wind ambience, player view) use the realm.
6. Protocol bump; update `CLAUDE.md` ("Boot", "Look and planets", the screenshot `--spawn` examples).

Tests: a joining player stands on the realm's ground at the gate; a dead player respawns there; the dummies stand on the ground and take hits; the old realm is reachable and its gate leads back; the network test passes.

### 2. The gate's look (Sonnet)

Files: `sim/arena.gd` or `client/terrain_view.gd`, `docs/PLAYTEST.md`, `docs/RESOURCES.md` if an asset is added.

Steps: rune stones and torches around the arrival, scatter (`Scatter.points`) kept clear of the ring; screenshots at the arrival (`--seed=1234 --spawn=2500,1004,1800 --look=180,-6`); play-test checks. Close the milestone: status in `docs/PLAN.md` §6 and here, `CLAUDE.md` "Where we are", `VERSION`.

## Out of scope

Saved spawn points and beds (M67). The next realms' gates (M22 opens the first).

## Pitfalls

- The spawn is now on streamed terrain: a body placed before its chunk exists falls through. Every spawn and respawn path goes through `ensure_around`.
- The client draws only the place it stands on (`Arena.show_planet`): a client that starts on the realm must build its terrain view before the first frame or it sees the void.
- `Encounter` resets when the old realm empties (`occupied`); the start no longer sits next to it, check the reset still runs.
