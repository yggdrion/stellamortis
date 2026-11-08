# Stellamortis: proof of concept plan

Source of truth for scope, design, architecture and milestones. Decisions from the brainstorm on 2026-11-09.

## 1. Pitch

Third-person coop action game in space, Valheim-like with aiming, combat feel closer to Elden Ring: dodge roll with i-frames, shield block and parry, lock-on. Fights happen across gravity zones on a planet surface and a small asteroid. The PoC is one arena: kill 3 mobs, a boss spawns, kill the boss.

## 2. Scope

In:

- Movement: walk, sprint, jump, dodge roll, stamina.
- Gravity zones: normal, low-g and high-g zones on flat ground, plus one small asteroid you can walk all the way around (spherical gravity).
- Melee: light combo, heavy attack. Shield: block and parry.
- Ranged: charged plasma bolt with travel time that falls with the local gravity.
- Lock-on (toggle key).
- 3 mobs with telegraphed attacks, then a boss with phases.
- Death, respawn, encounter reset on wipe.
- Up to 10 players. Solo, host-by-code (lobby) and dedicated all run the same server.

Out (for the PoC): inventory, loot, crafting, persistence, procedural world, building, telemetry, public dedicated hosting.

## 3. Tech

| Area | Choice |
|---|---|
| Engine | Godot 4.7, latest 4.7.x patch (jotra pins 4.7.2), pinned with a checksum like jotra (`tools/install.py`), Forward+ renderer, Jolt physics |
| Language | GDScript, statically typed everywhere (typed arrays and dictionaries) for speed and checks, lint with gdtoolkit |
| Tests | gdUnit4 (game), `bun test` (lobby) |
| Lobby | TypeScript on Bun, copied from jotra `lobby/` (own protocol number, own deployment later) |
| NAT traversal | WebRTC (`webrtc_native` GDExtension) + coturn, as in jotra |
| Dedicated | headless Linux export in Docker, run locally |
| Art | CC0 rigged and animated packs (Quaternius, KayKit), sources and licenses in `docs/RESOURCES.md` |

### 3.1 Rendering and performance

Rule: use the newest Godot 4.7 features where they improve looks or speed, and check each choice against the 4.7 docs and migration guide before using it.

Rendering (client):

- Forward+ on Vulkan (Linux) and Direct3D 12 (Windows default since 4.6).
- HDR output (new in 4.7) as a setting, on where the display supports it; AgX tonemapping; glow blended before tonemapping (4.6).
- Lighting: one directional sun with tuned shadow cascades; LightmapGI baked for the static arena with SSAO and SSIL on top; SDFGI only in the Ultra preset. `AreaLight3D` (new in 4.7) for panel and window lights on structures.
- Atmosphere: volumetric fog per planet zone, sky shader with stars and the planet in view; SSR (rewritten in 4.6, half resolution mode) for wet and metal surfaces.
- Effects: `GPUParticles3D` with collision for bolts, hits and dust; decals for impacts; compositor effects for screen-space distortion of the boss gravity well; stencil buffer for the lock-on target outline and players seen through walls.
- Anti-aliasing and scaling: TAA or SMAA, FSR 2 upscaling in lower presets.
- No hitches: ubershaders and pipeline precompilation are on, and the shader baker bakes shaders into the export.
- Scene cost: occlusion culling, automatic mesh LOD, visibility ranges for distant props, `MultiMeshInstance3D` for rocks and debris.
- Animation: `AnimationTree` with blend spaces, foot IK (the 4.6 IK modifiers) so feet sit on slopes and on the asteroid. Animations are visual only: no root motion, movement comes from the sim.
- Graphics presets Low, Medium, High, Ultra, plus resolution scale and the HDR toggle.

Server and network:

- The server runs `--headless` (dummy renderer), Jolt physics, fixed 30 Hz tick.
- Snapshots and inputs are packed `PackedByteArray`s (quantized positions and angles), not dictionaries over RPC.
- Track frame time and server tick time in the F3 overlay from M0, so performance regressions show up early.

## 4. Architecture

### 4.1 Always a server

One executable, three ways to run the server:

```
SOLO        client ──spawns──> headless server (--mode=solo, localhost ENet, 1 player)
HOST        client ──spawns──> headless server (--mode=host) ──registers room──> lobby ──code──> friends join via WebRTC
DEDICATED   docker: headless server (--mode=dedicated, ENet on a public UDP port)
```

The client never runs gameplay rules itself; solo is a server with one player. There is one codebase for solo and multiplayer. The pattern is jotra's (`GameServer`, `--owner`, `--room-file`, server process opens the lobby room).

A `Transport` creates the `MultiplayerPeer` (ENet or WebRTC). Gameplay code sees only peers, RPCs and the protocol.

### 4.2 Sim and view

- `sim/` holds the rules: player movement, gravity sampling, combat, enemy AI, encounter. It runs on the server and, for the local player's movement only, on the client for prediction. No rendering, no input reading.
- `client/` holds views, input, camera, HUD, animation. Views follow sim state; they never decide outcomes.

### 4.3 Networking

