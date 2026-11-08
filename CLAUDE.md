# CLAUDE.md

`docs/PLAN.md` is the source of truth for scope, design, architecture and milestones; read it before starting work. Setup, run and check commands are in `README.md`.

Stellamortis reuses patterns and code from `../jotra` (lobby, transport, tooling, the "client always spawns a server" design). Read the matching jotra code before writing a new version of it, but stellamortis is 3D and its gameplay code is new.

Use Godot 4.7 (latest 4.7.x patch) and its newest features for performance and visuals (`docs/PLAN.md` §3.1). Check each engine feature against the 4.7 docs and migration guide instead of relying on older Godot 4 habits. A quick way to check that a class, constant or setting exists: a `extends SceneTree` script run with `godot --headless -s`.

Run `python tools/check.py` (lint, gdUnit4, headless network test) before calling work done. GDScript is statically typed; `enum` names must not shadow native classes (`Button` did).

Every commit is a semantic commit (`type(scope): summary`, Conventional Commits; see the `semantic-git` skill). PR titles too. Pushing to `main` publishes a release (see Release below).

## Where we are

Keep this section current when a milestone finishes or what's next changes.

- **Done:** M0 skeleton (2026-11-09), release pipeline.
- **Next:** M1 gravity zones.
- **Boot:** `scripts/boot/main.gd` picks the role from args. No args: spawns `--server --solo` on a free port and joins it (solo exits when its player leaves). `--connect`, `--bot`, `--lag=MS` (fake latency in `Net.later`), `--screenshot=PATH` (saves a PNG after 4 s and quits; use it to check visuals).
- **Net:** `scripts/net/net.gd` holds every RPC and the packing (`Net.PROTOCOL_VERSION`, bump on change). Clients send the last 4 `PlayerInput`s each tick (9 bytes each); the server (`game_server.gd`) runs every received input in order and sends a snapshot per peer per tick (tick, acked input tick, `PlayerState` per player, 61 bytes each, f32, not quantized yet).
- **Prediction:** `client/game_client.gd` steps its own `SimPlayer` each physics tick, keeps `[input, state]` history, reconciles in `_physics_process` (never in `_process`: `move_and_slide` reads the physics delta only inside a physics frame). Remote players render `INTERP_TICKS` (3) behind the newest snapshot. The network test shows 0 corrections at 100 and 250 ms lag.
- **Movement:** `sim/sim_player.gd`. Players move in the plane of `up`, which follows `Gravity.sample` (`sim/gravity.gd`, constant until M1); `ref_forward` is carried along when `up` turns, and input yaw and the camera yaw (`client/camera_rig.gd`) are measured from it. `grounded` is our own floor flag so it can be restored from a server state. Players do not collide with each other (layers: 1 world, 2 players). Numbers in `data/tuning.tres` (`Tuning.data()`).
- **Arena:** `sim/arena.gd`, built in code; collision on both sides, meshes, sun, sky and environment (AgX, SSAO, SSIL, glow, fog) on clients only.
- **Release:** `.github/workflows/release.yml` on every push to `main` (and by hand): check, export per platform on its own runner (`tools/export.py`, presets in `game/export_presets.cfg`), artifacts kept 3 days (`ARTIFACT_DAYS`), then a GitHub Release `v<VERSION>.<run number>` with three zips. Exported builds spawn themselves as the solo server (`OS.has_feature("template")` in `main.gd`).
- **Physics:** Jolt, 30 ticks per second, physics interpolation on. Renderer Forward+ (Vulkan on Linux), SMAA.
