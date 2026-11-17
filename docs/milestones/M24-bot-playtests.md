# M24 Bot play-tests

Status: Built (2026-11-17, v0.27.0), play-test pending (`docs/PLAYTEST.md`).

## Goal

One command runs a headless server and headless clients whose bots fight like players of different skill, alone or as a party, over good and bad connections, and writes a report: who won, how long it took, what killed them, and how the netcode held. Balance and network regressions show up without a person playing; the user's play-tests are left for feel and look.

## Depends on

Nothing new. Builds on the bots of M7 (`GameClient._bot_controls`, `--bot`, `--bot-plan`), `tools/run_load_test.py`, `tools/run_network_test.py`, `tools/lag_proxy.py`, `STELLAMORTIS_SERVER_STATS`, `STELLAMORTIS_SNAP_LOG`. Number 24 was free after the renumbering of 2026-11-17 and this is built before M36, so numbers still follow the build order.

## Design

- **A bot is a client, not a cheat.** `BotBrain` (`game/scripts/client/bot/bot_brain.gd`) fills `PlayerControls` each tick, exactly where `GameClient._read_controls` does for a person. It sees only what a client has: its own `SimPlayer`, the players and enemies in `World` as they are predicted and interpolated on that client, enemy actions (the telegraph a player would see), its inventory. It never reads server state and never calls sim functions. So a bot under 150 ms lag suffers what a player would.
- **Skill is data.** `BotSkill` (`game/scripts/client/bot/bot_skill.gd`, `game/data/bots/novice.tres`, `average.tres`, `good.tres`, `expert.tres`):
  - `reaction_ms` and its spread: every observation passes a delay queue before the brain may act on it.
  - `dodge_chance`, `parry_chance`, `block_chance` per telegraph, and the timing error of each in ms.
  - `aim_error_deg` and how fast it settles while drawing.
  - `stamina_reserve`: how much stamina it keeps back; a novice swings itself empty.
  - `aggression`: how long it stays in reach, how early it retreats (`retreat_health`).
  - `combo_length`, `uses_heavy`, `uses_riposte`.
  - `mistake_rate`: wrong roll direction, attack into a telegraph, panic roll.
  - `presses_per_second`: a cap on input changes.
- **Behavior** is a small state machine, the same for every skill: travel to a goal, engage (melee or ranged role by worn weapon), evade, recover (back off, regain stamina), loot, body run after a death, follow the party. Travel is a straight line along the ground with the trunk sidestep idea of `Enemy._around`; no navigation mesh. Goals: `--bot-goal=camp|boss|roam|dummy|follow`.
- **Reproducible.** Each bot has `--bot-seed`; all its randomness comes from that seed. A run is not bit-identical (real time, network), but a scenario repeated N times gives a distribution, and the report shows mean and spread.
- **Fully headless.** Server and clients run `--headless`; nothing is drawn or played. The old plans (`combo`, `combo_walk`, `shoot`, the circle walk) stay as `--bot-plan` values for the screenshot and network tests and move into `client/bot/`.
- **Event log.** With `STELLAMORTIS_EVENT_LOG=PATH` the server appends one JSON line per event after the rollback step, from confirmed state only: hit (attacker, target, attack id, damage, blocked, parried), death (who, by what attack), kill, roll, parry, enemy wake and sleep, encounter phase changes, player join and leave, plus the stats line each second. Clients append to their own file: ping, corrections (the existing snap log: tick, distance), inputs per second.
- **Desync check.** Every 30 ticks server and each client log a hash of that client's player state at a confirmed tick (position quantized like the wire, health, action). The runner compares them: a mismatch that outlives the rollback window is a desync and fails the run.
- **Scenarios** are files (`tools/scenarios/*.json`): world seed, spawn or encounter, duration, the party (per bot: skill, role, seed, lag, jitter, loss), repeats, and expectations. `tools/lag_proxy.py` gets one port per bot and packet loss, so one party can mix a fibre player and a bad wifi player.
- **Runner and report.** `python tools/playtest.py SCENARIO [--repeat=N]` or `--suite`: starts everything, waits, reads the logs, writes `build/playtest/<scenario>/report.md` and `report.json`:
  - Fight: win or wipe, time to kill, deaths per player, damage dealt and taken per skill, damage taken per enemy attack id (what kills people), parry and dodge success, stamina-empty time.
  - Network: tps and tick loop, resimulated ticks, corrections per minute and their size per lag class, kB/s, desyncs.
  - Expectations fail the run: for example "expert party of 4 beats the Warden in 9 of 10", "a novice alone dies to the Warden in 9 of 10", "no correction over 2 m at 150 ms lag", "no desync", "29 tps".
