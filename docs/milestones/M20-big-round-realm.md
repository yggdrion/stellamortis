# M20 Big round realm

Status: planned.

## Goal

The first generated realm: the Barrowlands, a round world of 1000 m radius with hills, moor and stone, reached through a gate in the keep. It must feel like land, not a ball. Every peer builds the same ground from the world seed.

## Depends on

Nothing. The hand-built realm at the origin and its encounter stay untouched until M22.

## Design

- `RealmDef` (data): `id`, `center`, `radius`, `gravity`, `seed_salt`, `biome`, `arrival` (a direction). Realms are listed in `Layout.realms()`. The Barrowlands sits within 6 km of the origin, far enough from the old realm and the hub that nothing overlaps (centers at least radius + 500 m apart).
- `Terrain.height(realm, direction) -> float`: a pure static function. Seeded `FastNoiseLite` (several octaves, sampled in 3D at `direction * radius`, so there is no seam), shaped into moor, hills and a few ridges, quantized to 1 cm. No other source of height exists.
- Cube-sphere: 6 faces, each a grid of chunks. A chunk is identified by `(face, x, y)`; its vertices are `direction * (radius + height)`. Start with chunks of about 64 m and 2 m cells; both are constants to tune.
- Collision: one `StaticBody3D` with a `ConcavePolygonShape3D` per chunk on the world layer. `TerrainChunks` keeps the chunks around a set of anchor points alive (server: every player and every awake enemy; client: the own player) and frees the rest.
- Gravity: one `GravityZone.sphere` per realm, pulling to the center, reaching to radius + 300 m.
- View (client only): near chunks get meshes with normals; beyond them a coarse shell mesh of the whole realm (same height function at low resolution) so the horizon is never empty.

## Tasks

### 1. World seed handshake (Opus)

Files: `game/scripts/net/net.gd`, `net/game_server.gd`, `client/game_client.gd`, `sim/world.gd`, `scripts/boot/main.gd`, `game/tests/` (network test scripts under `tools/`).

Reuse: the `room` RPC pattern (`net.gd:48`, sent in `GameServer._on_hello`, `game_server.gd:210`).

Steps:

1. `GameServer.world_seed` (int) and `world_name`; `--seed=N` and `--world=NAME` flags, passed on by solo and host like `--spawn`. Without a flag the seed is random.
2. `Net.world(seed, name)` reliable, server to client, sent in `_on_hello` before the clock sync wait.
3. `World`: keep the node and its `MultiplayerSpawner` created in `_ready` (netfox and the spawner find nodes by path), but move everything generated behind `World.build(seed)`. The server calls it at start; the client calls it when `Net.world` arrives. The server must not spawn the player before the client has built: the client answers `Net.world_ready()`, and `_on_hello` waits for it as it waits for the clock sync.
4. Bump `Net.PROTOCOL_VERSION`. The joining screen (`MainMenu` "Joining room ...") stays up until the world is built.

Tests: the headless network test still passes (ENet with lag, WebRTC); a new gdUnit test builds `World` twice with the same seed and gets the same `Terrain` hash once task 2 exists (add it there).

### 2. Realm data and the height function (Opus)

Files: new `sim/realm_def.gd`, `sim/terrain.gd`, `game/data/realms/barrowlands.tres`, `sim/layout.gd`, new `tests/terrain_test.gd`.

Steps:

1. `RealmDef` resource and `Layout.realms()`, `Layout.realm_at(point)` (nearest center within reach, null on the hub or the old realm).
2. `Terrain.height`, `Terrain.surface(realm, direction) -> Vector3`, `Terrain.normal`.
3. `Terrain.chunk_arrays(realm, face, x, y) -> PackedVector3Array` (triangles), built without touching the scene tree so it can run on a worker thread.

