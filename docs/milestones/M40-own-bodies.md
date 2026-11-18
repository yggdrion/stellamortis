# M40 Own bodies

Status: In progress: tasks 1 (spike), 2 (bodies) and 3 (in the game) done 2026-11-18; task 4 (pick a body) open.

## Goal

Players, squires, the dead and the Warden wear bodies, heads and hair made for this game: faceted, vertex colored, adult. They move with the same animations as before. With this the last third-party models are gone except the skeleton and its clips.

## Depends on

M36 (shader, palette). Task 1 (the spike) can start as soon as M36 is done; the rest after M39, because gear names the body parts it covers. `docs/STYLE.md` §8.

## Design

- Bodies are skinned meshes, so they are made offline, not at runtime: `tools/make_bodies.py` runs Blender in the background (`blender --background --python`), builds each body from parameters, skins it to the UAL1 armature imported from `assets/quaternius/ual/UAL1.glb`, writes vertex colors as role indices, and exports glTF to `game/assets/bodies/`. The outputs are committed; the script is the source. `docs/RESOURCES.md` lists them as ours and notes the Blender version.
- Parameters, not sculpting: build (slim, average, heavy), sex, height, shoulder and hip width, head shape (three), hair (six masses), beard (three), plus the dead's variants (sunken, missing jaw, exposed bone). The Warden is the heavy build at twice the size.
- Body parts are separate surfaces (head, torso, upper and lower arms, hands, upper and lower legs, feet), so armor can hide what it covers.
- Vertex colors hold a role index, resolved to palette colors at load (`CharacterModel`), so one body file serves every skin and hair color and the dead's `rot`.
- `CharacterModel` keeps `play_timed`, `loop`, `show_prop`, `freeze`, `dissolve` and the clip handling (`_pin_root`, UAL2 clips copied onto UAL1). It loses what only the old meshes needed: `wear_head`, `swap_albedo`, `tint`, the outfit bone map and `HUMAN`'s hidden mannequin mesh. `Gear.ranger`, `squire`, `dead` and the Warden's look choose parameters instead of outfit files.
- Clothes are part of the body mesh's color roles at first (tunic, trousers, boots as colored regions with a few raised edges); real garments are gear (M39's generators) worn on top.

## Tasks

### 1. Spike: one body, every clip (Opus)

