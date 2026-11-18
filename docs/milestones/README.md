# Milestone briefs

One file per milestone. `docs/PLAN.md` §6 is the overview with every milestone's status; the files here hold the details. M0 to M14 were finished before briefs existed, so their files only keep the original "done when" text. From M16 on each brief splits the milestone into tasks that one worker (a Sonnet or Opus subagent, or a person) can build alone, one commit (or a few) per task, in the order given unless the brief says tasks are independent.

`docs/PLAN.md` stays the source of truth for design (§4.8 for the survival world). A brief says how to build it. When a brief and the code disagree, the code is right: fix the brief in the same commit.

## Rules for every task

Read first: `CLAUDE.md`, `docs/PLAN.md` §4 (architecture) and §4.8, this file, the milestone's brief, then the files the task names.

Code:

- Godot 4.7, GDScript statically typed everywhere. Check engine classes and settings against the 4.7 docs; a quick existence check is an `extends SceneTree` script run with `godot --headless -s`.
- `sim/` decides, `client/` shows. Sim code never reads input or draws; views never decide outcomes. Headless processes draw and play nothing.
- Numbers live in data (`game/data/*.tres`, `Tuning.data()`), not in code.
- `enum` names must not shadow native classes.

Rollback (read the netfox rollback caveats before touching it):

- Every rolled back variable is in its node's `STATE` list and in one packed group (`SimPlayer.MOTION`/`COMBAT`/`BOLTS`, `Enemy.net_combat`/`net_bolts`), and has a serializer in `net/wire.gd`. `tests/wire_test.gd` fails otherwise. A full state must fit 508 bytes.
- Nothing is spawned or freed inside rollback. Rolled back nodes exist on every peer from the start, with the same path; they are hidden and woken, never created.
- A player changes an enemy only inside its own `_rollback_tick` and calls `SimPlayer._mutate(enemy)` afterwards.
- Bump `Net.PROTOCOL_VERSION` when a RPC, rolled back state or input changes.
- Things that are not combat (inventory, world objects, stats) stay out of rollback: the server decides and tells clients by reliable RPC, with a snapshot at join.

Theme: dark medieval, Viking, northern fantasy (`docs/PLAN.md` §3.2). No sci-fi words or looks. Color is reserved for meaning.

Look: every model follows `docs/STYLE.md` (flat-shaded, vertex colors from the realm's palette, triangle budgets, the generator contract). Read it before any visual task. Models are generated (`client/meshgen/`, or `tools/make_bodies.py` for skinned ones), not downloaded.

Assets: third-party content is only the UAL rig and clips, sounds and fonts, CC0 (or the licenses already in use). Record every new one in `docs/RESOURCES.md` with source, version or commit, and license. Vendor only the files used. When a milestone removes a kit, its files and its row go in the same commit.

Done means:

- The task's tests exist and pass, and `python tools/check.py` is green.
- After a change to combat, enemies, the bots or netcode: `python tools/playtest.py --suite` (about two hours with the soak; `--repeat=5` for rates, `--short` caps each scenario at 30 s) and compare with the baselines in `docs/PLAN.md` §8 (M24 task 4); the scenarios' expectations fail the run.
- After a change to rolled back state, the enemy pool or the tick: `python tools/run_load_test.py` still holds 29 tps with 6 bots; put the numbers in the commit message.
- Visual work comes with screenshots (`--screenshot=PATH`, `--spawn`, `--look`; see `CLAUDE.md` "Boot").
- Commits are semantic commits (`type(scope): summary`).
- No pull requests (the user's rule, 2026-11-14): a finished task is committed and pushed straight to `main` by the main session, after it reviewed the worker's diff and ran the checks. Every push to `main` publishes a release, so push finished work only.
- What the task left open goes to `docs/PLAN.md` §8; what needs a person playing goes to `docs/PLAYTEST.md`.
- The last task of a milestone updates "Where we are" in `CLAUDE.md`, sets the milestone's status to Done with date and release in `docs/PLAN.md` §6 and in the `Status:` line of its file, and raises `VERSION`'s minor by one (milestones finish out of order, so the minor is not the milestone number).

Not done by workers: committing or pushing (the main session does both after review), changes on the gvm host, play-test verdicts.

Play-tests are batched (the user's call, 2026-11-14): a milestone is finished when it is built and checks are green; its status becomes "Built (date, release), play-test pending". Everything only a person playing can judge (feel, look, sound, numbers, what tests and screenshots could not show) goes into `docs/PLAYTEST.md` under the milestone, one checkbox per item, added by the task that built it. The user plays several milestones in one round and gives the feedback at once; fixes from it go into later work.

## Models

Each task names a model. **Opus**: netcode, rollback, terrain, anything where a subtle mistake desyncs peers. **Sonnet**: data, views, UI, content, sound.

## Brief template

```
# Mn Name
Goal            what the player gets, in two sentences
Depends on      milestones and tasks that must be merged first
Tasks           per task: model, files, reuse, steps, tests, done when
Out of scope    what not to build here
Pitfalls        what has gone wrong before, or will
```

M19 to M22 are written to file and function level; so are M24, M36 and M37. The other planned briefs (M38 to M72) fix goal, tasks, interfaces and done-when; their file level detail is added when the milestone before them lands, because it depends on that code. Whoever finishes a milestone details the next brief as its last task.

## Order

M15 is done. M16 (frame pacing) is required and independent: do it any time. M17 and M18 are optional and wait for the user to ask.

Numbers follow the build order, except that built milestones keep their numbers. Built: M0 to M16, M19 to M24, M33 to M37. M25 to M32 are unused (the survival milestones first had them and were renumbered on 2026-11-17; `docs/PLAN.md` §6 has the mapping).

Next, in order: M38 to M45 the generated look and polish (`docs/STYLE.md`); M46 to M56 combat depth, loot and party tools; M57 to M72 the survival world with its additions.

M24 comes first and needs nothing. M36 and M37 are built. M38 and M39 need M36 and are independent of each other. M40's spike (task 1) can start after M36, the rest of M40 after M39. M44 needs M37; M45 needs M37 and M44.

M46 (damage types) opens the combat block and needs M23. M47 needs M46 and M39. M48 needs M47. M49 needs M47. M50 needs M46. M51 needs M23 and M46. M52 needs M38. M53 needs M46, M50, M51 and M52. M54 and M55 are independent of combat and can be built any time after M24; M55 needs M54. M56 needs M52. After a change to combat, enemies or netcode the M24 suite is run and its expectations are updated.

M57 (levels, perks, sets) needs M23's items and M51's attributes. M58 needs M23 and M57. M59 needs M58 and M51. M60 to M62 (the realms) each need M58 and the realm before them; M60 needs M45's water. M63 needs M38, M51 and M52. M64 needs M46, M50 and M51. M65 needs M44 and M64. M66 needs M52. M67 needs M58. M68 needs M67 and M57. M69 needs M67 and M57; M70 needs M69; M71 needs M69 (M70 only for troughs). M72 needs M67, M64 and M65. M58 to M70 build their models with the kit of M36 and by the style sheet.

Built chain, for the record: M19 (hit feel) was independent beside M20; M20, M21, M22 were a chain; M23 needed M22's world flags and M21's kinds.
