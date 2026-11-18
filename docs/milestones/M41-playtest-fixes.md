# M41 Play-test fixes

Status: Built (2026-11-18, v0.31.0), play-test pending.

## Goal

What the play-test of 2026-11-18 found wrong in the look gets fixed before anything new: shadows on High and Ultra are as readable as on Medium, weapons sit in the fist and the shield on the outer forearm, the forest has big old trees, more grass and bushes that look like bushes, and the male faces are not buried in hair.

## Depends on

M37, M39, M40 (built). The four tasks are independent of each other and can run in any order or side by side (they touch different files).

## Tasks

### 1. Shadows on High and Ultra (Sonnet)

Files: `scripts/client/graphics.gd` (`apply`), `scripts/sim/arena.gd` (environment, sun), `docs/PLAYTEST.md`.

Steps: find which setting makes shadows near black from High up. What changes there: SSIL (`high_up`), SDFGI and SSR (`ultra`), TAA instead of SMAA (`ultra`), the soft shadow filter quality per preset; SSAO and volumetric fog already run on Medium. Take the same screenshot on all four presets (`--seed=1234 --graphics=X --screenshot=PATH`, the arrival and the forest edge), toggle the suspects one at a time, then fix the cause (for example SSIL or SDFGI energy and the ambient light so they brighten shade instead of darkening it, or SDFGI off on a flat-shaded world). Measure frame times per preset (`STELLAMORTIS_FRAME_STATS`).

Done when: screenshots of the four presets side by side show shade of about the same brightness; frame times in the commit message; play-test item added.

### 2. How hands hold gear (Sonnet)

Files: `scripts/client/gear.gd`, `scripts/client/character_model.gd` (the `BoneAttachment3D` slots), `scripts/client/player_view.gd`, `scripts/client/enemy_view.gd`, maybe `tools/make_bodies.py`.

Steps: the sword sticks out of the hand like a claw and the shield sits on the inner side of the forearm. Hand gear has its origin at the grip with the long axis +Y (`Gear` header); players attach the sword and crossbow to `RightHand` and the shield to `LeftLowerArm`. Find the hand and forearm bone axes of the M40 bodies (they may differ from the UAL1 mannequin the offsets were made for) and fix the rotation once, where every attach goes through, so enemies holding swords and axes are fixed too. The blade leaves the closed fist past the thumb; the shield's face looks outward from the outer forearm, away from the body.

Done when: screenshots of a player idle, mid-swing, blocking and aiming, and of a swordsman and a berserker, show the grips right; `--gallery=items` is unchanged.

### 3. Trees, grass and bushes (Sonnet)

Files: `scripts/sim/scatter.gd` (sizes and odds of the old kinds), `data/scatter/*.tres` (their `ScatterShape`s), `scripts/client/graphics.gd` (`COVER_DENSITY`, `COVER_RADIUS`, `TRIANGLE_BUDGET`), `scripts/client/meshgen/kinds/bush.gd`, `docs/STYLE.md` if a rule changes.

Steps: more and bigger old trees (a few giants per stand, up to about 1.5 to 2 times today's old trees); the collision shapes scale with them. Denser grass per preset within the triangle budget (raise the budget only with a frame time measurement). Rebuild the bush generator so it reads as a bush at game distance: a few overlapping faceted clumps on short stems, darker inside, per `docs/STYLE.md`.

Done when: before and after screenshots of the forest edge and the open moor on Low and High; `--gallery=bush`; F3 scatter triangles within budget; `tests/scatter_collision_test.gd` green.

### 4. Male faces and hair (Sonnet, needs Blender)

Files: `tools/make_bodies.py` (`SPECS`, the head, hair and beard parts), `game/assets/bodies/`, `scripts/client/character_model.gd` (`_paint` role indices).

Steps: the male bodies' faces look wrong, with hair everywhere. Check whether hair and beard geometry spills over the face and body or whether the role indices paint skin as hair. Fix the head build or the roles, rebuild the nine bodies, `--check` green.

Done when: close-up screenshots (front and three-quarter) of the four player bodies and the dead show clean faces, hair only on the scalp and the beard on the jaw; play-test item added.

The last task to land closes the milestone (`docs/milestones/README.md`).

## Out of scope

New graphics settings (a shadow or brightness slider) unless task 1 cannot fix the presets. Worn armor shown on bodies (still open from M40). Wind sway (M45).

## Pitfalls

- SDFGI and SSIL on faceted, vertex-colored ground behave unlike textured ground; judge by screenshots, not by the numbers in the docs.
- The grip rotation must not be fixed per prop: find the one place every attach goes through.
- Bigger trees need bigger collision in the same commit, or players walk through trunks (M35).
- Grass density costs the 1050 Ti first: Low and Medium keep their budget.
