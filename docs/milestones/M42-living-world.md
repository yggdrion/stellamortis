# M42 Living world

Status: Planned.

## Goal

The world moves and breathes: trees and grass sway in the wind, water lies in the low ground, embers, motes and mist drift, and the light is tuned so the faceted look is moody instead of plain. This is the polish pass that makes the generated world feel finished.

## Depends on

M37 (scatter and ground cover), M41 (wind strength and direction, sky and light). M57 (Myrkfen) needs this milestone's water.

## Design

- **Wind sway** in `shaders/flat.gdshader`'s vertex function (the hook M36 left): displacement grows with height above the instance's base and with a per-vertex sway weight stored by the generators (trunk 0, limbs low, crown and blades high), phased by world position so a gust travels. Strength and direction come from `Weather` as global shader uniforms. No CPU work per instance.
- **Grass** bends away from players and enemies near the camera: positions of the nearest few bodies as a small uniform array.
- **Water** (`shaders/water.gdshader`, `scripts/client/water_view.gd`): flat-shaded, slowly moving facets, dark with a pale rim where it meets the ground (depth fade), reflections from the sky color only. Where water stands is a pure function of the terrain (below a realm's `water_level`, data in `RealmDef`), so the sim can use it later; in this milestone it is look only and the Barrowlands gets a few tarns and bog pools.
- **Ambient particles** per place and weather, pooled like `HitEffects`: embers at torches and the boss site, motes in old wood, low mist in hollows at dawn, leaves in a gale.
- **Light pass:** rim light from the sky on faceted shapes, torch flicker and reach, shadow softness and SSAO strength chosen for flat shading (SSAO on facets can look dirty), fog color from the palette per phase, the glow threshold so only meaning colors bloom. Per `Graphics` preset; measured on the 1050 Ti.
- **Footing:** dust or splash puffs under feet by ground role, and footstep sounds by ground role (`Sounds`), now that the ground knows its role.

## Tasks

1. **Wind and grass (Sonnet).** Sway weights in `MeshKit` and the tree and cover generators, the shader, the global uniforms, the body positions.
2. **Water (Opus).** `RealmDef.water_level`, the pure "is water here" function with a test, the water mesh per chunk on workers, the shader. Opus because it touches terrain chunks and a function the sim will rely on.
3. **Particles, light, footing, close (Sonnet).** The pools, the light pass per preset with before and after screenshots and frame times, footing effects, play-test items, milestone closed.

File level detail is added when M41 lands.

## Out of scope

Swimming, wading speed and anything else water does to the sim (M57). Fire spreading, destructible scatter. Volumetric clouds. Footprints.

## Pitfalls

- Sway moves vertices, not collision. Trunks must not sway where a player can see the gap to the collision cylinder: weight 0 below 3 m.
- `MultiMesh` instances have no per-instance uniforms without custom data: the phase comes from world position in the shader.
- Water on a round realm follows the sphere: the water surface is a shell at `radius + water_level`, not a plane.
- Every effect here is tempting to overdo. The art direction is muted: when in doubt, less.