One average male body through `tools/make_bodies.py`, in the game, playing every UAL1 and UAL2 clip the game uses (walk, roll, the sword combo, block, draw and shoot, zombie clips, the Warden's). Settle skinning: rigid segments with blended rings at the joints, or Blender's automatic weights cleaned by script. Judge on shoulders in the overhead swings, hips in the roll, and the wrist holding the sword. Throwaway quality is fine; the finding goes into this brief.

Done when: a side by side screenshot burst (`--frames`) of old and new body through a combo and a roll, and a written verdict on the skinning method and on whether the Blender path holds. If it does not hold, stop and bring the alternatives to the user (keep Quaternius bodies under a palette shader, or segment-only puppets) before task 2.

### 2. The bodies (Opus)

`tools/make_bodies.py` in full: the parameter set, parts as surfaces, role indices, three levels of detail, both sexes, the dead, the Warden. A `--check` mode that fails when a bone of the UAL skeleton has no weights or a budget is broken. Wire `python tools/make_bodies.py --check` into `tools/check.py` only if Blender is present; CI does not have it, so the committed files are what ships.

### 3. In the game (Sonnet)

`scripts/client/character_model.gd`, `gear.gd`, `player_view.gd`, `enemy_view.gd`: load the new bodies, resolve roles, hide covered parts, looks by peer id as today. Remove `assets/quaternius/outfits/`, `assets/quaternius/characters/` and their rows. Screenshots of every look; the rubberband check (`--bot-plan=combo_walk` with `STELLAMORTIS_SNAP_LOG=1`) still clean; play-test items; milestone closed.

### 4. Pick a body in the menu (Sonnet; added 2026-11-18 on the user's request)

Four player bodies: male A, male B, female A, female B (two builds per sex from task 2's parameters, for example slim/average male and average/heavy female, plus head shape and default hair per type). The choice is saved in `Settings` (`body`, 0 to 3), picked in the main menu (a row of four previews in a `SubViewport` with the idle clip, turning slowly) and in `SettingsPanel`, sent to the server in `Net.hello` and told to every peer with the player's other join data (a protocol bump: `Net.PROTOCOL_VERSION`; not rolled back state, a reliable RPC and a snapshot at join like the name), and `Gear.ranger(peer_id)` picks the body from it instead of the peer id parity. Skin and hair colors stay by peer id for now. Tests: `Settings` round trip, hello carries the choice, `Gear.ranger` returns each of the four. Done when: four looks in screenshots, a joiner's choice shows on the host and the other clients.

## Task 2 result (2026-11-18)

`tools/make_bodies.py [ID ...] [--check] [--skin=rigid|auto]` builds the nine bodies of `SPECS` into `game/assets/bodies/<id>.glb` (and writes each `.import` with the UAL1 bone map): the four player bodies `male_a` (average, short hair, short beard), `male_b` (heavy, square head, long hair, full beard), `female_a` (slim, long hair), `female_b` (average, long head, bun, wide hips), the dead (`dead_male` sunken, `dead_female` bone arms and shins, `dead_skull` bare skull jaw), `berserker` (bare, heavy, full beard) and `warden` (heavy, bald; the game scales it by 2). Parameters in a spec: `sex`, `build` (slim, average, heavy), `head` (egg, square, long), `hair` (bald, buzzed, short, long, bun, braid), `beard` (none, short, full, long), `shoulder`, `hip`, `dead` (sunken, bone, skull), `outfit` (tunic, bare, plate). Height is the model's scale in the game, not a parameter (the mesh must fit the UAL rest pose).

- Parts are material slots, in this order: head, hair, beard, torso, upper_arm, lower_arm, hand, upper_leg, lower_leg, foot (surface index = part index; a part with no faces has no surface, so read the surface's material name, not its index, in task 3). Eyes, nose, brows and ears belong to `head`.
- Vertex colors are role indices, float, red channel = index / 255, no color management: `ROLES` in the script = skin, hair, tunic, sleeve, trousers, boot, belt, eye, bone, rot. Resolve in `CharacterModel` by rewriting each surface's `ARRAY_COLOR` (alpha = roughness, the flat shader reads it) with the palette: skin -> `skin_a..d` and hair -> `hair_a..d` by the player's choice, tunic and sleeve -> `cloth`, trousers -> `cloth_dark`, boot and belt -> `leather`, eye -> `iron`, bone -> `bone`, rot -> `rot`. The dead's flesh is already the `rot` role. Rebuild with `add_surface_from_arrays(..., flags)` where flags = the surface format and `ARRAY_FLAG_USE_8_BONE_WEIGHTS`, as `CharacterModel._head_of` does. Checked in a scratch scene with all nine bodies and `Sword_Idle`: the roles resolve, the flat shader draws them.
- Weights are rigid with blended joint rings (shoulder ring 0.12 m, the deltoid ring overlapping the torso); at most 2 influences a vertex. Fingers, toes and the root have no weights by design (`UNWEIGHTED`): the hand is a fist block, the foot a boot, so a clip curling a finger moves nothing.
- `--check` fails when a non-finger bone has no weights, a vertex has over 4 influences or weights not summing to 1, a body (without head) is over 3000 triangles or the head with hair and beard over 900 (STYLE.md section 5), or a part is missing. Numbers now: 1312 to 1472 triangles a body, 304 to 464 for the head with hair and beard. `tools/check.py` runs `--check` when Blender is installed (`BLENDER` env var or the default path).
- Deviations from the plan: no three LOD files (Godot's import generates LODs, `meshes/generate_lods` is on in the `.import`); the dead's `skull` variant colors the lower head `bone` rather than removing the jaw; the Warden has no armor yet (its `plate` outfit is one flat color, the generated plate of M39 goes on top in task 3).
- Looks: the faces are plain (brow, nose, two eye insets, ears); the bodies differ in build, head, hair and beard but the two sexes differ little at game distance (bust, narrower shoulders, wider hips). Tune the numbers after seeing them in the game (task 3's screenshots).

## Task 3 result (2026-11-18)

- `CharacterModel.new(path, held, scale, look)`: a body under `BODIES` (`CharacterModel.body_path(&"male_a")`) is painted at load by `_paint` / `_resolve` (not headless): the role indices become palette colors (`ROLE_COLORS`; `look.skin` and `look.hair` palette roles, default skin_b and hair_b; `look.roles` overrides a body role with a palette role or a Color), the mesh is rebuilt once per body, look and mesh name (`_painted`) and every surface gets `MeshKit.material()`. `dissolve` gives every surface one `MeshKit.burn_material()` (`burn_amount`). Removed: `wear_head`, `swap_albedo`, `tint`, `skin`, `light_up`, `_each_material`, `_wear`, `_head_of`, the outfit and character constants, `Gear.armor`, `Gear._metal`, `STEEL`, `LEATHER`, `DEAD`; `HUMAN` stays only as the clip source. `assets/quaternius/outfits/` and `characters/` and their RESOURCES rows are gone.
- `Gear.ranger(peer_id)`: body `PLAYER_BODIES[peer_id % 4]` (male A, female A, male B, female B), skin `SKINS[(peer_id / 4) % 4]`, hair `HAIRS[(peer_id / 16) % 4]`; task 4 replaces the body pick with the saved choice. `squire(index)` male A or B, `dead(archer, held, index)` dead_female for archers, dead_male, every third swordsman dead_skull; `berserker` the bare body with a grey-red `PAINT` skin; `Gear.armored(held, scale, plate)` is the Warden and the elite (the `warden` body, belt, tunic and sleeve roles in the plate color; generated helm, horns, crown, pauldrons and cape on top).
- Checked: screenshots of the start (squire), a camp (the dead lying, the player) and the boss site (`build/shots/`, not committed); `tests/character_model_test.gd` runs on `male_a`. Not covered: hiding body parts under armor and worn armor on peers (needs the worn item indices on the wire, a protocol bump; leave it to the milestone that shows armor: M48 or earlier on request); `GearKit.covers` is unused until then. Surfaces are named by the material names of the glTF only if Godot keeps them (not verified); a part that has no faces has no surface.


## Spike result (task 1, 2026-11-18)

Verdict: the Blender path holds. Go on with task 2.

- `tools/make_bodies.py` (Blender 5.3, `blender --background --python`, `--skin=rigid|auto`) imports `UAL1.glb`, deletes the mannequin and clips, builds one average male from faceted 8-sided tubes (one per part, one material slot per part: head, torso, upper/lower arm, hand, upper/lower leg, foot; 606 vertices, 696 faces, flat faces, baked face colors), skins it and exports `game/assets/bodies/male_average_{rigid,auto}.glb`. Only the armature round trip was a risk: after export and Godot import with the UAL1 bone map (`PATH:Rig/Skeleton3D`, copy `UAL1.glb.import`'s params into the body's `.import`) the skeleton has the same 53 bones, the same `GeneralSkeleton` path, global rest origins equal to 1e-6 m and rotations to 0.0007 rad. So the UAL1 and UAL2 clips play unchanged through `CharacterModel._borrow_animations` (a body with no `AnimationPlayer` takes that branch, as outfits do) and `_pin_root` applies as before; no change was needed in `CharacterModel` for the spike.
- Checked in a scratch scene (old ranger, rigid, auto side by side, `animation.seek` through six steps): Sword_Regular_A/B/C, Sword_Attack, Roll, Walk, Sword_Block, Pistol_Aim_Neutral, Zombie_Walk_Fwd, Hit_Chest, Death01, Sprint, Sword_Idle. Nothing snaps or collapses, the sword sits in the hand through the swings, `MeshKit.material()` (flat shader) draws the skinned mesh with the baked colors. Not done: the rubberband check with `--bot-plan=combo_walk`, since nothing in the game loads a new body yet (task 3), and `Gear` is not hooked.
- Skinning, judged on overhead swings (Sword_Regular_C) and the roll: rigid segments with 0.05 to 0.08 m blended rings at the joints (arm tubes weighted along `shoulder`, `upper_arm`, `forearm`, `hand`; legs along `thigh`, `shin`, `foot`; torso along hips and three spine bones) are clean at elbow, knee and wrist but the upper arm tube pulls away from the torso when the arm goes overhead (a visible gap at the shoulder), and the torso tube shows a hard step at the waist in the roll. `ARMATURE_AUTO` (Blender's automatic weights) keeps the shoulder joined and bends the roll smoothly but pinches the forearm into the torso when the arm crosses the body and gives stray weights at the hands. Decision for task 2: rigid weights as the base (predictable, the check "every bone has weights" is easy) with a wider shoulder blend (0.12 m) and the deltoid ring overlapping the torso by a hand's width, then smooth the weights one pass over each joint ring by script; keep `--skin=auto` as a fallback to compare.
- What the spike left for task 2: the tube builder (`tube`, `chain_weights`) is the seed of the parameter set; the head is a bald faceted egg with a nose wedge (faces, hair and beards are not started); feet are boxes along the foot bone (heel does not reach behind the ankle); hands have no fingers or thumb (the finger bones have no weights: the `--check` mode must either weight them to the hand or accept them); vertex colors are baked face colors, not role indices; the scratch scene (a `SceneTree` script that plays a clip at six steps and saves a contact sheet) is worth rebuilding as `--gallery=bodies`. Body height is 1.76 m and the shoulders are narrow against the old mannequin: tune with the height and build parameters.

## Out of scope

New animations (UAL stays). Faces that move. Beasts and animals (M67 and the realm milestones build theirs the same way, as rigid or simply rigged Blender-scripted models).

## Pitfalls

- The clips are retargeted by bone name and rest pose. A body whose rest pose differs from the UAL mannequin's bends wrong in every clip: import the armature, never rebuild it.
- `_pin_root` strips root motion; a new body with a different root or hip bone brings the snap-back bug back.
- Hit stop, burn-away (`CharacterModel.dissolve`, `shaders/burn_away.gdshader`) and freezing act on the model's materials: a dying model uses `MeshKit.burn_material()` (`shaders/flat_burn.gdshader`, one per model; M36 task 3 split it from the plain flat shader because the discard costs GPU time).
- New `MeshInstance3D`s under a skeleton need `skeleton = ".."`.
- Blender versions change the exporter: pin the version in the script and in `docs/RESOURCES.md`.
- This milestone is the block's risk. The spike exists so the risk is paid first and cheaply.

## Left by M39

Armor generators exist (`helm`, `cuirass`, `pauldrons`, `greaves`, `cape`) with `GearKit.covers(look, params)` naming the covered bones (`Head`, `UpperChest`, `Spine`, `LeftUpperArm`, `RightUpperArm`, `<side>LowerLeg`); nothing hides body parts yet and no player model shows worn armor: only `SimPlayer.armor` (a sum) is synced, so showing a helm or cuirass on every peer needs the worn item indices sent (a protocol bump) or derived. Greaves are built for one leg (origin at the knee, shin along -Y): check against the UAL rest pose when bodies land.
