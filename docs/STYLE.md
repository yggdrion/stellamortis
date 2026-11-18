# Style sheet

The one rule set for every model in the game (decided 2026-11-17, `docs/PLAN.md` §3.2). Read it before any visual task. A model that breaks a rule here is not done, however good it looks alone: the point is that everything looks made by one hand.

The numbers below are starting values. M36 puts them into `game/data/style/budgets.tres` and the palette resources and tuned them with the stress scene (measured on an RTX 4080; the GTX 1050 Ti is for the user to run, `docs/PLAYTEST.md`); when a number changes there, change it here in the same commit. Tests (`tests/meshgen_test.gd`) fail when a generator breaks a budget, uses a color outside its palette or is not deterministic.

## 1. The look in one paragraph

Flat-shaded, faceted, mid poly. Every face has one color and one normal. No textures, no normal maps, no smooth shading. Shapes are a little irregular and worn: nothing is perfectly straight, symmetric or new. Colors are muted and dark, taken from one palette per realm. Detail comes from silhouette and facets, never from surface patterns. Dark medieval, northern, adult proportions, not cute.

## 2. Shading

- One material for everything: `shaders/flat.gdshader` (`MeshKit.material()`). A model that burns away on death uses its copy `shaders/flat_burn.gdshader` (`MeshKit.burn_material()`, one per model): the discard costs 5 to 9 % GPU time, so no other model carries it. No `StandardMaterial3D` on generated models, no other shader.
- Flat normals through unshared vertices (`MeshKit` does this; never call a smooth normal generator).
- Color is vertex color only. Roughness is one value per palette role, carried in the vertex color's alpha; no metal look except role `iron` and `steel`.
- Glow (emission) only for meaning: embers, torch flame, portals, telegraphs (§3.2). Never as decoration.
- No transparency except flame, mist and water. Leaves are solid faces, not alpha cards.

## 3. Palette

- Colors come only from the realm's `Palette` (`game/data/palettes/<realm>.tres`), asked for by role. A generator never contains a color literal.
- Roles: `bark`, `bark_pale` (birch), `leaf`, `leaf_dry`, `needle`, `grass`, `heather`, `moss`, `earth`, `stone`, `stone_dark`, `wood` (worked timber), `thatch`, `iron`, `steel`, `leather`, `cloth`, `cloth_dark`, `skin_a` to `skin_d`, `hair_a` to `hair_d`, `bone`, `rot` (the dead), and the meaning colors `ember`, `gate`, `gold`. A new role is added to every palette and to this list in the same commit.
- Variation, applied by `MeshKit`, not by hand: per instance value ±6 % and hue ±3°; per face value ±4 %; darkening toward the ground or into creases up to 25 % (the only ambient occlusion we draw).
- Every role except the meaning colors stays under 45 % saturation and under 60 % value. The meaning colors are the only saturated things on screen.

## 4. Facets

Facets must read at the distance a thing is usually seen from, and be of similar apparent size across kinds. Target edge lengths:

| Size class | Examples | Edge length |
|---|---|---|
| Hand-held | weapons, tools, helm details | 3 to 6 cm |
| Worn and body | armor, bodies, heads | 4 to 10 cm |
| Prop | torch, crate, chest, anvil | 8 to 20 cm |
| Trunk | tree trunks, posts, beams | 20 to 40 cm |
| Crown and bush | leaf clumps, needle layers | 40 to 90 cm |
| Rock | pebbles to boulders | a sixth to a quarter of the rock's size |
| Outcrop and built stone | outcrops, standing stones, walls | 0.8 to 1.6 m |

Smaller facets than the class allows are wasted triangles; larger ones look like a placeholder.

## 5. Triangle budgets

