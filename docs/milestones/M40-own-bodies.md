# M40 Own bodies

Status: Planned.

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

File level detail for tasks 2 and 3 is added after the spike.

## Out of scope

New animations (UAL stays). Faces that move. Beasts and animals (M67 and the realm milestones build theirs the same way, as rigid or simply rigged Blender-scripted models). Character customization in the menu.

## Pitfalls

- The clips are retargeted by bone name and rest pose. A body whose rest pose differs from the UAL mannequin's bends wrong in every clip: import the armature, never rebuild it.
- `_pin_root` strips root motion; a new body with a different root or hip bone brings the snap-back bug back.
- Hit stop, burn-away (`CharacterModel.dissolve`, `shaders/burn_away.gdshader`) and freezing act on the model's materials: a dying model uses `MeshKit.burn_material()` (`shaders/flat_burn.gdshader`, one per model; M36 task 3 split it from the plain flat shader because the discard costs GPU time).
- New `MeshInstance3D`s under a skeleton need `skeleton = ".."`.
- Blender versions change the exporter: pin the version in the script and in `docs/RESOURCES.md`.
- This milestone is the block's risk. The spike exists so the risk is paid first and cheaply.
