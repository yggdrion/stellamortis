# M43 Minimap, compass and map

Status: Planned.

## Goal

Players always know where they are: a small round minimap in a corner, a compass bar on top, and a big map that points north with only the player's arrow turning. Walking goes on while the big map is open.

## Depends on

M33 (map panel, projection, terrain image). Independent of M41 and M42. Client only: nothing in `sim/` rolls back or syncs differently, `Net.PROTOCOL_VERSION` stays.

## Design

- **North is a fixed point on the realm, not the image's pole.** The terrain image's pole is world +Y (`MapPanel.image_direction`), and `RealmDef.arrival` is `Vector3(0, 1, 0)`: exactly that pole, where players start. A north taken from +Y would be undefined at the arrival. So `RealmDef` gets `@export var north_pole := Vector3.BACK` (a unit direction from the center; set explicitly in `data/realms/barrowlands.tres`), and north at a direction `d` is the tangent at `d` pointing along the great circle toward it: `(pole - d * d.dot(pole)).normalized()`. It is defined everywhere except at the pole and its antipode (+Z and -Z of the realm, 1571 m of ground from the arrival, never near the boss site at 450 to 800 m); there `Layout.north` falls back to `Vector3.UP` projected on the tangent plane. +Z is also the way a new player faces at the arrival (`Layout.arrival_spot` and the spawn face `+Z`), so everyone starts looking north. The image and `shaders/map.gdshader` do not change for this: they take the heading as a uniform. East is `north.cross(up)` (the same right-hand side `MapPanel.project` uses, `heading.cross(center)`).
- **Two directions, not one.** `MapPanel._forward` (the camera's ground heading) is used today as the projection heading, so the map turns with the camera. After M43 the projection heading is `_north`; the camera heading stays as `_look` and only turns the own arrow and the compass. `bearing = atan2(look.dot(east), look.dot(north))` (radians, clockwise from north, 0 = north, PI/2 = east), a pure `Layout.bearing(direction, north, ahead)` in `sim/layout.gd`.
- **Big map, walking:** `GameClient` does not block movement while the map is open through `covered` (that only hides the interaction prompt at line ~465). Movement stops because holding M sets `Input.mouse_mode = MOUSE_MODE_VISIBLE` and `_read_controls` returns early whenever the mouse is not captured. That early return is what changes: with the map open (and no pause menu or inventory panel open) it reads move, jump, sprint and roll, and still never reads attack, heavy or block. The camera does not turn (`_rig.look` only runs with a captured mouse), `controls.yaw`/`pitch` stay the camera's, so movement is relative to where the camera pointed when M went down; releasing M gives the mouse back as today. M stays a hold key (a toggle and panning are out of scope). A pure helper `GameClient.input_scope(captured, map_open, other_open) -> int` decides (an `InputScope` value) (`enum InputScope { NONE, WALK, FULL }`), so a test can cover it without a client.
- **Minimap: its own small control over the same shared pieces.** `MapPanel` today builds the terrain image only while the big map is visible (`_follow` runs from `_process` only when `visible`, and it finishes the `Job`). So the image build and lookup move into static functions on `MapPanel`: `texture_for(realm, world_seed) -> Texture2D` (null while building) which requests the `Job`, finishes it and caches the `ImageTexture` in the existing static `_textures`. The big map and the minimap both call it; there is still one image per realm and seed, built on workers; whoever asks first starts it, so with the minimap on the image is ready before M is ever pressed. `Minimap` (`client/minimap.gd`, a `Control`) owns a `ShaderMaterial` on `shaders/map.gdshader` (same shader, same `Shader` resource), calls `MapPanel.project` for its markers and does not call `Spawner.points` (about 1 s in a debug build; camps are not on the minimap). It is north-up with the own arrow turning, `Minimap.SPAN` 200 m across (the server wakes camps within `Spawner.WAKE` 90 m, so the wake ring fits), `Minimap.SIZE` 180 px, drawn as a circle: the shader gets `uniform bool circle = false;` that returns transparent for `length(p) > view_size.x * 0.5` (the big map leaves it false), and a ring and a small "N" tick are drawn in `_draw`. Markers: the own arrow, other players, awake enemies (`MapPanel.KIND_COLORS`, no `HIDDEN`), gates (`Layout.portals()` of the realm) and the boss site, drawn by `project` against the minimap's own zoom; markers beyond the rim stick to it. Hidden while the big map is open, when `Settings.minimap` is off, outside a realm, (it keeps showing when the player is dead). Top right under the room code label (offset 48 px from the top; the label sits at 16 px).
- **Compass bar:** `Compass` (`client/compass.gd`, a `Control` of 480 by 30 px, top center at 8 px). It shows a 180 degree window around the camera's bearing (2.67 px per degree): the letters N, E, S, W at 0, 90, 180, 270, a tick every 15 degrees, long every 45, the bearing as a number in the middle. Markers sit at their bearing from the player with a distance in meters: the arrival (the ring `Terrain.surface(realm, seed, realm.arrival)`; it is where the gate will stand, so the glyph is a small square in `MapPanel.GATE` and the label "arrival"), gates of `Layout.portals()` in the realm, the boss site (`BossSite.at(realm, seed).center()`, `MapPanel.SITE`, greyed once `Encounter.flag_set` says the Warden has fallen). A marker outside the window shows as an arrow at the edge. Pure statics `Compass.wrap(angle)` (to (-PI, PI]) and `Compass.offset(bearing, target_bearing)` carry the geometry. The HUD's top box (`top`, the goal label, boss bar and warning) moves down from 20 to 52 px so it does not sit under the compass. Open for later milestones: M54's pings and M56's downed allies add markers through the same list of `[direction, color, label]` entries (`Compass.markers()` builds it).
- **HUD wiring:** `Hud` gets `minimap` and `compass` (like `hotbar`, `weapon_bar`), both with `me`, `camera` and `world` set in `GameClient` next to `_map.camera`/`_map.me`. `Hud._process` hides both while `_map.visible`: `Hud` has no reference to the panel, so `GameClient._process` sets `_hud.minimap.visible`/`compass.visible` from `_map.visible` and `Settings.minimap` (the compass stays on in the setting; only the minimap has one).

## Tasks

### 1. North and the big map (Sonnet; built 2026-11-18, checks green)

Files:

- `scripts/sim/realm_def.gd` (`north_pole`), `data/realms/barrowlands.tres` (`north_pole = Vector3(0, 0, 1)`), `scripts/sim/layout.gd`: `static func north(realm: RealmDef, direction: Vector3) -> Vector3` (pure; fallback at the poles) and `static func bearing(direction: Vector3, north: Vector3, ahead: Vector3) -> float` next to `realm_at`.
- `scripts/client/map_panel.gd`: `_follow` computes `_north = Layout.north(_realm, _center)` and a separate `_look` from the camera (today lines ~220 to 226, where `_forward` is the camera tangent); everything that passes `_forward` to `project`/`unproject` or the shader's `forward_dir`/`right_dir` (`_screen`, `_draw_camps`, `_distance_to`, the uniforms) takes `_north` instead. `_draw_players`: the own arrow's three points are rotated by `Layout.bearing(_center, _north, _look)` with `Vector2.rotated` (positive is clockwise on screen). Move the image request and `Job` finishing out of `_follow` into `static func texture_for(realm, world_seed) -> Texture2D` (reuses `_request_image`, `_jobs`, `_textures`, which become static helpers). The `_forward` smoothing line (`_forward = (_forward - _center * ...)`) goes. The class doc comment ("turned so the camera looks up") becomes "north up". The legend gets a "N" mark at the top of the frame.
- `scripts/client/game_client.gd`: `enum InputScope { NONE, WALK, FULL }`, `static func input_scope(captured: bool, map_open: bool, other_open: bool) -> int` (captured: FULL; else map open and nothing else open: WALK; else NONE); `_read_controls` uses it: NONE returns as today, WALK reads move, jump, sprint, roll and no attack, heavy or block, FULL as today. `other_open` is `_pause.visible or _panel.visible`. The comment at the M key ("the player stands still") goes.
- `docs/PLAYTEST.md` line ~105 to 108 (the map text says the camera's forward is up and the player stands still): rewritten for north-up and walking, in task 3.

Reuse: `MapPanel.project`/`unproject` and the shader unchanged (heading is already a parameter), `SimPlayer._tangent(vector, up)` for projecting the camera's `-basis.z` on the ground plane, `Terrain.surface` for the arrival.

Tests (`tests/map_test.gd`; it has 3 public methods and the 20 limit is far):

- `test_north_is_a_unit_tangent_everywhere_but_at_the_pole`: for `Terrain.sample_directions(200)` skipping those within 0.001 of +Z/-Z: unit length, perpendicular to the direction (|dot| < 0.0001), and `north.dot(pole) > 0` (it points toward the pole).
- `test_north_falls_back_at_the_pole`: at +Z and -Z the result is still a unit tangent, not NaN.
- `test_arrival_is_not_at_a_pole`: `Layout.start_realm().arrival` is at least 0.5 rad from the pole (the +Y pole of the image is the arrival: a north from the image's axis would fail here).
- `test_bearing_is_clockwise_from_north`: ahead = north gives 0, east (`north.cross(up)`) PI/2, south PI, west -PI/2; the camera yaw turning leaves `north` unchanged but changes the bearing by the same angle.
- `test_the_projection_does_not_turn_with_the_camera`: a fixed target projects to the same point from `project(center, north, d, z)` however the look direction turns (the map's heading is north, so the test passes `Layout.north` and rotated looks and compares).
- `test_input_scope`: (captured) FULL; (not captured, map open, nothing else) WALK; (not captured, map and pause open) NONE; (not captured, no map) NONE.

Done when: checks green; screenshots `--seed=1234 --spawn=2500,1004,1800 --map` with `--look=0,-6` and `--look=90,-6` show the same map and the arrow turned; a `--bot --bot-plan` run is unaffected (`python tools/check.py` smoke).

### 2. Minimap (Sonnet)

Files: new `scripts/client/minimap.gd`; `shaders/map.gdshader` (`uniform bool circle = false;` and the one early return); `scripts/client/map_panel.gd` (`texture_for` is task 1; make `KIND_COLORS`, `GATE`, `SITE`, `FRIEND`, `OWN` usable from outside, they already are consts); `scripts/client/hud.gd` (`minimap` var and the node in `_ready`, top right at 48 px under `_room`); `scripts/client/settings.gd` (`static var minimap := true`, `[display] minimap` in `load_saved` and `save`, next to `vsync`); `scripts/client/settings_panel.gd` ("Minimap" CheckBox with `Menus.row`, `_on_minimap`, saved like `_on_vsync`); `scripts/client/game_client.gd` (set `_hud.minimap.me`, `camera`, `world`; visibility from `_map.visible` and `Settings.minimap` in `_process`).

Steps: the shader mask first and see the big map is unchanged; `Minimap._process` finds the realm (`Layout.realm_at(me.global_position)`), `MapPanel.texture_for`, sets the uniforms (`center_dir`, `forward_dir` = north, `right_dir` = `north.cross(center)`, `zoom` = `SIZE * 0.5 * (TAU * radius) / SPAN`, `view_size`, `realm_radius`, `image_size`, `circle`, `ready`, `heights`), `queue_redraw` for the markers only; markers through `MapPanel.project` with the same formula as `MapPanel._screen`, clamped to the rim. Keep the markers' loop free of allocations beyond the arrow polygon.

Tests: `tests/minimap_test.gd`: `test_minimap_zoom_puts_the_rim_at_half_the_span` (a point `SPAN / 2` meters north along the ground projects to `SIZE / 2` px above the center, within a pixel); `test_minimap_is_hidden_outside_a_realm_and_with_the_setting_off` (a bare `Minimap` with `me` far from any realm, and with `Settings.minimap = false` through the HUD's visibility rule); `settings_test.gd`: `Settings.minimap` round trips through the config file and defaults to on.

Done when: checks green; a screenshot at the arrival (`--seed=1234`, no flags) shows the minimap top right with the ring of stones and the dummies as dots; the image appears without opening the map; the minimap costs nothing measurable (frame time with it on and off within noise: `STELLAMORTIS_FRAME_STATS=5`).

### 3. Compass, close (Sonnet)

Files: new `scripts/client/compass.gd`; `scripts/client/hud.gd` (`compass` var, node top center at 8 px, `top` box margin 20 to 52); `scripts/client/game_client.gd` (set `me`, `camera`, `world`); `docs/PLAYTEST.md` (the map text of M33 task 1 updated, M43 items below); `CLAUDE.md` "Where we are" (M43 built, Next becomes M44 and M45; the map entry says north-up); `docs/PLAN.md` §6 and §8; `VERSION` minor +1.

Steps: `Compass._draw` with `draw_line`, `draw_string` (font from `get_theme_font("font", "Label")` like `MapPanel`), markers from `Compass.markers()`, the arrival marker from `Terrain.surface` once per realm and seed (cache the direction in `_process` when the key changes), the boss site from `BossSite.at`.

Tests: `tests/compass_test.gd`: `test_wrap_keeps_angles_in_half_open_range` (`wrap(3 * PI)` is PI, `wrap(-PI)` is PI, `wrap(0.1)` unchanged); `test_offset_takes_the_short_way` (bearing 350 degrees to a target at 10 degrees is +20 degrees); `test_markers_include_arrival_and_boss_site_in_the_start_realm` (two entries; the boss site's bearing equals `Layout.bearing` of `BossSite.at(...).direction`).

Play-test items to add to `docs/PLAYTEST.md` under "M43 Minimap, compass and map":

- [ ] The compass shows N, E, S, W and ticks; turning the camera slides it; at the start you face north (the N in the middle) and the arrival marker is at your back (about 180 degrees, a few meters), the boss site marker 450 to 800 m away.
- [ ] The minimap shows the ring of stones, the dummies and any awake enemy as dots around you, north up, only your arrow turns; it is hidden while M is held and comes back on release.
- [ ] Hold M and walk with WASD, Shift, Space and the roll key: you move, the camera does not turn, attack and block do nothing; releasing M gives the mouse back.
- [ ] The map keeps north up when you turn; the same hill is in the same place whichever way you face.
- [ ] Settings has a "Minimap" check box; off hides the minimap, the compass stays; it is remembered after a restart.
- [ ] At 1280 by 720 the compass, the minimap and the room code label do not overlap each other, the goal text or the boss bar.

Done when: checks green; screenshots of the HUD with the compass and minimap (`--seed=1234 --delay=6 --screenshot=PATH`) at 1280 by 720 and 1920 by 1080, and the map open (`--spawn=2500,1004,1800 --map`); play-test items written; status "Built (date, release), play-test pending" here and in `docs/PLAN.md` §6; `CLAUDE.md` updated.

## Out of scope

Fog of war and explored areas, map pins (M54), panning the big map by drag, a toggle instead of hold for the map, turning the camera while the map is open, zoom on the minimap, a compass setting.

## Pitfalls

- `RealmDef.arrival` is the image's pole (+Y). North must not come from the image's axis (it is undefined at the arrival); it comes from `north_pole` (+Z).
- Do not touch `covered` to enable walking: it only hides the prompt. The block is `_read_controls`'s early return on the mouse mode; keep that for the pause menu and the inventory panel.
- `MapPanel._follow` is the only place that finishes the image `Job` and runs only while the big map is visible: the minimap would never get an image (and a second panel must not build its own) unless `texture_for` moves out first (task 1).
- `Spawner.points` (about 1 s in a debug build) runs on the map's first open; the minimap must not call it.
- Redrawing the minimap's terrain every frame on the main thread costs: the terrain is the shader (uniforms only); only markers are drawn.
- Walking with the map open must not send attack, heavy or block; camera look is already off with a free mouse.
- Keep both shader users in step: `circle` defaults to false so the big map is untouched.
- The compass window and the top box share the screen's top: check the boss bar and the "No word from the host" warning at 1280 by 720.
