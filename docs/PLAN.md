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
| Engine | Godot 4.7, latest 4.7.x patch (4.7.2 now), pinned with a checksum (`tools/install.py`), Forward+ renderer, Jolt physics |
| Language | GDScript, statically typed everywhere (typed arrays and dictionaries) for speed and checks, lint with gdtoolkit |
| Tests | gdUnit4 (game), `bun test` (lobby) |
| Lobby | TypeScript on Bun, no runtime deps (`lobby/`), with coturn (`deploy/lobby/`), deployed on the gvm host |
| Netcode | [netfox](https://github.com/foxssake/netfox) (MIT), pinned to a main commit (`tools/install.py`): shared network tick, client-side prediction with server-side rollback, tick interpolation; later lag compensation for hits |
| NAT traversal | WebRTC (`webrtc_native` GDExtension) + coturn |
| Dedicated | headless Linux export in Docker, run locally |
| Art | CC0 rigged and animated packs (Quaternius, KayKit), sources and licenses in `docs/RESOURCES.md` |

### 3.1 Rendering and performance

Rule: use the newest Godot 4.7 features where they improve looks or speed, and check each choice against the 4.7 docs and migration guide before using it.

Rendering (client):

- Forward+ on Vulkan (Linux) and Direct3D 12 (Windows default since 4.6).
- AgX tonemapping; glow blended before tonemapping (4.6). HDR output (new in 4.7) is left out for now (2026-11-09).
- Lighting: one directional sun with tuned shadow cascades; LightmapGI baked for the static arena with SSAO and SSIL on top; SDFGI only in the Ultra preset. `AreaLight3D` (new in 4.7) for panel and window lights on structures.
- Atmosphere: volumetric fog per planet zone, sky shader with stars and the planet in view; SSR (rewritten in 4.6, half resolution mode) for wet and metal surfaces.
- Effects: `GPUParticles3D` with collision for bolts, hits and dust; decals for impacts; compositor effects for screen-space distortion of the boss gravity well; stencil buffer for the lock-on target outline and players seen through walls.
- Anti-aliasing and scaling: TAA or SMAA, FSR 2 upscaling in lower presets.
- No hitches: ubershaders and pipeline precompilation are on, and the shader baker bakes shaders into the export.
- Scene cost: occlusion culling, automatic mesh LOD, visibility ranges for distant props, `MultiMeshInstance3D` for rocks and debris.
- Animation: `AnimationTree` with blend spaces, foot IK (the 4.6 IK modifiers) so feet sit on slopes and on the asteroid. Animations are visual only: no root motion, movement comes from the sim.
- Graphics presets Low, Medium, High, Ultra (F4, saved in `user://settings.cfg`): Low and Medium render at 67%/80% and upscale with FSR 2, Low drops SSAO and the zone fog; High adds SSIL and SMAA; Ultra adds SDFGI, SSR and TAA. On a GTX 1050 Ti (vsync off): Low 146 fps (GPU 3.7 ms), Medium 132 (5.4), High 128 (5.6), Ultra 93 (10).

Server and network:

- The server runs `--headless` (dummy renderer), Jolt physics, fixed 30 Hz tick.
- Snapshots and inputs are packed `PackedByteArray`s (quantized positions and angles), not dictionaries over RPC.
- Track frame time and server tick time in the F3 overlay from M0, so performance regressions show up early.

## 4. Architecture

### 4.1 Always a server

One executable, three ways to run the server:

```
SOLO        client ──spawns──> headless server (--solo, localhost ENet, 1 player)
HOST        client ──spawns──> headless server (--solo --lobby=URL) ──opens room──> lobby ──code──> host and friends join via WebRTC
DEDICATED   headless server (--server --port=N, ENet on a public UDP port)
```

The client never runs gameplay rules itself; solo is a server with one player. There is one codebase for solo and multiplayer. `GameServer` makes the `MultiplayerPeer` (ENet, or WebRTC when it has a lobby URL), `GameClient` joins by address or by room code. Gameplay code sees only peers, RPCs and the protocol.

### 4.2 Sim and view

- `sim/` holds the rules: player movement, gravity sampling, combat, enemy AI, encounter. It runs on the server and, for the local player's movement only, on the client for prediction. No rendering, no input reading.
- `client/` holds views, input, camera, HUD, animation. Views follow sim state; they never decide outcomes.

### 4.3 Networking

netfox does the netcode (decided 2026-11-09, replacing M0's own prediction code):

- `NetworkTime` runs one network tick loop at 30 Hz on every peer, synced to the physics tick and to the server's clock. `NetworkEvents` starts it when the server opens or the client connects.
- Each player is a server-owned `SimPlayer` (state: transform, velocity, up, ref_forward, facing, grounded) with a player-owned `PlayerControls` child (input: move, yaw, buttons). A `RollbackSynchronizer` sends input to the server only (no broadcast) and state from the server, with diff states.
- Server: when late input arrives, it rolls back to that tick and resimulates. Owning client: predicts its own player from its input and resimulates from each server state. Other players are not simulated on clients; they show the server's state, smoothed by a `TickInterpolator`.
- Movement code runs in `_rollback_tick`, scaled by `NetworkTime.physics_factor` around `move_and_slide`. Godot's own physics interpolation is off, `TickInterpolator` does that job.
- Players are spawned by the server through a `MultiplayerSpawner` once the client's clock is synced (`NetworkTime.is_client_synced`), so late joiners get everyone.
- Our own RPCs (`Net`): hello with protocol version and name, reject, ping, server stats, the room code.
- Hits (later milestones): player melee and projectiles go through netfox rollback and lag compensation, enemy attacks are resolved on the server, so i-frames, block and parry are checked there against the player's rolled back state. Details are worked out in M2/M3.
- Testing latency: `tools/lag_proxy.py` delays every UDP packet (netfox's too), with optional jitter and loss.

### 4.7 Lobby and player host

Built in M6 (section number out of order so the earlier references stay valid):

- `lobby/`: TypeScript on Bun, no runtime deps, Docker container. WebSocket `/ws`, `/healthz`, Prometheus `/metrics` (`stellamortis_lobby_*`). Room codes of 8 letters without ambiguous ones; relays WebRTC offer, answer and ICE candidates verbatim and never sees gameplay. Mints time-limited coturn credentials (REST scheme, the shared secret stays on the server host). Rooms stay open while the game server runs (it pings every 20 s, the lobby drops a room after 60 s without one), so friends can join any time; up to 10 guests waiting per room, 5 join attempts per 10 s per socket. Star topology: each guest connects only to the server (WebRTC peer 1), the server makes one offer per guest. Lobby protocol 1 (`PROTOCOL` in `lobby/src/server.ts`, `LobbyClient.PROTOCOL`), apart from `Net.PROTOCOL_VERSION`, so game-only changes need no lobby redeploy. Logs one JSON line per room event, never signal data, credentials or addresses.
- coturn as STUN plus TURN relay fallback (`deploy/lobby/turnserver.conf`, 3478, relay ports 49160–49259, `total-quota` 100, no relaying into private networks).
- Game: `net/lobby_client.gd` for both sides, with a join trace in `user://logs/join-<role>.log` (`net/join_log.gd`) and readable failure reasons per stage (lobby, signaling, ICE). `--server --lobby=URL [--room-file=PATH]` opens a room on a `WebRTCMultiplayerPeer` server and writes the code to the file; if the lobby is lost later it opens a new room after 10 s (players already in stay). `--host` spawns that server as `--solo` (it exits when the last player leaves, or after 60 s without anyone), waits for the code and joins it by code like any friend: one peer type per `MultiplayerAPI`, so in player host everyone uses WebRTC. `--join=CODE` joins a room, `--lobby=URL` picks the lobby (default `wss://lobby.r4b2.de/ws`). The server sends the code to every player (`Net.room`); the HUD shows it top right and F2 copies it. F3 shows the ICE candidate types the server offered and whether TURN was used (inferred: Godot exposes no WebRTC stats).
- Checks: `bun test` (lobby), and the network test's WebRTC run: a local lobby, a `--host` bot and a bot joining by code, plus a join with a wrong code that must fail with the lobby's reason. `--relay-only` (debug) makes a client send and accept only relay candidates; with `deploy/lobby/docker-compose.local.yml` (lobby on 8080, coturn on 127.0.0.1) a friend joined through TURN only (2026-11-09).

### 4.4 Gravity

- Zones are data (`GravityZone`: box or sphere, mode `DIRECTIONAL` or `POINT`, direction or center, strength, priority), listed in `Layout`. `Gravity.sample(pos)` returns the gravity vector at a point; the highest priority zone containing the point wins, the world default is -Y at 9.8 m/s².
- One deterministic function is used by players, enemies and projectiles, on server and client, so predicted arcs and movement match. Godot's physics gravity (`Area3D` overrides) is not used for gameplay.
- Bodies: `CharacterBody3D` with `up_direction = -gravity.normalized()`. The up vector turns toward the new one over about 0.25 s when crossing zones, so the camera does not snap. Movement is computed in the body's local frame (tangent plane).
- Camera: orbit and pitch are relative to the player's up vector, so walking around the asteroid keeps the horizon steady.
- PoC layout (`sim/layout.gd`): main ground (normal); low-g zone east of the spawn (3 m/s², 30×18×40 m); high-g zone west (22 m/s²); an asteroid of 18 m radius floating above the low-g zone (center 50 m up, point gravity 7 m/s² out to 34 m from its center, overlapping the top of the low-g zone).
- Jump pads: standing on one and jumping launches along the player's up at the pad's speed (12 m/s on the ground under the asteroid, 17 m/s on the asteroid's bottom pole back down). Jump, not touch, so landing on a pad never relaunches.
- Turning the up vector uses axis-angle, because slerp is undefined between opposite directions (leaving the asteroid's underside flips up by 180°).
- Look: zones are tinted `FogVolume`s with rising (low-g) or falling (high-g) GPU particles and a glowing border; space sky shader (`shaders/space_sky.gdshader`) with stars, nebula and a gas giant.

### 4.5 Combat

All numbers live in data resources (`game/data/*.tres`), not in code.

- Stamina: sprint, roll, heavy attacks, blocking hits and charged shots spend it; regenerates after a short delay.
- Dodge roll: about 0.6 s, i-frames about 0.1–0.4 s, direction from input (or away from the lock-on target), costs stamina.
- Melee: light combo of 2–3 swings, heavy attack with windup. Attacks commit: no turning after the windup.
- Shield: hold to block (cuts damage, stamina per hit, breaks at zero stamina). Pressing block within the parry window (about 0.2 s) before a hit lands parries: the attacker is staggered and takes bonus damage from the next hit.
- Ranged: hold right mouse for over-the-shoulder aim with crosshair; hold fire to charge (faster bolt, more damage, more stamina). The bolt falls with `Gravity.sample` along its path.
- Built in M3: weapons switch with 1, 2 or the wheel (sword and shield, or crossbow), only while not acting. Crossbow: RMB aims (camera moves in over the shoulder, FOV 55, walk 3 m/s), holding LMB draws for up to 0.9 s, releasing shoots. Charge scales speed 22–55 m/s, damage 10–38 and stamina 6–18. Bolts aim at what the crosshair is on (`Combat.aim_target`: the aiming camera's ray, shared geometry with `CameraRig`), live up to 3 s, fall with `Gravity.sample` each tick and end on the first enemy (capsule test) or wall (ray on the world layer). Each player has 4 bolt slots in its rolled back state (packed arrays), so bolts are predicted and rolled back with their shooter without spawning nodes in rollback; views draw remote bolts from that state and move them on between ticks. Enemies moved to their own collision layer so aim and bolt rays only see the world.
- Lock-on: toggle key picks the enemy nearest to screen center within range; camera keeps it framed, movement strafes around it, rolls go relative to it. Switch target with the mouse or scroll.
- Built in M4 (numbers in `data/tuning.tres`): MMB or Tab toggles, picking the enemy closest to the camera's center within 45° and 22 m and in sight; the lock drops beyond 30 m, when the target goes down or the player dies. A sideways mouse flick (120 px within 0.25 s) or the wheel switches to the next enemy that way. While locked, movement input is relative to the direction to the target (on any up vector, so it works on the asteroid), walking strafes facing the target, sprinting runs free, a roll without input backs away, attacks face the target and crossbow bolts fly at its center. The target is `SimPlayer.target` (an `Enemy.index`) in the rolled back state, toggled and switched by `LOCK`/`SWITCH_LEFT`/`SWITCH_RIGHT` input bits (one-tick pulses for switches), picked by `LockOn` in the player's tick. The camera turns itself toward the target, looking 15° below it so the target sits above the player's head; the target gets a stencil outline (Godot 4.5+ `stencil_mode` on the model's overlay material) and a dot that shows through walls.
- Enemy actions are state machines: idle, chase, windup (telegraphed by animation, a sound and a glow), attack, recover, stagger.
- Built in M2 (numbers in `data/tuning.tres` and `data/attacks/*.tres`): stamina 100, regen 35/s after 0.8 s; light combo of 3 (18/20/28 damage, 12/12/16 stamina), heavy 50 (28 stamina, 0.6 s windup); roll 0.6 s with i-frames 0.06–0.4 s (20 stamina); block stops 80% and costs 1 stamina per point blocked, guard breaks at 0; parry window 0.2 s after block press, staggers 1.5 s, ripostes deal 2.5×; unguarded hits stun 0.35 s and give 0.45 s of invulnerability (no double hits); 3 s death, then respawn at the spawn ring. Presses are buffered 0.3 s; rolls and the next combo swing can cancel an attack's recovery; attacking or rolling drops the block.
- Controls: LMB light, Q heavy (MMB moved to lock-on in M4), RMB block (and parry), Ctrl or C roll (mouse button 4 too). When M3 adds the bow, RMB aims with the bow out: weapons switch like in Valheim.
- Netcode for hits: enemy swings are checked in the defending player's own `_rollback_tick` against its state that tick (roll, block, parry), so a late dodge input that the server resimulates still counts. Player hits and parries change the enemy and call `NetworkRollback.mutate(enemy)`. Enemies use `RollbackSynchronizer` with prediction, so clients simulate them between server states. Views pose models from the state (action and ticks since it started), never from their own animation clock.

### 4.6 Encounter

- 3 mobs in the arena (2 melee, 1 ranged). When all are dead, the boss spawns.
- Boss "Warden": a melee sweep (roll through it), a ground slam with an area (roll out of it), a bolt volley (block or strafe). Below 50% health, phase 2: faster, plus a gravity well that pulls players toward it, built on the same `GravityZone` system.
- Boss health scales with player count.
- A dead player respawns at the start after a few seconds. If everyone is dead, the encounter resets.
- Built in M5 (`sim/encounter.gd`, `sim/mob.gd`, `sim/warden.gd`, numbers in `data/attacks/mob_*.tres` and `warden_*.tres` and the scripts' constants): every enemy exists on every peer from the start (netfox finds nodes by path), so nothing is spawned during rollback; the encounter only changes their state. Enemy indices: dummies 0–1, mobs 2–4, Warden 5.
  - Arena: south of the spawn, in front of the long wall. Two melee skeletons (minions with axes, 90 health, 18 damage chop with 0.8 s windup) at (±6, 0, 24), a ranged one (rogue with a crossbow, 70 health, 14 damage bolts every 1.6 s, keeps 7–13 m away) at (0, 0, 33). Mobs notice players within 16 m, chase them within a 24 m leash around their post, walk back when the player leaves it and stay down when killed.
  - Warden: rises (3 s, unhittable) where the ranged mob stood when the third mob falls, 900 health plus 50% per extra player present at that moment. Moves: sweep (30 damage, 220°, 4.2 m, parryable), slam (40 damage, a 3.2 m circle 2.2 m in front of it, not parryable: roll out), volley (5 bolts in a 50° fan, 16 damage each, blockable). Below half health, phase 2: windups at 70%, faster steps, and every 4th move a gravity well (14 m, 5 s) that drags players toward it (`Gravity.pull`, a `GravityZone` sphere read apart from `Gravity.sample`, so it doesn't turn the player's up vector or bend bolts; `well_drag` 0.4 s of its 11 m/s² becomes drift, so walking out is slow and sprints or rolls escape). The HUD shows its bar; telegraphs are the same orange glow and ground area as the dummies'.
  - Enemy bolts: fixed slots in the enemy's rolled back state (like the players'), aimed up to make up for gravity, ended by walls in the enemy's tick and by players in their own tick (`SimPlayer._catch_bolts`: rolls pass through, blocks reduce, no parry).
  - Phases (`Encounter.Phase`): MOBS, BOSS, CLEARED; 20 s after the Warden falls everything resets. A wipe (every player dead at once, at least 4 s after the last reset) resets to the mobs. The encounter node is rolled back with prediction like the enemies.
  - Debug: `--encounter=boss` starts a server (or solo) with the mobs dead.

## 5. Repository layout

```
game/        Godot project
  sim/       rules (movement, gravity, combat, enemies, encounter)
  client/    views, input, camera, HUD, animation
  net/       transport, lobby client, protocol, snapshots
  data/      .tres tuning, attacks, enemies
  tests/     gdUnit4
lobby/       Bun lobby/signaling server, tests, Dockerfile
deploy/      docker-compose for dedicated server, lobby + coturn
tools/       install, run, test, export scripts
docs/        PLAN.md, RESOURCES.md
```

## 6. Milestones

| # | Name | Done when | Status |
|---|---|---|---|
| M0 | Skeleton | Tooling (pinned Godot, gdUnit4, lint); client spawns a local server in solo; capsule player moves with prediction and reconciliation (netfox since 2026-11-09); third-person camera; a second client joins by IP; two clients see each other move smoothly at 100 ms simulated latency | Done (2026-11-09), v0.1.x |
| M1 | Gravity zones | `Gravity.sample` with zones; low-g and high-g zones; walk all the way around the asteroid with a steady camera; jump pad to the asteroid; tests for sampling and zone priority | Done (2026-11-09), v0.2.0 |
| M2 | Melee + defense | Stamina, roll with i-frames, light combo, heavy, block, parry; a training dummy that swings on a timer to test i-frames and parry; animated player model (CC0); graphics presets | Done (2026-11-09), v0.3.0 |
| M3 | Ranged | Aim mode, crosshair, charged bolt simulated on the server and falling with local gravity; hits the dummy; weapon switching | Done (2026-11-09), v0.4.0 |
| M4 | Lock-on | Toggle, target switch, strafe and roll relative to target, works on the asteroid | Done (2026-11-09), v0.5.0 |
| M5 | Encounter | 3 mobs with telegraphed attacks, boss with phases and gravity well, death and respawn, wipe reset, HUD (health, stamina, boss bar) | Done (2026-11-09), v0.6.0 |
| M6 | Lobby | `lobby/` (Bun, lobby protocol 1) and `deploy/lobby/` (lobby + coturn) in this repo; `net/lobby_client.gd` and the WebRTC transport; `--host` spawns the server with a lobby room, host and friends join by code via WebRTC (TURN relay when direct fails); `bun test` and a WebRTC run in `tools/check.py`; works against a local lobby + coturn compose | Done (2026-11-09), v0.7.0 |
| M7 | 10 players | Headless bots fill a game to 10; server holds 30 tps; bandwidth per peer measured; state packets fit netfox's 508 byte limit again (since M3's bolt slots a player's state snapshot is 520–590 bytes and netfox warns it may be dropped) | Planned |
| M8 | Lobby deploy | Run `deploy/lobby/` on the gvm host in place of the lobby + coturn stack there today: stop that stack, start ours on the same ports (3478, relay 49160-49259) and the Caddy route `lobby.r4b2.de` (gvm's Caddyfile: container alias `stellamortis-lobby` and comment), reuse or rotate `TURN_SECRET`; host and friends join by code from different networks, one through TURN. Touches the gvm host, so it needs a go-ahead before deploying | Planned |
| M9 | Frame pacing | Settings to turn vsync off and, as an alternative, cap the frame rate (`Engine.max_fps`, e.g. 60/120/144/unlimited), saved with the graphics preset; F3 shows the cap. Later, not relevant for the PoC | Later |
| M10 | Wooting analog | Analog movement from Wooting keyboards through the Wooting Analog SDK (GDExtension or a small native bridge): WASD depth becomes `PlayerControls.move` length, so walk speed follows key pressure; digital keys stay the fallback when no Wooting device or SDK is present. Later, not relevant for the PoC | Later |

## 7. Open questions

- M8: keep `lobby.r4b2.de` (default) or move to a stellamortis subdomain. Other services on the gvm host that are not ours are out of scope.
- Exact CC0 packs: answered in M2 (KayKit Adventurers and Skeletons, `docs/RESOURCES.md`).

## 8. Open items to clarify after the last milestone

Everything left open, deferred or decided on the way, collected so it can be gone through at the end. Add to it whenever a milestone leaves something open; strike items when they are settled.

Testing and verification:

- Nobody has play-tested M2 (melee, defense), M3 (crossbow), M4 (lock-on) or M5 (encounter) by hand yet; all of it is covered only by gdUnit4 tests, the headless network test and screenshots. Numbers (damage, windups, ranges, boss health, well strength) are first guesses.
- The gravity well's look (shell and motes) and the phase 2 Warden were never seen in a screenshot; only the mobs, the rising Warden and its volley were.
- Player host was only tried on one machine (direct, and forced through a local coturn with `--relay-only`); joining from another network through the public lobby and TURN is M8.
- The headless network test only has bots walking, fighting the dummies and toggling lock-on; nothing in it fights the encounter, so its netcode (mob chases, boss phases, enemy bolts against prediction) is untested under lag.

Network and performance:

- In player host the host's own server is a child process of the host's client: when the host quits, the game ends for everyone in the room. Host migration is out of scope; confirm that this is fine.

- netfox warns that state snapshots exceed its 508 byte packet limit (`Buffer of 520–590 bytes ... may be dropped`) since M3's player bolt slots; M5 adds enemy bolt slots (the Warden has 10). Planned for M7: shrink or split the state.
- Server tick loop with one local headless bot: about 5 ms at M4 and 7–9 ms at M5 (rollback resimulates walking enemies with `move_and_slide`; both processes on one machine). The 1.6 ms noted at M2 came from a smaller setup. Watch in M7 with 10 players.
- Snapshots as packed `PackedByteArray`s (§3.1) were replaced by netfox's own serialization; revisit only if bandwidth in M7 asks for it.

Design decisions to confirm:

- Hosting and joining by code need the command line (`--host`, `--join=CODE`); exported builds start solo. A small start menu (solo, host, join by code) would make player host usable from the release zips.

- MMB moved from heavy attack to lock-on in M4 (heavy is Q only). Lock-on also takes over mouse look: sideways flicks switch targets.
- The Warden's gravity well drags players (`Gravity.pull`) instead of being a real gravity zone in `Gravity.sample`: players don't tilt toward it and bolts don't bend around it. A real zone would make the arena briefly a tiny planet around the boss.
- Boss health scales with the players present when it rises; players joining later don't change it.
- The encounter loops: 20 s after the Warden falls it starts over. There is no end screen or score.
- A wipe resets the encounter at once (players still respawn after their 3 s).
- Enemies don't collide with each other (melee mobs can overlap) and walk only on their own up (mobs stay on the flat ground by their leash; none goes to the asteroid or the gravity zones).
- The debug overlay (F3) overlaps the encounter title at the top center.
- Fantasy KayKit characters stand in for space ones (no CC0 space pack found yet).

Planned in §3.1 and not built yet:

- LightmapGI for the static arena, `AreaLight3D` lights on structures, decals for impacts, collision on `GPUParticles3D`, `MultiMeshInstance3D` for rocks and debris, visibility ranges.
- The compositor screen-space distortion for the gravity well (it is a glowing shell with motes falling in for now).
- Stencil x-ray for players seen through walls (the stencil outline is used for the lock-on target).
- `AnimationTree` with blend spaces and foot IK; views use `AnimationPlayer` clips posed from the sim state.
- Sound: there is no audio at all (the plan mentions telegraph sounds).
- Shader baker for exports and a check that ubershaders avoid hitches in the release builds.

Later milestones not started: M7 10 players, M8 lobby deploy (needs a go-ahead, touches gvm), M9 frame pacing, M10 Wooting analog.
