# M49 Shrines and flask

Status: Planned.

## Goal

Old shrines stand across each realm. Lighting one makes it a place to rest: it refills the healing flask, becomes the respawn point, and lets the party travel between lit shrines. Healing is a few flask charges, not waiting.

## Depends on

M23 (world objects, saves, character file), M38 (the shrine's generated look). M24.

## Design

- Shrine sites are a pure function of realm and seed (like `BossSite`): about eight per realm, spread by a minimum distance, on flat ground, with a cleared disc; the arrival has one lit from the start. Lit shrines are saved in the world file.
- Resting (use key, a few seconds, interrupted by damage): flask refilled, health full, statuses cleared, respawn point set (per character, saved). Nearby cleared camps are not reset by resting.
- Travel: from a lit shrine to any other lit one in the same realm (the map panel in travel mode); uses `TerrainChunks.ensure_around` like gates. Realm gates stay the way between realms.
- Flask: a gear slot item with charges (3 at first; more through shrine upgrades found in crypts, M60). Drinking is an action with a wind-up that can be hit; charges are rolled back state on the player (one byte).
- Death: respawn at the last rested shrine instead of the arrival; the grave and body run stay.

## Tasks

1. **Sites, lighting, rest and respawn (Opus).** New `sim/shrine_site.gd`, `sim/scatter.gd` and `sim/spawner.gd` (keep clear), `net/game_server.gd`, `sim/sim_player.gd` (`_respawn`), `sim/world_save.gd`; tests.
2. **Flask (Opus).** The drink action, charges in `STATE` and `wire.gd`, the gear slot; tests; `Net.PROTOCOL_VERSION`; load test.
3. **Travel, views, bots, close (Sonnet).** Map travel mode, shrine look and light, rest animation, HUD flask; bots drink and rest; suite; play-test items.

File level detail is added when the milestone before it lands (`docs/milestones/README.md`).

## Out of scope

Leveling at shrines. Enemies respawning on rest. Player-built travel points (M64 could add them).

## Pitfalls

- A respawn point far from the grave makes body runs long: the grave marker on the map matters.
- Travel moves a player far in one tick: bump `respawns` so views snap, as gates do.
- Sites must not land on the boss disc, camps or the arrival ring.
