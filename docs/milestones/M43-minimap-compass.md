# M43 Minimap, compass and map

Status: Planned.

## Goal

Players always know where they are: a small minimap in a corner, a compass bar on top, and a big map that points north with only the player's arrow turning. Walking goes on while the big map is open.

## Depends on

M33 (map panel, projection, terrain image). Independent of M41 and M42.

## Design

- North: every realm gets a fixed north, a pure function of the direction from `realm.center` (the realm's pole axis projected on the tangent plane). `MapPanel.project`/`unproject` already take a `heading`; today they get the player's `_forward`, so the map turns with the player. Pass north instead; the player's arrow turns by its yaw against north. At the pole north is undefined: use a fallback axis there.
- Big map: hold M as today, but movement keeps working while it is open (`GameClient` counts the map as covering and stops the controls). The mouse stays free, so the camera does not turn; attacks stay off.
- Minimap: the same panel in a small round mode in a HUD corner, north-up, about 150 m across, the same terrain image, players, awake enemies and gates; hidden while the big map is open; a setting hides it.
- Compass bar: top of the HUD, N, E, S, W and ticks from the camera yaw against north, markers for the arrival gate and the boss site; M54's pings and M56's downed allies add their markers later.

## Tasks

1. **North-up map and walking (Sonnet).** `client/map_panel.gd`, `client/game_client.gd`, `sim/layout.gd` (a pure `north(realm, direction)`); `tests/map_test.gd` (north is a unit tangent everywhere but at the pole; the map does not turn when the player turns).
2. **Minimap (Sonnet).** A compact mode of `client/map_panel.gd` (or a small `client/minimap.gd` reusing its projection and image), `client/hud.gd`, `client/settings.gd`.
3. **Compass, close (Sonnet).** `client/compass.gd`, `client/hud.gd`; screenshots (`--seed=1234 --spawn=2500,1004,1800`, the map open and closed); play-test items; milestone closed.

## Out of scope

Fog of war and explored areas, map pins (M54), panning the big map by drag.

## Pitfalls

- The minimap must not build its own terrain image: share the big map's, built on a worker.
- Redrawing the minimap's image every frame on the main thread costs; move it by a shader uniform and redraw only the markers.
- Walking with the map open must not send camera look or attack input.
