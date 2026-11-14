# Stellamortis: proof of concept plan

Source of truth for scope, design, architecture and milestones. Decisions from the brainstorm on 2026-11-09.

## 1. Pitch

Third-person coop action game in space, Valheim-like with aiming, combat in Valheim's style: dodge roll with i-frames, shield block and parry, attacks toward the camera, no lock-on (removed in M10). Fights happen across gravity zones on a planet surface and a small asteroid. The PoC is a hub keep and one realm: kill 3 mobs, a boss rises, kill the boss, take the portal home.

After the PoC (decided 2026-11-14, §4.8, M19 onward): a saved survival world. Round realms large enough to feel like land, one biome, gravity and boss each, reached through rune gates from the keep; camps of the dead to clear, loot, gear with real gear slots, levels and perk trees, gathering, crafting and base building.

## 2. Scope

The PoC list below is built. From M19 on the scope is §4.8 and the milestone briefs in `docs/milestones/`: inventory, loot, crafting, persistence, a generated world and building move in; telemetry and public dedicated hosting stay out.

In:

- Movement: walk, sprint, jump, dodge roll, stamina.
- Gravity zones: normal, low-g and high-g zones on flat ground, plus one small asteroid you can walk all the way around (spherical gravity).
- Melee: light combo, heavy attack. Shield: block and parry.
- Ranged: charged plasma bolt with travel time that falls with the local gravity.
- Lock-on (toggle key).
- 3 mobs with telegraphed attacks, then a boss with phases.
- Death, respawn, encounter reset on wipe.
- Up to 6 players (10 planned; netfox's server rollback holds 6, §8). Solo, host-by-code (lobby) and dedicated all run the same server.

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
| Art | Dark grounded medieval fantasy (§3.2): CC0 Quaternius models and animations, CC0 ambientCG materials, the Cinzel and Alegreya fonts (OFL); sources and licenses in `docs/RESOURCES.md` |

### 3.1 Rendering and performance

Rule: use the newest Godot 4.7 features where they improve looks or speed, and check each choice against the 4.7 docs and migration guide before using it.

Rendering (client):

- Forward+ on Vulkan (Linux) and Direct3D 12 (Windows default since 4.6).
- AgX tonemapping; glow blended before tonemapping (4.6). HDR output (new in 4.7) is left out for now (2026-11-09).
- Lighting: one directional sun with tuned shadow cascades; LightmapGI baked for the static arena with SSAO and SSIL on top; SDFGI only in the Ultra preset. `AreaLight3D` (new in 4.7) for panel and window lights on structures.
- Atmosphere: volumetric fog per planet zone, sky shader with stars and the planet in view; SSR (rewritten in 4.6, half resolution mode) for wet and metal surfaces.
- Effects: `GPUParticles3D` with collision for bolts, hits and dust; decals for impacts; compositor effects for screen-space distortion of the boss gravity well; stencil buffer for players seen through walls.
- Anti-aliasing and scaling: TAA or SMAA, FSR 2 upscaling in lower presets.
- No hitches: ubershaders and pipeline precompilation are on, and the shader baker bakes shaders into the export.
- Scene cost: occlusion culling, automatic mesh LOD, visibility ranges for distant props, `MultiMeshInstance3D` for rocks and debris.
- Animation: `AnimationTree` with blend spaces, foot IK (the 4.6 IK modifiers) so feet sit on slopes and on the asteroid. Animations are visual only: no root motion, movement comes from the sim.
- Graphics presets Low, Medium, High, Ultra (F4, saved in `user://settings.cfg`): Low and Medium render at 67%/80% and upscale with FSR 2, Low drops SSAO and the zone fog; High adds SSIL and SMAA; Ultra adds SDFGI, SSR and TAA. On a GTX 1050 Ti (vsync off): Low 146 fps (GPU 3.7 ms), Medium 132 (5.4), High 128 (5.6), Ultra 93 (10).

Server and network:

- The server runs `--headless` (dummy renderer), Jolt physics, fixed 30 Hz tick.
- Snapshots and inputs are packed `PackedByteArray`s (quantized positions and angles), not dictionaries over RPC.
- Track frame time and server tick time in the F3 overlay from M0, so performance regressions show up early.

### 3.2 Art direction

Dark, grounded medieval fantasy (M12, chosen 2026-11-09, replacing M9's sci-fi, which replaced the cute KayKit fantasy): worn steel, stone, torches, the dead; muted colors, adult proportions, not cute. Space stays as travel: each planet is a place (a hub keep, the Barrows), reached through portals. Color is reserved for meaning: enemy embers and telegraph orange, the gate portals' blue, the victory portal's gold, the gravity zones' blue and red.

- Players: rangers from Quaternius' Modular Character Outfits (Fantasy, the free set: Ranger and Peasant), with heads, hair and brows from the Universal Base Characters (the full body cut to head and neck at runtime, `CharacterModel.wear_head`). Male (bearded) or female (second color set) and dark or light skin by peer id (`Gear.ranger`). Steel sword and crossbow built in code, the Fantasy Props MegaKit's round wooden shield. The outfits ship without clips; they are imported with a humanoid `BoneMap` (`assets/quaternius/outfits/outfit_bone_map.tres`) and `CharacterModel` gives them every UAL1 and UAL2 clip, like it copies UAL2's onto UAL1.
- Training squires: peasants with short or parted hair (`Gear.squire`).
- The dead: peasants in the dark color set, tinted grey-green, with long or bound hair, ember eyes and rusted swords (male) or crossbows (female); zombie clips for the swordsmen (`Gear.dead`). The Warden: the UAL1 mannequin at twice the size in black iron with a bascinet, a greatsword and ember eyes (the paid outfit sets have the plate knight that would suit it).
- Planets: the realm (the Barrows) on ambientCG dark grass, broken brick blocks and a barrow wall in the Medieval Village MegaKit's uneven brick, rock grave slabs, torches, the asteroid. The hub keep: a cobbled yard (ambientCG paving) inside brick walls with corner towers (MegaKit roofs), a hall with lit windows (Godot 4.7 `AreaLight3D`), torches, banners, vines, a training corner and a smithy (MegaKit props). Surfaces are tiling materials mapped world triplanar (`Arena._surface`).
- Light: a cold moon, warm flickering torches, a night sky with stars and a banded moon-planet, fog, a muted grade.
- HUD and menus: Cinzel capitals for titles, buttons and the HUD, Alegreya for running text, parchment on near black, old-blood bars (`client/menus.gd` holds the theme).
- The gameplay names in code (`Weapon.CROSSBOW`, bolts, mobs, `Warden`) stay.

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
- Built in M7: every synced property has a netfox schema serializer (`net/wire.gd`: 32 bit floats and vectors, small ints, varuint tick counters, our own serializers for packed arrays), so no value falls back to netfox's Variant encoding; besides transform and velocity, the rolled back fields travel packed in groups (`SimPlayer.net_motion`, `net_combat`, `net_bolts`; `Enemy.net_combat`, `net_bolts`: properties with a getter and setter around `Wire.pack`/`unpack`), because netfox's cost grows with the number of synced properties. `tests/wire_test.gd` checks every property has a serializer, values round-trip and a full state fits 508 bytes. Servers started with `STELLAMORTIS_SERVER_STATS=1` print one line per second: players, tps, tick loop avg and max, ticks resimulated per loop (netfox `NetworkPerformance`, debug builds), kB/s per player out and in (ENet host statistics), and the rollback loop split into restore, simulate, record and send (`net/rollback_profile.gd`). The F3 overlay shows the server's kB/s per player. `tools/run_load_test.py [--players=6] [--seconds=40] [--lag=MS]` runs a server and that many bots and reports it all; `--bench=N` times N simulated players and the enemies without the network. Up to 6 players (`GameServer.MAX_PLAYERS`).

### 4.7 Lobby and player host

Built in M6 (section number out of order so the earlier references stay valid):

- `lobby/`: TypeScript on Bun, no runtime deps, Docker container. WebSocket `/ws`, `/healthz`, Prometheus `/metrics` (`stellamortis_lobby_*`). Room codes of 8 letters without ambiguous ones; relays WebRTC offer, answer and ICE candidates verbatim and never sees gameplay. Mints time-limited coturn credentials (REST scheme, the shared secret stays on the server host). Rooms stay open while the game server runs (it pings every 20 s, the lobby drops a room after 60 s without one), so friends can join any time; up to 10 guests waiting per room, 5 join attempts per 10 s per socket. Star topology: each guest connects only to the server (WebRTC peer 1), the server makes one offer per guest. Lobby protocol 1 (`PROTOCOL` in `lobby/src/server.ts`, `LobbyClient.PROTOCOL`), apart from `Net.PROTOCOL_VERSION`, so game-only changes need no lobby redeploy. Logs one JSON line per room event, never signal data, credentials or addresses.
- coturn as STUN plus TURN relay fallback (`deploy/lobby/turnserver.conf`, 3478, relay ports 49160–49259, `total-quota` 100, no relaying into private networks), on the host network on gvm (behind Docker's NAT it refused relay to relay). ICE tries a direct connection, then hole punching through the addresses STUN reports, then the TURN relay; there is no UPnP.
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
- Dodge roll: about 0.6 s, i-frames about 0.1–0.4 s, direction from input (camera forward without input), costs stamina.
- Melee: light combo of 2–3 swings, heavy attack with windup. Attacks commit: no turning after the windup.
- Shield: hold to block (cuts damage, stamina per hit, breaks at zero stamina). Pressing block within the parry window (about 0.2 s) before a hit lands parries: the attacker is staggered and takes bonus damage from the next hit.
- Ranged: hold right mouse for over-the-shoulder aim with crosshair; hold fire to charge (faster bolt, more damage, more stamina). The bolt falls with `Gravity.sample` along its path.
- Built in M3: weapons switch with 1, 2 or the wheel (sword and shield, or crossbow), only while not acting. Crossbow: RMB aims (camera moves in over the shoulder, FOV 55, walk 3 m/s), holding LMB draws for up to 0.9 s, releasing shoots. Charge scales speed 22–55 m/s, damage 10–38 and stamina 6–18. Bolts aim at what the crosshair is on (`Combat.aim_target`: the aiming camera's ray, shared geometry with `CameraRig`), live up to 3 s, fall with `Gravity.sample` each tick and end on the first enemy (capsule test) or wall (ray on the world layer). Each player has 4 bolt slots in its rolled back state (packed arrays), so bolts are predicted and rolled back with their shooter without spawning nodes in rollback; views draw remote bolts from that state and move them on between ticks. Enemies moved to their own collision layer so aim and bolt rays only see the world.
- Built in M4, removed in M10 (Valheim style, decided 2026-11-09): MMB or Tab toggles, picking the enemy closest to the camera's center within 45° and 22 m and in sight; the lock drops beyond 30 m, when the target goes down or the player dies. A sideways mouse flick (120 px within 0.25 s) or the wheel switches to the next enemy that way. While locked, movement input is relative to the direction to the target (on any up vector, so it works on the asteroid), walking strafes facing the target, sprinting runs free, a roll without input backs away, attacks face the target and crossbow bolts fly at its center. The target is `SimPlayer.target` (an `Enemy.index`) in the rolled back state, toggled and switched by `LOCK`/`SWITCH_LEFT`/`SWITCH_RIGHT` input bits (one-tick pulses for switches), picked by `LockOn` in the player's tick. The camera turns itself toward the target, looking 15° below it so the target sits above the player's head; the target gets a stencil outline (Godot 4.5+ `stencil_mode` on the model's overlay material) and a dot that shows through walls.
- Built in M10: lock-on code, input bits, tuning, camera framing, outline and marker are gone (`Net.PROTOCOL_VERSION` 10). Attacks, blocks and aiming face the camera's yaw; a roll without input goes where the camera looks. The "teleport toward an enemy" came from the lock (attacks snapped to the target and lunged at it at up to 4 m/s); lunges are now 1.2/1.2/2.0 m/s (heavy 1.0), and `PlayerView` turns the model to the body's facing over a few frames (`TURN_FOLLOW`), so a facing snap at an attack or roll start no longer reads as a jump. Enemy ground telegraphs show a filled fan (alpha 0.2 to 0.6 over the windup) and a bright edge band (0.75 to 1.0) from the first windup tick. The HUD pops the own player's damage next to the health bar (blocked: smaller, grey); death reads "YOU DIED"; the F3 overlay starts below the encounter title.
- Built in M11: `main.gd` shows `MainMenu` unless a flag starts a game (`connect`, `join`, `host`, `bot`, `solo`, `screenshot`, `spawn`, `encounter`, `look`; the last four still mean solo). Leaving a game (pause menu, server gone, lobby failure) frees the `GameClient`, stops `NetworkTime`, resets the peer, kills the spawned server and shows the menu again with the reason; bots still quit. A friend whose server goes away reads "The host left" (`GameClient.hosting` tells the host apart). `Settings` (`client/settings.gd`) keeps name, mouse sensitivity (a multiplier on `Controls.MOUSE_SENSITIVITY`) and fullscreen in `user://settings.cfg` next to the graphics preset; `SettingsPanel` is shared by both menus; `GameClient._exit_tree` drops its lambdas from the persistent `Net` and `MultiplayerAPI` signals so a second game starts clean.
- Built in M12: hub and realm share one world (`Layout.HUB` floats 600 m from the realm, 400 m up), so the netcode loads nothing; clients draw only the planet the own player is on (`Arena.show_planet`, `Arena.shows` for views). Portals (`sim/portal.gd`, `Layout.portals()`) move a player inside the rolled back tick (`SimPlayer._use_portal`, `respawns` counts the jump so views snap): the keep's gate to the Barrows, a home portal beside the realm's arrival, and the victory portal where the Warden fell, open while `Encounter.won()`. Players spawn and respawn at the keep (`Layout.spawn_point`), facing south. The encounter has no restart timer any more: it resets when the realm empties (`Encounter.occupied`, rolled back), which covers going home and a wipe (everyone respawns at the keep). The training dummies moved into the keep's yard. `Net.PROTOCOL_VERSION` 11.
- Built in M13: `client/presence.gd` (`Presence`, made by `main.gd` for players only, not bots, servers or screenshots) looks at the game every 2 s and sends changes: details "In the menu", "Solo", "Hosting" or "In a party" (`GameClient.mode`), state "In the keep", "In the Barrows", "Facing the Warden", "The Warden has fallen", the elapsed time since the game started, and in a party its size out of 6 under a random party id (never the room code). The large image is the art asset key `logo`. The IPC client is the vendored pure GDScript `addons/discord_rich_presence` (MIT): a named pipe on Windows, a unix socket bridged through `nc`, `ncat` or (our patch) `socat` on Linux and macOS; it retries every 20 s and does nothing without Discord or a bridge. The logo is `game/assets/logo/stellamortis.svg` (a downturned sword through a pale star over a crescent moon on an iron seal), exported as `stellamortis-1024.png`; it is also the game's icon (`config/icon`).
- Built in M14: `client/sounds.gd` (`Sounds`): named sounds with variants (`Sounds.library`), positional one-shots on the node they come from (`play`), 3D loops (`loop`: torches crackle, portals hum, the Warden's well rumbles), the planet's wind (`ambience`, on a 2D player in `GameClient`) and UI clicks and hovers (`ui`, on every `Menus.button`). Buses Effects, Ambience (60%) and UI under Master; Settings has a volume slider (`Settings.volume`). Views play sounds when the state they show changes: players swing when the blade passes the windup (heavy swoosh for Q), roll and raise the shield with cloth, draw and shoot the crossbow, switch weapons, die, take hits (wood on the shield, a thud unguarded), travel (portals and respawns), launch from pads and step on grass or stone; enemies growl through windups (deeper for the Warden), swoosh or spit embers on strikes, thud when hit (iron clang on the Warden), ring on a parry and fall; player bolts knock on what they hit. Kenney's CC0 Impact, RPG and Interface Sounds give footsteps, impacts, cloth, the draw and the UI; `tools/make_sounds.py` (standard library only, fixed seeds, output checked in) synthesizes swooshes, the twang, telegraphs, embers, the portal hum and travel shimmer, the well, the pad whoom, wind and torch fire. Headless processes play nothing.
- Enemy actions are state machines: idle, chase, windup (telegraphed by animation, a sound and a glow), attack, recover, stagger.
- Built in M2 (numbers in `data/tuning.tres` and `data/attacks/*.tres`): stamina 100, regen 35/s after 0.8 s; light combo of 3 (18/20/28 damage, 12/12/16 stamina), heavy 50 (28 stamina, 0.6 s windup); roll 0.6 s with i-frames 0.06–0.4 s (20 stamina); block stops 80% and costs 1 stamina per point blocked, guard breaks at 0; parry window 0.2 s after block press, staggers 1.5 s, ripostes deal 2.5×; unguarded hits stun 0.35 s and give 0.45 s of invulnerability (no double hits); 3 s death, then respawn at the spawn ring. Presses are buffered 0.3 s; rolls and the next combo swing can cancel an attack's recovery; attacking or rolling drops the block.
- Controls: LMB light, Q heavy (MMB was lock-on from M4 to M10, now unbound), RMB block (and parry), Ctrl or C roll (mouse button 4 too). When M3 adds the bow, RMB aims with the bow out: weapons switch like in Valheim.
- Netcode for hits: enemy swings are checked in the defending player's own `_rollback_tick` against its state that tick (roll, block, parry), so a late dodge input that the server resimulates still counts. Player hits and parries change the enemy and call `NetworkRollback.mutate(enemy)`. Enemies use `RollbackSynchronizer` with prediction, so clients simulate them between server states. Views pose models from the state (action and ticks since it started), never from their own animation clock.

### 4.6 Encounter

- 3 mobs in the arena (2 melee, 1 ranged). When all are dead, the boss spawns.
- Boss "Warden": a melee sweep (roll through it), a ground slam with an area (roll out of it), a bolt volley (block or strafe). Below 50% health, phase 2: faster, plus a gravity well that pulls players toward it, built on the same `GravityZone` system.
- Boss health scales with player count.
- A dead player respawns at the start after a few seconds. If everyone is dead, the encounter resets.
- Built in M5 (`sim/encounter.gd`, `sim/mob.gd`, `sim/warden.gd`, numbers in `data/attacks/mob_*.tres` and `warden_*.tres` and the scripts' constants): every enemy exists on every peer from the start (netfox finds nodes by path), so nothing is spawned during rollback; the encounter only changes their state. Enemy indices: dummies 0–1, mobs 2–4, Warden 5.
  - Arena: south of the spawn, in front of the long wall. Two melee mobs (QuadShell walkers since M9, 90 health, 18 damage chop with 0.8 s windup) at (±6, 0, 24), a ranged one (an EyeDrone since M9, 70 health, 14 damage bolts every 1.6 s, keeps 7–13 m away) at (0, 0, 33). Mobs notice players within 16 m, chase them within a 24 m leash around their post, walk back when the player leaves it and stay down when killed.
  - Warden: rises (3 s, unhittable) where the ranged mob stood when the third mob falls, 900 health plus 50% per extra player present at that moment. Moves: sweep (30 damage, 220°, 4.2 m, parryable), slam (40 damage, a 3.2 m circle 2.2 m in front of it, not parryable: roll out), volley (5 bolts in a 50° fan, 16 damage each, blockable). Below half health, phase 2: windups at 70%, faster steps, and every 4th move a gravity well (14 m, 5 s) that drags players toward it (`Gravity.pull`, a `GravityZone` sphere read apart from `Gravity.sample`, so it doesn't turn the player's up vector or bend bolts; `well_drag` 0.4 s of its 11 m/s² becomes drift, so walking out is slow and sprints or rolls escape). The HUD shows its bar; telegraphs are the same orange glow and ground area as the dummies'.
  - Enemy bolts: fixed slots in the enemy's rolled back state (like the players'), aimed up to make up for gravity, ended by walls in the enemy's tick and by players in their own tick (`SimPlayer._catch_bolts`: rolls pass through, blocks reduce, no parry).
  - Phases (`Encounter.Phase`): MOBS, BOSS, CLEARED; 20 s after the Warden falls everything resets. A wipe (every player dead at once, at least 4 s after the last reset) resets to the mobs. The encounter node is rolled back with prediction like the enemies.
  - Debug: `--encounter=boss` starts a server (or solo) with the mobs dead.

### 4.8 Survival world (M19 onward)

Decided with the user on 2026-11-14. Nothing here is built yet; the briefs in `docs/milestones/` split it into tasks.

What the game becomes:

- A persistent survival world in Valheim's spirit. Priority: explore and fight, then gather and craft, then base building.
- Several round realms, each one biome with its own gravity, enemies, resources and boss. A boss's death opens the keep's gate to the next realm. Realms must be big enough that walking never feels like running around a ball.
- Realms: the Barrowlands (normal gravity, start, the Warden), Myrkfen (low gravity, fog and black water, a drowned jotun), Jarnfell (high gravity, ash and old forges, a forge king), the Skyshards (a cluster of small floating rocks with launch stones between them).
- The theme stays §3.2: dark medieval, Viking, northern fantasy. No sci-fi words or looks: realms and rune gates, sky iron, draugr.
- Hits and loot must feel satisfying (M19, M23).
- A base becomes a homestead (added 2026-11-14, after base building): fields of crops cooked into meals that raise health and stamina for a while (M30), tamed livestock that breeds and gives wool, milk, eggs, hide and meat but never fights (M31), and stations that work unattended through fuel and queues, with water wheels and windmills driving mills, bellows and saws over wooden shafts (M32). No conveyors, pipes or electricity. Growth, breeding and processing count in saved world time (only while the server runs) and are computed on load, never ticked.
- Inventory with real gear slots apart from the bag, sorting and quick transfer (Valheim's inventory is the bad example).
- Progression: character levels with perk trees, plus gear and sets that grant perks. The level cap rises with each boss. A kill pays its full XP to every nearby player; dying drops the XP toward the next level into the grave, to be fetched back by a body run (lost on a second death).
- Characters (gear, inventory, level, perks) are saved on the player's machine and travel between worlds; the server trusts what the client sends (fine among friends). The world save lives with the server.
- Enemies stay rolled back. A fixed pool of 24 to 32 enemy slots is assigned to spawn points near players: small groups, no hordes.

Technical calls (Claude's, to be corrected by measurement and play-tests):

- Realm radius 1000 m (a lap is 6.3 km; the horizon sits about 60 m away at eye height, and hills and fog hide the curve). Radius is data per realm.
- Terrain is a cube-sphere cut into chunks. Height is a pure function of world seed and direction (seeded `FastNoiseLite`), quantized, so every peer builds the same collision. Collision chunks exist around every player and awake enemy on the server and around the own player on clients; clients draw near chunks in detail and a coarse far shell. A gate holds the traveller until the destination's chunks exist.
- Realms sit in the one world at offsets like `Layout.HUB`, all within 6 km of the origin (32 bit floats); clients draw the realm they are on.
- The server sends the world seed and name in the hello handshake, before the client builds `World`.
- Only combat is rolled back. World objects (resource nodes, drops, graves, built pieces) and inventories are server-authoritative: reliable RPC deltas plus a snapshot at join. Equipped item ids are the only item data in rolled back state. A player's `Stats` block (from perks, gear and sets) is computed on the server and sent to its owner; it is not rolled back.
- Enemy kinds are data (`EnemyDef`: health, speed, attacks, behavior, look), so any pool slot can be any kind.
- Saves are JSON, written to a temp file and renamed: `user://worlds/<name>.json` on the server, `user://characters/<name>.json` on the client.
- New enemies stay on the humanoid UAL rig first. Beasts and flyers need a CC0 model that fits the look; each realm milestone starts with that search and falls back to humanoids.

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

The overview: every milestone, what it is in one line, and its status. The details (tasks, files, done-when, pitfalls) are in the milestone's file in `docs/milestones/`; `docs/milestones/README.md` has the rules for working on one.

When a milestone's status changes, change it here and in the `Status:` line of its file. Status values: Done (date, release), In progress, Planned, Optional (only when the user asks).

| # | Name | What | Status | Details |
|---|---|---|---|---|
| M0 | Skeleton | Tooling, solo through a local server, netfox prediction, camera, join by IP | Done (2026-11-09), v0.1.x | [details](milestones/M0-skeleton.md) |
| M1 | Gravity zones | `Gravity.sample`, low and high gravity zones, the walkable asteroid, jump pads | Done (2026-11-09), v0.2.0 | [details](milestones/M1-gravity-zones.md) |
| M2 | Melee + defense | Stamina, roll, light combo, heavy, block, parry, training dummy, graphics presets | Done (2026-11-09), v0.3.0 | [details](milestones/M2-melee-defense.md) |
| M3 | Ranged | Aim mode, charged bolts that fall with local gravity, weapon switching | Done (2026-11-09), v0.4.0 | [details](milestones/M3-ranged.md) |
| M4 | Lock-on | Target lock and switching (removed again in M10) | Done (2026-11-09), v0.5.0 | [details](milestones/M4-lock-on.md) |
| M5 | Encounter | Three mobs, the Warden with phases and gravity well, death, wipe reset, HUD | Done (2026-11-09), v0.6.0 | [details](milestones/M5-encounter.md) |
| M6 | Lobby | Lobby server, WebRTC transport, host and join by room code | Done (2026-11-09), v0.7.0 | [details](milestones/M6-lobby.md) |
| M7 | 6 players | Load test with bots, wire schemas, 30 tps at 6 players | Done (2026-11-09), v0.8.0 | [details](milestones/M7-six-players.md) |
| M8 | Lobby deploy | Lobby and coturn on the gvm host behind `lobby.r4b2.de` | Done (2026-11-09) | [details](milestones/M8-lobby-deploy.md) |
| M9 | Dark sci-fi look | Grounded sci-fi look (replaced by M12) | Done (2026-11-09) | [details](milestones/M9-dark-sci-fi-look.md) |
| M10 | Combat like Valheim | Lock-on removed, attacks face the camera, clear telegraphs, damage numbers | Done (2026-11-09) | [details](milestones/M10-combat-like-valheim.md) |
| M11 | Main menu | Main menu, pause menu, settings, player name, "The host left" | Done (2026-11-09) | [details](milestones/M11-main-menu.md) |
| M12 | Medieval fantasy theme | Dark medieval look, hub keep and realm, portals, restyled HUD and menus | Done (2026-11-09) | [details](milestones/M12-medieval-fantasy.md) |
| M13 | Discord Rich Presence | Discord presence with mode, party size and logo | Done (2026-11-09) | [details](milestones/M13-discord-rich-presence.md) |
| M14 | Sound | CC0 and synthesized sounds, buses, volume setting | Done (2026-11-09) | [details](milestones/M14-sound.md) |
| M15 | Test round | Hand play-tests, network test under lag, screenshots, tuning | Done (2026-11-14), v0.16.0 | [details](milestones/M15-test-round.md) |
| M16 | Frame pacing | Settings for vsync and a frame rate cap, saved, shown in F3. Required; independent of M19 to M29. | In progress (built 2026-11-14, the user's check in F3 is open) | [details](milestones/M16-frame-pacing.md) |
| M17 | Wooting analog | Analog movement from Wooting keyboards. | Optional | [details](milestones/M17-wooting-analog.md) |
| M18 | Telemetry | Opt-in game telemetry through the lobby host. | Optional | [details](milestones/M18-telemetry.md) |
| M19 | Hit feel | Hitting and being hit read clearly and feel heavy: knockback and flinch, hit stop, camera shake, blood and sparks, enemies that fall and burn away. | In progress (built 2026-11-14, the user's play-test is open) | [details](milestones/M19-hit-feel.md) |
| M20 | Big round realm | A world has a seed. The Barrowlands is a generated realm of 1000 m radius with streamed terrain, reached by a keep gate; two peers stand on identical ground; it looks like northern moorland. | Planned | [details](milestones/M20-big-round-realm.md) |
| M21 | Enemy pool | Enemies walk the round realm; kinds are data; a pool of 24 rolled back slots serves seeded camps and roamers near players; the load test holds 29 tps with a full pool. | Planned | [details](milestones/M21-enemy-pool.md) |
| M22 | Barrowlands bestiary and boss | Draugr swordsman and archer, shield bearer, berserker, barrow elite; the Warden rises at a generated barrow and its death opens the next gate; the hand-built realm is removed. | Planned | [details](milestones/M22-barrowlands.md) |
| M23 | Inventory, loot and saves | Items, gear slots apart from the bag, a good inventory panel, loot that bursts out of enemies, chests, graves, world and character saves, a world list in the menu. | Planned | [details](milestones/M23-inventory-loot-saves.md) |
| M24 | Levels, perks and sets | XP and levels, three perk trees, set bonuses, one `Stats` block feeding the sim, level cap per boss. | Planned | [details](milestones/M24-levels-perks-sets.md) |
| M25 | Gather and craft | Trees, rock and ore as saved world objects, axe and pickaxe, recipes, smithy and workbench, the Barrowlands gear tier with two sets. | Planned | [details](milestones/M25-gather-craft.md) |
| M26 | Myrkfen | Second realm, low gravity: biome, three enemy kinds, resin and bog iron, tier 2, the drowned jotun. | Planned | [details](milestones/M26-myrkfen.md) |
| M27 | Jarnfell | Third realm, high gravity: brutes and swarms, ore and coal, tier 3, the forge king. | Planned | [details](milestones/M27-jarnfell.md) |
| M28 | Skyshards | Floating rocks with launch stones, sentries, sky iron, tier 4, a boss fought across rocks. | Planned | [details](milestones/M28-skyshards.md) |
| M29 | Base building | Place, snap and remove saved pieces and stations on any realm, within a piece budget. | Planned | [details](milestones/M29-base-building.md) |
| M30 | Planting and cooking | World time, tilled fields, crops per realm that grow while the server runs, cooking stations, three meal slots that raise health and stamina through `Stats`. | Planned | [details](milestones/M30-planting-cooking.md) |
| M31 | Livestock | Goats, sheep, boars and hens: wild herds, taming by feeding, pens, breeding and products by world time; server-moved, out of rollback, never fighting. | Planned | [details](milestones/M31-livestock.md) |
| M32 | Mills and station queues | Stations with fuel and queues that work unattended, water wheels and windmills driving machines through shafts, hoppers and chutes by gravity. | Planned | [details](milestones/M32-mills-and-queues.md) |

M16 is required and independent of the rest. M19 to M32 are the survival world (§4.8), in priority order; from M19 on every milestone ends with a hand play-test by the user instead of being built blind.

## 7. Open questions

None open. Answered on the way:

- M8 kept `lobby.r4b2.de`; it stays (no stellamortis subdomain, decided 2026-11-09).
- Exact CC0 packs: KayKit in M2, Quaternius and ambientCG in M9; M12 picks fantasy packs.
- M12 planet travel: a hub with portals, one planet loaded at a time (decided 2026-11-09).
- M13: application ID and what Discord shows are in the M13 row.
- After the PoC (2026-11-14): a persistent survival world on several large round realms; characters saved on the player's machine; enemies in a fixed rolled back pool; levels with perk trees and set perks; real gear slots. All in §4.8.

## 8. Open items to clarify after the last milestone

Everything left open, deferred or decided on the way. Add to it whenever a milestone leaves something open; strike items when they are settled. Verification goes to M15: features are built "blind", trusting tests and screenshots, and checked there.

Decided (2026-11-09):

- Player host: the game ends for everyone when the host quits; no host migration (M11 adds the "The host left" path).
- 6 players (`GameServer.MAX_PLAYERS`) is enough. Background, for if it ever matters: at 6 the server core is saturated (30 tps on average, worst seconds 21–25), at 8 it fell to 13 tps, at 10 to about 2. The cost is netfox's server-side rollback in GDScript (it diffs and serializes every node for every peer for every resimulated tick); the way to 10 would be a netfox patch that serializes each node once per tick. Sending only the newest resimulated tick breaks remote players.
- Bandwidth of 30–40 kB/s per player at 6 players (2–3 kB/s back) is fine.
- The Warden's gravity well stays a drag (`Gravity.pull`), not a real gravity zone.
- Boss health scales with the players present when it rises; late joiners don't change it.
- Enemies don't collide with each other.
- The lobby stays at `lobby.r4b2.de`.
- Lock-on is removed in M10 (Valheim style combat).
- After the Warden, and after a wipe, the group goes back to the hub (M12); the 20 s loop and the instant wipe reset go with it.
- Snapshots go through netfox with our schemas (`net/wire.gd`), not hand-packed arrays as §3.1 planned.
- The load test stays out of `tools/check.py`; run `python tools/run_load_test.py` by hand after netcode or state changes.

- Play-test 2026-11-09, "the character teleports back after combos and boss attacks": not netcode. UAL2's Sword_Regular_A and Sword_Regular_C (light 1 and 3, the dummy's swing, the Warden's sweep) carry root motion on the Root bone (0.9 m and 1.7 m, 3.4 m on the Warden), so the model walked away from its body and snapped back when the clip ended. `CharacterModel._pin_root` keeps every clip's root in place sideways; `tests/character_model_test.gd` guards it. A combo bot under 100 ms lag (`--bot-plan=combo_walk`, `STELLAMORTIS_SNAP_LOG=1`) saw only 0.1 to 0.3 m rollback nudges against the Warden.

Moved to milestones:

- Play-testing, the network test fighting the encounter under lag, a friend on another network, the `--host --bot` hang (possibly fixed after M14: a bot killed and respawned near the keep never counted as moved, now `_bot_moved` remembers it), unseen effects (gravity well, phase 2, roll, M10's damage numbers; the telegraph edge was seen in an M12 screenshot), M11's menu round trips (menu, game, Leave to menu, a second game in the same process; a friend seeing "The host left"): M15.

- Platforms in M15: CI exports Linux, Windows and macOS on every release (all green since v0.13.0), but only Linux was run by hand; run the exported Windows and macOS builds (menu, solo, host and join, presence, the spawned local server).
- M12 to check in M15: portal travel in a networked game (prediction across a 700 m jump, the view snap), the keep from every side, crossbow and shield held right, the undead and Warden clips and gear in a fight, the realm resetting when players come back, the hall's area lights on every preset.

- M13 to check in M15: the presence on a running Discord (Linux with socat passed on 2026-11-09: handshake and SET_ACTIVITY, the user saw it in Discord; still to see: Windows named pipe, macOS nc), the party size updating as friends join, the logo showing once uploaded. For the user: upload `game/assets/logo/stellamortis-1024.png` in the developer portal as the app icon and as a Rich Presence art asset named `logo`.

- Outfits (2026-11-09, after M13): to check in M15 how the rangers, squires and the dead look in a fight (outfit clipping in the UAL clips, the hood and hair, the weapon grips on the new hands, the hit flash on several stacked meshes).

- Play-test 2026-11-14, the roll still glided: the 2026-11-10 fix below eased the body over the last 30 % of the roll into walking speed along the held direction, but UAL1's Roll clip plants its feet at 60 % of its length and stands up in place (its root motion twin `Roll_RM` stops there), so the standing model slid about 1.3 m, more with a direction held. Now the body travels for `SimPlayer.ROLL_TRAVEL` (70 %) of the roll, brakes within two ticks and stays put until the roll ends, whatever the input; `PlayerView` stretches the clip's travel part over the body's travel and its stand-up over the rest (`ROLL_CLIP_TRAVEL`). `ROLL_EASE` is gone. The first version stopped too suddenly (the user, same day): the second half of the travel now slows to a quarter of the roll speed before the stop (`ROLL_SLOW`, `ROLL_END`), and `roll_speed` is 11.5 (was 8.5) to keep the distance at about 4.2 m. With a direction held there is no stop at all: the travel eases into walking speed along it and the view goes from the roll straight into the walk; the stand-up only plays when nothing is held. To check by hand: the stop reads as planted, and the 0.18 s of standing up does not feel sluggish.
- Play-test 2026-11-10: the body glided on after a roll ended (8.5 m/s braking at ground_accel while the model already stood). The last `SimPlayer.ROLL_EASE` (30 %) of a roll now eases from roll speed into walking. The Warden was too small and plain: it is 4.2 m now (was 3.0; sweep reach 5.6, slam reach 4.0 at offset 3.0) with horns, an iron crown, spiked pauldrons, a ragged cape and brighter eyes with a face light, all built in code (`Gear.horns`, `crown`, `pauldrons`, `cape`). No CC0 model fit (Quaternius' monster packs are cartoony). M15: check the roll's end feels right and the Warden reads as scary at night.
- Play-test notes 2026-11-10, second round: the HUD and menus were tiny on high resolutions (no stretch mode); `window/stretch/mode` is `canvas_items` now, so the UI scales from the 1280x720 base (1.5x at 1080p, 3x at 4K). The pause menu shows the room code with a Copy button. Stairs: `SimPlayer._step_up` walks up ledges to `STEP_HEIGHT` (0.45 m) after the slide stopped (test_move only, so rollback replays it), `floor_snap_length` follows stairs down; `tests/movement_test.gd` climbs the realm's test stair. A wrong room code no longer shows the world: the main menu stays on top with "Joining room ..." (Cancel or Esc) until `GameClient.entered`, a failed join returns there with the reason. Dropped connections: clients warn on the HUD after `GameClient.SILENT_WARN` (2 s) without a pong or stats from the server and leave after `SILENT_LEAVE` (8 s) ("Lost the connection to the host"); the server drops a player silent for `GameServer.SILENT_DROP` (10 s), and every player sees "X joined", "X left", "X lost the connection" (`Net.notice`, protocol 12). M15: check the UI scale on 1080p and 4K, the stairs feel (and walking down them), the joining screen with a wrong and a right code, and killing a host or a client mid-game.
- Play-test notes 2026-11-10, third round: the game was far too dark (characters and walls in shadow read as black). Ambient light is brighter (0.42, 0.45, 0.58 at 1.8, was 0.3, 0.33, 0.45 at 1.0), AgX exposure 1.25, the moon 1.4 (was 1.1), SSAO intensity 1.2, contrast 1.02 (was 1.1). Blocking or aiming the crossbow while walking had no walk animation (the upper-body pose slid along): `CharacterModel.mix` builds `Walk_Shield` and `Walk_Aim` from the legs of `Walk` and the upper body of `Idle_Shield` / `Pistol_Aim_Neutral`, played at ground speed / `PlayerView.WALK_CLIP_SPEED` (1.8 m/s, a guess). Sideways and backwards still show the forward walk. M15: check the brightness on every preset (still night, not washed out) and the shield walk.
- M14 to check in M15: listen to every sound (the synthesized ones were never heard while building: twang, telegraphs, embers, hum, wind, fire), the mix (ambience, torches and footsteps against combat), 3D falloff, the volume slider. Swings and hits were replaced on 2026-11-10 (StarNinjas recordings, slash hits from Kenney) after the user disliked the first ones; check they land.

M19 task 1 (knockback and flinch, 2026-11-14), open: the numbers (`knockback` m/s and `flinch` s in `data/attacks/*.tres`, `Tuning.block_knockback`, `bolt_knockback`, `bolt_flinch`, `Enemy.poise`/`shove`/`flinches`) were set without a play-test: check in the M19 play-test that lights stagger without stopping mobs, heavies interrupt windups, and the Warden slides a hair. Killed enemies are not pushed (they skip the push, `DOWN` has no `_walk`). Enemy `flinch` on enemy attacks is unused (players stagger for `Tuning.hurt_time`). `TrainingDummy` flinches but does not slide (it never walks).

M19 task 2 (hit stop, shake, bursts): views react to what they see (`EnemyView` health drop, `PlayerView` health drop and new `swing_hits` bits), so nothing is deduplicated beyond comparing with the last seen value, as `_sounds` does. Left open: blocked hits were not screenshotted (no bot plan blocks a swing); a hit on an enemy shakes only through the attacker's `swing_hits` (bolt hits do not shake); hit stop on the attacker waits for the next frame after the hit lands, so it lags the victim's by one frame; the numbers (`HitEffects` constants) wait for the play-test.

M19 task 3 (deaths, layered hit sounds): `EnemyView._burn` derives the burn from `Action.DOWN` + `action_time` (`LINGER` 2 s, `BURN_TIME` 1.4 s) and `CharacterModel.dissolve` swaps in `shaders/burn_away.gdshader` (restored when the enemy leaves DOWN). No mob was killed on camera (the combo bot dies to them first); the dissolve was checked by driving the view timer with a temporary clock on live mobs. Open: the real kill-to-ash sequence, hit layers (`thud` and `boom` are Kenney punches, the blade layer is the old `hit`; heavy means damage over `HitEffects.BLADE_WEIGHT` x 50) and the ember look wait for the play-test; the burn does not dissolve non-StandardMaterial3D surfaces' textures (none today); dead mobs' ember bursts share the 8-node pool with blood.

Still open (§3.1, not in a milestone yet):

- The compositor screen-space distortion for the gravity well (a glowing shell with motes for now).
- Stencil x-ray for players seen through walls.
- Collision on `GPUParticles3D`, `MultiMeshInstance3D` for debris, visibility ranges.
- Shader baker for exports and a check that ubershaders avoid hitches in the release builds.
- From M12: LightmapGI needs an editor bake, and the levels are built in code at runtime; it waits for levels saved as scenes. `AnimationTree` with blend spaces and foot IK (`TwoBoneIK3D` exists in 4.7) would replace `CharacterModel.play_timed`, which the rolled back views rely on; left out. Decals for impacts left out. Only one realm; more planets mean more `Layout` entries and portals.

Open from the 2026-11-14 planning (§4.8): food, rest, day and night are not planned yet; whether 1000 m is the right realm radius, and the enemy pool size, wait for M20's play-test and M21's load test.

Waiting on the user: M16 frame pacing (check in F3), M19 hit feel (play-test). Milestones not started: M20 to M32 the survival world (§4.8); optional: M17 Wooting analog, M18 telemetry. M15 test round is done (2026-11-14). Briefs for all of them are in `docs/milestones/`.
- M20 task 1 (world seed handshake, `Net.PROTOCOL_VERSION` 15): `World.build(seed, name)` only stores the seed today. The arena, dummies and encounter stay in `World._ready`: the enemies are rolled back nodes that netfox finds by path and the server sends their state from its first tick, so building them only when `Net.world` arrives would leave a window of state for missing nodes, and `GameClient._ready` hands the arena to `Graphics.apply`. Task 2 puts terrain behind `build`; task 3 builds the arrival chunks there too. A client that never answers `Net.world_ready` holds its player slot until it disconnects (same as a client that never syncs its clock).