Per model, three levels of detail. Full within 40 m, half to 120 m, far beyond (to the preset's scatter radius). "none" means the kind is not drawn at that distance.

| Kind | Full | Half | Far |
|---|---|---|---|
| Grass tuft | 12 | 6 | none |
| Fern, heather, bush | 160 | 48 | none |
| Pebble, small rock (under 0.5 m) | 40 | 20 | none |
| Rock (0.5 to 2 m) | 160 | 80 | 24 |
| Boulder (2 to 5 m) | 320 | 140 | 40 |
| Outcrop (5 to 12 m) | 700 | 300 | 80 |
| Standing stone, mound | 300 | 120 | 40 |
| Log, stump | 200 | 80 | none |
| Tree, young (3 to 6 m) | 500 | 200 | 40 |
| Tree, grown (8 to 14 m) | 1100 | 400 | 60 |
| Tree, old (15 to 25 m) | 1800 | 650 | 90 |
| Prop, small | 300 | 120 | none |
| Prop, large (gate, chest, anvil, station) | 800 | 300 | 80 |
| Building piece | 400 | 160 | 50 |
| Weapon, tool | 250 | 100 | none |
| Shield, helm, armor piece | 400 | 160 | none |
| Body without gear | 3000 | 1200 | 400 |
| Head with hair and beard | 900 | 350 | 100 |
| A whole dressed character | 6000 | 2500 | 800 |

The far level keeps the silhouette and the main color masses and nothing else.

Measured cost (M36 task 3, `--gallery-stress`, `docs/PLAN.md` §8): drawing costs a fixed 0.25 ms plus about 0.35 ms GPU per million triangles in view on an RTX 4080, per frame, shadows on; the table above held, nothing was changed. Rule for scatter: triangles in view per frame stay under 1.5 million on Low and 2.5 million on Ultra (counted by the M37 view, `docs/milestones/M37-generated-terrain-scatter.md`); the instance counts per level there keep it.

## 6. Shape rules

- **Silhouette first.** A kind must be recognizable as a black shape. Build the outline, then spend what is left of the budget on facets.
- **No perfect symmetry.** Trunks lean 0 to 6°, stones 0 to 10°. Cross sections are irregular (radius ±8 to 15 % per corner). Mirrored things (helms, bodies) are exempt, but worn edges and dents are not mirrored.
- **Taper.** Trunks narrow to 35 to 55 % of their base radius below the crown; old trees flare at the root (1.3 to 1.6 times the trunk radius) with 3 to 5 root ridges. Standing stones narrow to 60 to 80 %.
- **Hard edges are bevelled** on anything worked (timber, cut stone, metal): one bevel face, 6 to 12 % of the smaller side. Natural rock has chipped corners instead: cut 2 to 5 corners off by a plane.
- **Minimum thickness** 2 cm for hand-held things, 6 cm for props, 15 cm for anything on a tree. Thinner parts flicker at distance.
- **Trees** have a trunk with 10 to 12 sides, visible branch stubs or main limbs from "grown" up, and a crown of several separate masses (needle layers for conifers, 5 to 12 leaf clumps for broadleaf), each displaced so no two are the same. A crown is never one cone or one ball.
- **Rocks** are a subdivided icosphere displaced by low-frequency noise, flattened (height 50 to 80 % of width), sunk 10 to 25 % into the ground, with chipped corners.
- **Grass and ground cover** are a few bent blades or fronds, wider at the base, colored lighter toward the tip.
- **Nothing floats and nothing stands exactly upright on a slope:** trees follow gravity (`up`), rocks and props follow the ground normal.

## 7. Scale

Reference sizes, so kinds fit each other: a player is 1.8 m; a door opening 2.2 m by 1.1 m; a wall piece 3 m high; a young tree 3 to 6 m, grown 8 to 14 m, old 15 to 25 m with a trunk 0.8 to 1.6 m across; a standing stone 3 to 6 m; a sword blade 0.9 m, a greatsword 1.5 m; a torch post 1.4 m.

## 8. Characters

- Bodies are made by `tools/make_bodies.py` (Blender, M40), skinned to the UAL skeleton; the UAL clips play on them unchanged. Bone names and the rest pose are the UAL1 mannequin's.
- Adult proportions: 7.5 heads tall, hands and feet at real size, no enlarged heads or eyes.
- Faces: brow, nose, cheek and jaw planes; eyes are dark insets, no eye texture; no mouth detail beyond one crease. Hair and beards are a few solid masses.
- Joints (shoulder, elbow, wrist, hip, knee, ankle, neck) have a ring of edges on each side so they bend without collapsing.
- Gear (M39) is rigid and sits on a bone (`RightHand`, `Head`, `Spine`, ...); it never deforms. Armor covers the body part below it, which is then hidden so nothing pokes through.

## 9. What a generator must be

- A pure function of (kind, variant seed, palette) that returns one mesh per level of detail. Same inputs, same vertices, on every machine. No randomness outside the seeded `RandomNumberGenerator` it is given, no reading of time, scene or settings.
- Built only with `MeshKit` (`game/scripts/client/meshgen/`), so shading, color variation and budgets are applied in one place.
- For solid kinds: inside the kind's `ScatterShape` (`game/data/scatter/`) at the trunk or body. The sim's collision never reads a mesh; the mesh must fit the collision.
- Registered in `Generators`, so it appears in the gallery (`--gallery`) and in the tests.
- Lives in `client/`. Headless processes never build a mesh.

## 10. Done means

- [ ] A gallery screenshot (`--gallery=<kind>`) showing every variant at all three levels of detail, beside a player for scale and beside two existing kinds.
- [ ] A screenshot in the world, at dusk light, at 5 m and at 60 m.
- [ ] `tests/meshgen_test.gd` green: budget, determinism, palette, fits its `ScatterShape`.
- [ ] No texture, no color literal, no new material.
- [ ] The kind's row is in the table in §5 if it is a new kind.

## 11. Not allowed

Textures and UV-mapped detail; smooth shading; alpha-card foliage; third-party models (the UAL rig and clips are the one exception, `docs/RESOURCES.md`); models from AI mesh generators; a unique mesh per placed instance (variants are few and shared through `MultiMesh`); saturated color without meaning; anything that reads as sci-fi.