- Server tick 30 Hz. Clients send input (move vector in camera frame, look direction, buttons, tick number) every tick.
- Own player: predicted with the same `sim/` movement code, reconciled against the server state (replay unacked inputs).
- The server runs every input it received each tick (up to 8), never extrapolates a missing one, so the client's prediction replays exactly what the server ran. A player whose inputs are late stands still on the server until they arrive. Fine for coop; a speed-hack check can come later.
- Physics interpolation (project setting) smooths the predicted player between 30 Hz ticks; remote players are interpolated in code.
- Other players and enemies: interpolated from snapshots about 100 ms behind.
- Snapshots at 30 Hz: position, up vector, facing, velocity, action state + its start tick, health, stamina. 10 players in one arena need no interest management.
- Hits:
  - Player melee: the client reports what its swing hit; the server checks reach, arc, timing and stamina with slack (jotra pattern).
  - Player projectiles: simulated on the server; the client draws its own bolt at once and snaps to the server one.
  - Enemy attacks: resolved on the server. I-frames, block and parry are checked there against the action state the server has for that player.
- Game protocol version is separate from the lobby protocol.

### 4.4 Gravity

- Zones are data nodes (`GravityZone`: shape, mode `DIRECTIONAL` or `POINT`, direction or center, strength, priority). `Gravity.sample(pos)` returns the gravity vector at a point; the highest priority zone containing the point wins, the world default is -Y at 9.8 m/s².
- One deterministic function is used by players, enemies and projectiles, on server and client, so predicted arcs and movement match. Godot's physics gravity (`Area3D` overrides) is not used for gameplay.
- Bodies: `CharacterBody3D` with `up_direction = -gravity.normalized()`. The up vector turns toward the new one over about 0.25 s when crossing zones, so the camera does not snap. Movement is computed in the body's local frame (tangent plane).
- Camera: orbit and pitch are relative to the player's up vector, so walking around the asteroid keeps the horizon steady.
- PoC layout: main ground (normal), one low-g zone (about 3 m/s², long jumps), one high-g zone (about 20 m/s², slow, short jumps, heavier bolt drop), one asteroid of about 25 m radius with point gravity, reachable by a low-g jump pad.

### 4.5 Combat

All numbers live in data resources (`game/data/*.tres`), not in code.

- Stamina: sprint, roll, heavy attacks, blocking hits and charged shots spend it; regenerates after a short delay.
- Dodge roll: about 0.6 s, i-frames about 0.1–0.4 s, direction from input (or away from the lock-on target), costs stamina.
- Melee: light combo of 2–3 swings, heavy attack with windup. Attacks commit: no turning after the windup.
- Shield: hold to block (cuts damage, stamina per hit, breaks at zero stamina). Pressing block within the parry window (about 0.2 s) before a hit lands parries: the attacker is staggered and takes bonus damage from the next hit.
- Ranged: hold right mouse for over-the-shoulder aim with crosshair; hold fire to charge (faster bolt, more damage, more stamina). The bolt falls with `Gravity.sample` along its path.
- Lock-on: toggle key picks the enemy nearest to screen center within range; camera keeps it framed, movement strafes around it, rolls go relative to it. Switch target with the mouse or scroll.
- Enemy actions are state machines: idle, chase, windup (telegraphed by animation, a sound and a glow), attack, recover, stagger.

### 4.6 Encounter

- 3 mobs in the arena (2 melee, 1 ranged). When all are dead, the boss spawns.
- Boss "Warden": a melee sweep (roll through it), a ground slam with an area (roll out of it), a bolt volley (block or strafe). Below 50% health, phase 2: faster, plus a gravity well that pulls players toward it, built on the same `GravityZone` system.
- Boss health scales with player count.
- A dead player respawns at the start after a few seconds. If everyone is dead, the encounter resets.

## 5. Repository layout

```
game/        Godot project
  sim/       rules (movement, gravity, combat, enemies, encounter)
  client/    views, input, camera, HUD, animation
  net/       transport, lobby client, protocol, snapshots
  data/      .tres tuning, attacks, enemies
  tests/     gdUnit4
lobby/       Bun lobby/signaling server (copied from jotra), tests, Dockerfile
deploy/      docker-compose for dedicated server, lobby + coturn
tools/       install, run, test, export scripts (adapted from jotra)
docs/        PLAN.md, RESOURCES.md
```

## 6. Milestones

| # | Name | Done when | Status |
|---|---|---|---|
| M0 | Skeleton | Tooling copied from jotra (pinned Godot, gdUnit4, lint); client spawns a local server in solo; capsule player moves with prediction and reconciliation; third-person camera; a second client joins by IP; two clients see each other move smoothly at 100 ms simulated latency | Done (2026-11-09) |
| M1 | Gravity zones | `Gravity.sample` with zones; low-g and high-g zones; walk all the way around the asteroid with a steady camera; jump pad to the asteroid; tests for sampling and zone priority | Planned |
| M2 | Melee + defense | Stamina, roll with i-frames, light combo, heavy, block, parry; a training dummy that swings on a timer to test i-frames and parry; animated player model (CC0) | Planned |
| M3 | Ranged | Aim mode, crosshair, charged bolt simulated on the server and falling with local gravity; hits the dummy | Planned |
| M4 | Lock-on | Toggle, target switch, strafe and roll relative to target, works on the asteroid | Planned |
| M5 | Encounter | 3 mobs with telegraphed attacks, boss with phases and gravity well, death and respawn, wipe reset, HUD (health, stamina, boss bar) | Planned |
| M6 | Lobby | `lobby/` copied with its own protocol; host opens a room, friends join by code via WebRTC; local lobby + coturn compose | Planned |
| M7 | 10 players | Headless bots fill a game to 10; server holds 30 tps; bandwidth per peer measured | Planned |
| M8 | Lobby deploy | Own lobby + coturn deployed on its own subdomain (needs a go-ahead) | Planned |

## 7. Open questions

- Subdomain and host for the M8 lobby deployment.
- Exact CC0 packs (pick in M2 when the player model goes in).