- **In the checks.** `tools/check.py` runs one short smoke scenario (two bots, a camp, 30 s) beside the network test. The suite is run by hand and before a milestone that changed combat or netcode closes; `docs/milestones/README.md` says so.

## Tasks

### 1. Brain and skills (Opus)

Files: new `scripts/client/bot/bot_brain.gd`, `bot_skill.gd`, `bot_plans.gd` (the old plans moved out of `game_client.gd`), `data/bots/*.tres`; `scripts/client/game_client.gd` (`_bot_controls`, `_check_bot`, `_bot_gear`), `scripts/boot/main.gd` (`--bot-skill=NAME`, `--bot-goal=`, `--bot-seed=`), new `tests/bot_brain_test.gd`.

Reuse: `Combat.in_arc` and the `AttackDef` numbers to judge reach, `Combat.aim_target` for aiming, `PlayerControls` as the only output, `tests/support/flat_ground.gd` for tests.

Steps: the observation delay queue; the state machine; melee and ranged engage; evade from telegraphs (read `Enemy` action and `action_time` as shown on the client); stamina and retreat; loot and equip (the gear step exists); body run; follow.

Tests (headless, on the flat ground, one process): an expert kills a swordsman without dying in 20 of 20 seeded runs; a novice takes clearly more damage than an expert over the same seeds; no bot output exceeds `presses_per_second`; the same seed gives the same input sequence against a scripted enemy.

Done when: `--bot --bot-skill=good --bot-goal=camp` on a real server clears a camp, and the old network and load tests still pass with the moved plans.

### 2. Event log and desync check (Opus)

Files: new `scripts/net/event_log.gd`; `scripts/net/game_server.gd`, `scripts/sim/sim_player.gd`, `scripts/sim/enemy.gd`, `scripts/sim/encounter.gd` (emit from confirmed ticks only, outside rollback resimulation), `scripts/client/game_client.gd` (client log, state hash), new `tests/event_log_test.gd`.

Steps: the log writer (off unless the variable is set; buffered, flushed each second); events from the place where the server already knows a tick is final; the state hash on both sides.

Tests: a scripted fight logs each hit once although the tick was resimulated; hashes agree in a clean local run; a deliberately changed client value is reported.

Done when: the load test with the log on loses less than 1 tps.

### 3. Scenarios, runner, report (Sonnet)

Files: new `tools/playtest.py`, `tools/scenarios/*.json`, `tools/lag_proxy.py` (a port per bot, loss), `tools/_common.py`, `tools/check.py` (the smoke scenario), `README.md`.

Scenarios to ship: `smoke`, `camp_solo_<skill>` for the four skills, `camp_party_mixed`, `boss_solo_<skill>`, `boss_party_expert`, `boss_party_mixed_lag` (0, 60, 150 ms and one with 2 % loss), `soak_30min` (six bots roaming and fighting, desync and leak watch).

Done when: `python tools/playtest.py --suite` writes reports for all of them and exits non-zero when an expectation fails.

### 4. Baselines, and close (Opus)

Files: `tools/scenarios/*.json` (expectations from measured runs), `docs/PLAN.md` §8 (the numbers, what the bots found), `docs/PLAYTEST.md` (items the bots now cover are marked so, the rest stay for the user), `docs/milestones/README.md` ("Done means": run the suite after combat, enemy or netcode changes), `CLAUDE.md`, `VERSION`.

Steps: run the suite ten times, set expectations with room for the spread, write down every balance or netcode finding as an open item (not fixed here unless trivial). Detail M36's first task if needed. Close the milestone.

Done when: the suite is green twice in a row on this machine and its findings are in §8.

## Out of scope

Bots that learn (no ML). Faster than real time (netfox ticks in real time; a scenario takes as long as its fight). Bots judging feel, look or sound. Navigation meshes. Bots as party members for real players. Running the suite in CI (the smoke scenario only; the runners are small).

## Pitfalls

- All processes share one CPU: six clients and a server are already at the limit (§8). The report must separate "the server was starved" from "the netcode broke": keep the server's own tick loop time in every report, and run big parties with the bots at a lower client frame rate.
- A bot that reads the server, or reads enemy state earlier than a client sees it, measures nothing. The delay queue sits in front of every observation, also the bot's own health.
- Events must be written once: emit from confirmed ticks, never inside `_rollback_tick` resimulation, or every hit appears several times.
- Skill numbers are guesses until a person compares: the user plays one camp and the Warden once and says which bot plays like them. That calibration is one item in `docs/PLAYTEST.md`.
- The state hash must use the same quantization as `net/wire.gd`, or it reports float noise as desync.
- Random seeds make runs repeatable only in distribution. Expectations are rates over repeats, never "this exact run".
- Keep bot code out of exported builds' hot path: one `if bot` at the reader, nothing else.
