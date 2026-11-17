class_name BotSkill
extends Resource
## How well a bot plays (M24): every number a BotBrain's play depends on. Files live in
## res://data/bots/, the id is the file name (novice, average, good, expert). The Behavior group
## is the same for every skill, so the files leave it at its defaults.

@export_group("Perception")
## Every observation (also the own health) is this late when the brain may act on it, plus a
## random part of up to the spread (a normal deviation).
@export var reaction_ms := 350.0
@export var reaction_spread_ms := 80.0

@export_group("Defense")
## Per telegraph: the chance to answer it with a roll, a parry (a block started just before the
## hit) or a plain block, tried in that order (parry first).
@export_range(0.0, 1.0) var dodge_chance := 0.5
@export_range(0.0, 1.0) var parry_chance := 0.1
@export_range(0.0, 1.0) var block_chance := 0.5
## Deviation of the press time of each answer, in ms.
@export var dodge_error_ms := 90.0
@export var parry_error_ms := 110.0
@export var block_error_ms := 110.0
## Chance per telegraph of a slip: a roll the wrong way, a panic roll at a wrong time, or an
## attack into the telegraph.
@export_range(0.0, 1.0) var mistake_rate := 0.1

@export_group("Aim")
## Deviation of the aim in degrees, and how fast it settles while drawing (per second).
@export var aim_error_deg := 5.0
@export var aim_settle := 2.0

@export_group("Fighting")
## Stamina kept back: attacks start only above it (0 swings itself empty), the bot backs away to
## regain it when it falls under it.
@export var stamina_reserve := 15.0
## 0 to 1: how soon it swings again after a combo (1 at once, 0 a full `pause_seconds` later).
@export_range(0.0, 1.0) var aggression := 0.7
## Below this share of health it backs away for `recover_seconds` (and eats what heals).
@export_range(0.0, 1.0) var retreat_health := 0.3
@export var combo_length := 2
@export var uses_heavy := false
@export var uses_riposte := false
## Cap on new button presses per second.
@export var presses_per_second := 4.0

@export_group("Behavior")
## It engages enemies this close (m); it sees this far.
@export var notice := 22.0
@export var sight := 45.0
## Seconds without an enemy, after a kill, after which a camp bot calls the camp cleared.
@export var camp_quiet := 10.0
## Metres of a search leg when it has nowhere known to go.
@export var search_leg := 40.0
## It walks to drops this close (m) and gives up on one after loot_seconds.
@export var loot_radius := 25.0
@export var loot_seconds := 8.0
## Following: closes in beyond follow_far, stands within follow_near (m).
@export var follow_near := 5.0
@export var follow_far := 8.0
## Ranged role: the band of distances it keeps to the target (m).
@export var ranged_near := 8.0
@export var ranged_far := 16.0
## A press is held this long (s), so no tick loop misses it.
@export var tap_seconds := 0.12
## The pause after a combo at aggression 0, and how long it backs away to heal or breathe.
@export var pause_seconds := 1.0
@export var recover_seconds := 4.0
## Stamina above the reserve it wants back before it fights on after backing away.
@export var recover_margin := 20.0
## How long the body run lasts at most, in seconds.
@export var body_seconds := 90.0
## Seconds between new rolls of the aim error in melee.
@export var aim_period := 0.5