Tests: fixed seed gives a fixed hash over 10 000 sampled heights (guards against accidental changes and platform differences; run it on CI's three platforms); two different seeds differ; neighbouring chunks share their edge vertices exactly, also across cube faces; slopes stay under the walkable limit on most of the surface (report the share).

### 3. Streamed collision (Opus)

Files: new `sim/terrain_chunks.gd`, `sim/world.gd`, `sim/sim_player.gd` (gate travel only), new `tests/realm_walk_test.gd`.

Reuse: `SimPlayer.place` (`sim_player.gd:202`), `SimPlayer._use_portal` (`:572`), `WorkerThreadPool`.

Steps:

1. `TerrainChunks` node under `World`: each physics frame it takes anchor points, queues missing chunks within `LOAD_RADIUS` (about 150 m), builds their arrays on `WorkerThreadPool`, and adds at most a budgeted number of bodies per frame on the main thread; chunks beyond `UNLOAD_RADIUS` are freed.
2. A chunk under a body must exist before the body gets there: `LOAD_RADIUS` must exceed the distance a sprinting or launched body covers in the build time; assert in debug builds when a player is over a missing chunk.
3. Gate travel: the server builds the destination chunks before `_use_portal` moves the player (build them synchronously for the arrival point: a handful of chunks). On the client the predicted teleport lands before chunks exist: build the arrival chunks of every realm at `World.build`.
4. Server anchors: players and awake enemies (M21 passes enemies; for now players).

Tests (`realm_walk_test.gd`, modelled on `tests/asteroid_test.gd`): a player walks 500 m along a great circle and never falls below the surface; walks across a cube face edge; a jump lands; chunks behind the player are freed; replaying the same input from a rolled back state gives the same position (chunks are static, but the test proves streaming does not disturb determinism).

### 4. Any-up fixes and the gate (Opus)

Files: `sim/layout.gd`, `sim/portal.gd`, `sim/arena.gd`, `sim/gravity.gd`, `client/player_view.gd`, `client/game_client.gd`, `client/sounds.gd`.

Steps:

1. `Layout.gravity_zones()` adds one sphere per realm.
2. `Portal.reaches` (`portal.gd:30`) and `Layout.ring_point` (`layout.gd:116`) work in the tangent plane of the local up instead of XZ.
3. `Arena._prop` takes a basis (`SimPlayer.frame(up, forward)`) instead of a yaw.
4. `Layout.on_hub`, `Arena.show_planet` and `Arena.shows` become "which place is this point in" (hub, old realm, realm id); views, ambience (`Sounds.ambience`) and the footstep surface test (`player_view.gd:142`) use it.
5. A second gate in the keep leads to the Barrowlands' arrival point; a gate there leads home. `Layout.portals()`.

Tests: gravity test for the realm zone; portal reach on a tilted up; `encounter_test.gd` and `asteroid_test.gd` still pass.

### 5. The look (Sonnet)

Files: new `client/terrain_view.gd`, `sim/arena.gd`, `client/graphics.gd`, `docs/RESOURCES.md`, `game/assets/`.

Reuse: `Arena._surface` (triplanar world mapping works on a sphere), `Arena._add_environment`, `Graphics` presets, `MultiMeshInstance3D`.

Steps:

1. Near chunk meshes (from `Terrain.chunk_arrays`, with normals and a slope and height blend between grass, heather and rock materials) and the far shell.
2. Scatter from the seed, per chunk, on the client only: pines, birches, boulders, standing stones, burial mounds. CC0 models that fit the grim look (search first; record them). Scatter is visual in M20; trees and rocks get collision and health in M25, so place them through one seeded function `Scatter.points(realm, chunk)` that M25 can reuse in the sim.
3. Fog, a cold night sky, the moon; view distance and scatter density per graphics preset.
4. Frame time on Low and High stays within the M12 numbers in `docs/PLAN.md` §3.1 (measure, report).

Done when: screenshots from the arrival point, a hilltop and a valley; the user's play-test says it reads as land and not as a ball. If it does not, raise `radius` and hill height before touching anything else.

## Out of scope

Enemies on the realm (M21). Resources (M25). Water. Caves. Biome borders (one biome per realm).

## Pitfalls

- Float determinism: never derive collision from mesh data or from anything client side. Only `Terrain.height`. Quantize before building vertices.
- `ConcavePolygonShape3D` is static only and has no inside: a body that tunnels through stays under. Keep the debug assert from task 3.
- `SimPlayer._step_up` uses `test_move`; check it on slopes so a steep hillside is not climbed as stairs.
- The client builds `World` itself (`game_client.gd:89`); nothing about terrain is sent except the seed.
- 32 bit floats: at 6 km from the origin the step is about 0.5 mm. Check for jitter at the realm's far side in the walk test; if it shows, move the realm closer or shrink the radius before considering double precision builds.
