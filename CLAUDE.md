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
- **Boot:** `scripts/boot/main.gd` picks the role from args. No args: spawns `--server --solo` on a free port and joins it (solo exits when its player leaves). `--connect`, `--bot`, `--screenshot=PATH` (saves a PNG after 4 s and quits; use it to check visuals). Fake latency: `tools/lag_proxy.py` (UDP proxy, `dev.py --lag=MS`, the network test uses 100 ms + 20 ms jitter).
- **Netcode:** netfox (`game/addons/netfox`, `netfox.internals`, installed by `tools/install.py` from `NETFOX_COMMIT`, gitignored; autoloads and `[netfox]` settings live in `project.godot` because the editor plugin never runs headless). Tick 30 Hz, `sync_to_physics`. Read the netfox docs (https://foxssake.github.io/netfox/, rollback caveats first) before adding rollback state. `SimPlayer.networked(peer)` adds `Controls` (input, owned by the peer), `Rollback` (`RollbackSynchronizer`, state `SimPlayer.STATE`) and on clients `Interpolator`. `sim/world.gd` (`/root/Main/Game/World`, same path on both sides) holds the arena, `Players` and the `MultiplayerSpawner`. `net/net.gd` keeps only our RPCs (`Net.PROTOCOL_VERSION`, bump on change, also when netfox state or input changes).
- **Server tick loop:** with 150 ms lag one sample showed a 9 ms max tick loop (rollback resimulation; was 0.6 ms without netfox). Watch it in M7.
- **Movement:** `sim/sim_player.gd`. Players move in the plane of `up`, which follows `Gravity.sample` (`sim/gravity.gd`, constant until M1); `ref_forward` is carried along when `up` turns, and input yaw and the camera yaw (`client/camera_rig.gd`) are measured from it. `grounded` is our own floor flag, part of the rolled back state. Players do not collide with each other (layers: 1 world, 2 players). Numbers in `data/tuning.tres` (`Tuning.data()`).
- **Arena:** `sim/arena.gd`, built in code; collision on both sides, meshes, sun, sky and environment (AgX, SSAO, SSIL, glow, fog) on clients only.
- **Release:** `.github/workflows/release.yml` on every push to `main` (and by hand): check, export per platform on its own runner (`tools/export.py`, presets in `game/export_presets.cfg`), artifacts kept 3 days (`ARTIFACT_DAYS`), then a GitHub Release `v<VERSION>.<run number>` with three zips. Exported builds spawn themselves as the solo server (`OS.has_feature("template")` in `main.gd`).
- **Physics:** Jolt, 30 ticks per second, Godot physics interpolation off (netfox `TickInterpolator` instead). Renderer Forward+ (Vulkan on Linux), SMAA.
