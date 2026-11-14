# Milestone briefs

One file per milestone from M19 on. Each brief splits the milestone into tasks that one worker (a Sonnet or Opus subagent, or a person) can build alone, one PR per task, in the order given unless the brief says tasks are independent.

`docs/PLAN.md` stays the source of truth for design (§4.8 for the survival world). A brief says how to build it. When a brief and the code disagree, the code is right: fix the brief in the same PR.

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

Assets: CC0 (or the licenses already in use). Record every new one in `docs/RESOURCES.md` with source, version or commit, and license. Vendor only the files used.

Done means:

- The task's tests exist and pass, and `python tools/check.py` is green.
- After a change to rolled back state, the enemy pool or the tick: `python tools/run_load_test.py` still holds 29 tps with 6 bots; put the numbers in the PR.
- Visual work comes with screenshots (`--screenshot=PATH`, `--spawn`, `--look`; see `CLAUDE.md` "Boot").
- Commits and the PR title are semantic commits (`type(scope): summary`).
- What the task left open goes to `docs/PLAN.md` §8.
- The last task of a milestone updates "Where we are" in `CLAUDE.md`, marks the row in `docs/PLAN.md` §6 done, and sets `VERSION` to `0.<n+1>` for milestone Mn.

Not done by workers: pushing to `main` (it publishes a release), changes on the gvm host, play-test verdicts. Each milestone ends with the user's play-test.

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

M19 to M22 are written to file and function level. M23 to M29 fix goal, tasks, interfaces and done-when; their file level detail is added when the milestone before them lands, because it depends on that code. Whoever finishes a milestone details the next brief as its last task.

## Order

M19 (hit feel) is independent and can run beside M20. M20, M21, M22 are a chain. M23 needs M22's world flags and M21's kinds. M24 needs M23's items. M25 needs M23 and M24. M26 to M28 each need M25 and the realm before them. M29 needs M25.
