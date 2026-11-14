# M19 Hit feel

Status: built (2026-11-14, v0.17.0), play-test pending (`docs/PLAYTEST.md`).

## Goal

Hitting an enemy and being hit read clearly and feel heavy. Today a hit is a health change, a flash and a number; after M19 enemies are pushed and flinch, the blow pauses for a moment, the camera kicks, blood or sparks fly, and the dead fall and burn away.

## Depends on

Nothing. Can run beside M20. Tasks 2 and 3 need task 1 merged.

## Tasks

### 1. Knockback and flinch in the sim (Opus)

Files: `game/scripts/sim/attack_def.gd`, `sim/enemy.gd`, `sim/sim_player.gd`, `sim/mob.gd`, `sim/warden.gd`, `net/wire.gd`, `net/net.gd`, `game/data/attacks/*.tres`, `game/tests/combat_test.gd`, `tests/wire_test.gd`.

Reuse: `Enemy.take_hit` (`enemy.gd:167`), `Enemy._set_action`, `Enemy._walk` (velocity is already in `Enemy.ACTOR_STATE`), `SimPlayer._strike` (`sim_player.gd:510`), `SimPlayer._fly_bolts` for bolt hits, `SimPlayer._take` for hits on players.

Steps:

1. `AttackDef`: add `knockback` (m/s away from the attacker) and `flinch` (seconds). Set them in the player attacks (light small, light 3 and heavy large) and the enemy attacks.
2. `Enemy.take_hit(amount, from, knockback, flinch)` (built that way: bolts have no `AttackDef`, they use `Tuning.bolt_*`): add the push to `velocity` along the tangent away from `from`, and enter a new `Action.FLINCH` for `def.flinch` unless the enemy is in `RISE`, `DOWN`, `HIDDEN` or a parried `STAGGER`. A flinch interrupts a windup only if the enemy's `poise` allows it: add `poise` to `Enemy` (a per-kind constant, not rolled back; `flinches = false` and `shove = 0.15` for the Warden). The flinch length is rolled back as `Enemy.flinch_time` (ticks, in `net_combat`).
3. Mob and Warden ticks: `FLINCH` counts down, then returns to `IDLE`; velocity decays through `_walk` with no wish.
4. Players: `SimPlayer._take` applies the enemy attack's knockback to the player's velocity (blocked hits: a quarter).
5. Wire and protocol: `Action` grows by one value (check its serializer still fits), bump `Net.PROTOCOL_VERSION`.

Tests (`combat_test.gd`): a heavy pushes a mob further than a light; a flinch delays a mob's windup; the Warden does not flinch; a blocked hit pushes the player less; rollback replay of a hit gives the same enemy position (`movement_test.gd` has the deterministic replay pattern).

Done when: tests pass, `python tools/check.py` green, load test numbers unchanged.

### 2. Hit stop, shake, blood and sparks (Sonnet)

Files: `game/scripts/client/enemy_view.gd`, `client/player_view.gd`, `client/camera_rig.gd`, `client/character_model.gd`, `client/hud.gd`, new `client/hit_effects.gd`.

Reuse: `EnemyView._pop_number` and `_pop_text` (enemy damage numbers exist already), the hit flash in `EnemyView._process`, `Hud._show_damage`, `Sounds.play`, `Graphics` presets for particle counts.

Steps:

1. Hit stop is view only: when a view sees its sim node's health drop (victim) or its `swing_hits` gain a bit (attacker), it holds the model's pose for 2 to 5 frames scaled by damage. The views pose from sim state each frame (`_pose`, `CharacterModel.play_timed`), so hold by skipping `_pose` for that time; never touch sim time.
2. `CameraRig.shake(strength)`: a decaying offset on the camera, scaled by damage dealt or taken, capped; a setting to turn it down (`Settings`, `SettingsPanel`).
3. `HitEffects.burst(at, normal, kind)`: one-shot `GPUParticles3D` for blood (flesh), sparks (the Warden's iron, shield blocks), wood chips (shield hits on the player). Pool the nodes.
4. Stronger flash and a short scale punch on the hit model; numbers for heavy hits are larger.

Done when: screenshots of a light hit, a heavy hit and a blocked hit at the keep's dummies (`--spawn=4,0,-7.6` is stale since M12: find the dummy position in `Layout.DUMMIES`), and the user's play-test says hits land.

### 3. Deaths and layered hit sounds (Sonnet)

Files: `client/enemy_view.gd`, `client/sounds.gd`, `game/shaders/` (new dissolve shader), `tools/make_sounds.py` if a synthesized layer is needed.

Steps:

1. Death: the fall clip plays, the body lingers 2 s, then burns away from the edges in embers (a dissolve shader on the model's materials driven by a view timer, plus ember particles). `Action.DOWN` since N ticks drives it, so late joiners see a consistent state.
2. Hit sounds in layers picked by damage: a body thud always, a blade layer for heavy hits, a low boom for kills. Add the names to `Sounds.library`; record any new files in `docs/RESOURCES.md`.

Done when: screenshot burst (`--frames=N`) of a dying mob, sounds heard by the user.

## Out of scope

Loot (M23). New attacks or enemies. Ragdolls.

## Pitfalls

- Views are replayed against rolled back state: derive effects from state changes the view observes, and guard against firing twice when a rollback restores and reapplies a hit (compare against the last confirmed value, as `PlayerView._sounds` does).
- `Enemy._sync_body` must only run on change; setting the shape rebuilds the body.
- Hit stop that touches `NetworkTime` or sim ticks desyncs peers. It is a pose hold, nothing else.
