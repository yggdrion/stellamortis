# M33 Map

Status: Planned.

## Goal

A map panel (M) shows the realm a player stands on, with the terrain, the player and the group, awake enemies, camps and roamer points, gates and, after M22, the boss site. It is a debug tool first (asked for on 2026-11-15 to check spawns, enemies and gates); a player map with explored areas comes later.

## Depends on

M20 (realms, `Terrain`, world seed), M21 (`Spawner.points`, enemy pool). Comes before M22 so the bestiary and boss site can be checked on it.

## Design

- Client only, nothing new in the sim or on the wire. Everything shown is already known on the client: the terrain and spawn points are pure functions of realm and seed (`Terrain.height`, `Spawner.points(realm, world_seed)`), gates come from `Layout.portals()`, and players and enemies are nodes in `World` (the hidden slots skipped).
- Projection: azimuthal equidistant, centered on the player's direction from the realm center and turned so the camera's forward points up. One projection covers the whole sphere: the player at the center and the far pole on the rim. Zoom with the wheel, from about 150 m across to the whole realm.
- Terrain image: once per realm and seed, an equirectangular height and slope shade (about 1024 x 512 from `Terrain.height`), built on a WorkerThreadPool task. A shader on a `TextureRect` does the inverse projection per pixel and samples that image, so moving and turning cost nothing on the CPU.
- Markers are drawn on top in `_draw`, through the forward projection: players (own one is an arrow), awake enemies colored by kind, spawn points (camps as rings with their size, roamers as dots), gates with their names. A legend and the zoom level sit in a corner. Hovering a marker shows its details: kind, slot index, action, camp id, distance.
- Off a realm (the keep, the old realm) the panel shows "No map here".
- The panel is open only while M is held or toggled (a setting); it does not pause the game.

## Tasks

### 1. The map (Sonnet)

Files: new `game/scripts/client/map_panel.gd`, new `game/shaders/map.gdshader`, `client/controls.gd` (`map` action on `KEY_M`), `client/game_client.gd` (open and close in `_unhandled_input`), `client/hud.gd` if the panel lives under it, new `game/tests/map_test.gd`.

Reuse: `Terrain.height`, `Layout.realm_at`, `Layout.portals()`, `Spawner.points`, `Combat.ENEMY_KINDS`, `Menus.theme()` for the frame and fonts.

Steps: the terrain image job and its cache per realm id and seed; the projection functions (static and pure: world point to map point and back, for a center direction, a heading and a zoom); the shader; the markers, legend and hover; zoom with the wheel.

Tests (`tests/map_test.gd`): the projection round-trips points in every direction except the antipode; the center maps to the middle, a point 90 degrees away lands at half of the full-realm radius; the terrain image of the same seed is the same.

Done when: screenshots (`--seed=1234 --spawn=2500,1004,1800`, the map open, close and fully zoomed out) show the terrain, the arrival gate and the camps around it; `docs/PLAYTEST.md` gets the checks a person must make.

### 2. Debug details (Sonnet)

Files: `client/map_panel.gd`, `sim/spawner.gd` (read only), `docs/PLAYTEST.md`.

Steps: in solo and when hosting, also show what only the server knows (the client runs in the same process as the server only in tests, so read it through a small debug RPC that is sent only with `--debug-map` or in builds that are not exported): cleared camps and their timers, the `WAKE` and `SLEEP` rings around each player. Skip the task if the RPC turns out to need state changes in the sim.

## Out of scope

Explored areas and fog of war, map pins, a compass bar, the map in exported builds as a player feature (after M23, when there is something to find).

## Pitfalls

- The realm's up at the player is not world up: build the projection from the player's direction from `realm.center` and `ref_forward`, as `CameraRig` does.
- `Terrain.height` costs real time per call; 500 000 samples on the main thread would freeze the frame. Build on a worker and show the markers alone until the image is ready.
- The antipode is a single point that maps to the whole rim; clamp there.
