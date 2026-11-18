"""Builds the game's skinned character bodies with Blender (M40).

    python tools/make_bodies.py [ID ...] [--check] [--skin=rigid|auto] [--out-dir=PATH]

Runs `blender --background --python` on itself. For each body in SPECS it imports the UAL1
armature from game/assets/quaternius/ual/UAL1.glb (never rebuilt: the clips retarget by bone name
and rest pose), builds the body from faceted tubes (one material slot per part, so armor can hide
what it covers), skins it rigidly with a blended ring at every joint, writes vertex colors as
role indices (see ROLES; `CharacterModel` resolves them to palette colors at load) and exports
glTF without the clips to game/assets/bodies/<id>.glb. The outputs are committed; this script is
the source. With --check nothing is written: the bodies are built and the rules of check() must
hold (every skinned bone has weights, at most 4 influences, budgets of docs/STYLE.md section 5).

Levels of detail: Godot generates them on import (`meshes/generate_lods` in the .import files),
the bodies are one mesh each.
"""

import json
import math
import os
import subprocess
import sys

BLENDER_VERSION = "5.3"  # pinned: exporter options change between versions
BLENDER_EXE = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.3\blender.exe")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UAL1 = os.path.join(ROOT, "game", "assets", "quaternius", "ual", "UAL1.glb")
OUT_DIR = os.path.join(ROOT, "game", "assets", "bodies")

# Vertex color role indices (red channel = index / 255), resolved to palette colors by
# CharacterModel: skin -> skin_a..d, hair -> hair_a..d (the player's choice), the rest fixed.
ROLES = ["skin", "hair", "tunic", "sleeve", "trousers", "boot", "belt", "eye", "bone", "rot"]

PARTS = [
    "head", "hair", "beard", "torso", "upper_arm", "lower_arm", "hand",
    "upper_leg", "lower_leg", "foot",
]  # fmt: skip

# Bones that carry no geometry of their own: the root, fingers and toes follow the hand and foot
# surfaces (a fist and a boot), so a clip curling a finger moves nothing.
UNWEIGHTED = ("root", "f_", "thumb", "toe")

# docs/STYLE.md section 5 (triangles): body without gear, head with hair and beard.
BODY_BUDGET = 3000
HEAD_BUDGET = 900

# Build: width, depth, limb thickness factors.
BUILDS = {"slim": (0.88, 0.90, 0.88), "average": (1.0, 1.0, 1.0), "heavy": (1.18, 1.20, 1.20)}

# The bodies. sex: male|female; build: BUILDS; head: egg|square|long; hair: bald|buzzed|short|
# long|bun|braid; beard: none|short|full|long; shoulder, hip: width factors; dead: None|sunken|
# bone|skull (rot flesh, the variants of the dead); outfit: the colors of the clothes.
SPECS = {
    "male_a": dict(sex="male", build="average", head="egg", hair="short", beard="short"),
    "male_b": dict(sex="male", build="heavy", head="square", hair="long", beard="full",
                   shoulder=1.05),
    "female_a": dict(sex="female", build="slim", head="egg", hair="long", beard="none"),
    "female_b": dict(sex="female", build="average", head="long", hair="bun", beard="none",
                     hip=1.06),
    "dead_male": dict(sex="male", build="slim", head="long", hair="long", beard="none",
                      dead="sunken"),
    "dead_female": dict(sex="female", build="slim", head="egg", hair="bun", beard="none",
                        dead="bone"),
    "dead_skull": dict(sex="male", build="average", head="square", hair="bald", beard="none",
                       dead="skull"),
    "berserker": dict(sex="male", build="heavy", head="square", hair="bald", beard="full",
                      shoulder=1.08, outfit="bare"),
    "warden": dict(sex="male", build="heavy", head="square", hair="bald", beard="none",
                   shoulder=1.1, outfit="plate"),
}  # fmt: skip


def main_blender(argv: list[str]) -> None:
    import bpy

    opts = dict(a.lstrip("-").split("=", 1) if "=" in a else (a.lstrip("-"), "1") for a in argv)
    ids = [a for a in argv if not a.startswith("-")] or list(SPECS)
    method = opts.get("skin", "rigid")
    out_dir = opts.get("out-dir", OUT_DIR)
    check_only = "check" in opts
    problems: list[str] = []
    report = {}
    for body_id in ids:
        spec = SPECS[body_id]
        stats = build(bpy, body_id, spec, method, None if check_only else out_dir)
        report[body_id] = stats
        problems += check(body_id, stats)
    print("BODIES", json.dumps(report))
    for problem in problems:
        print("PROBLEM", problem)
    if problems:
        sys.exit(1)


def check(body_id: str, stats: dict) -> list[str]:
    found = []
    for bone in stats["unweighted_bones"]:
        found.append(f"{body_id}: bone {bone} has no weights")
    if stats["max_influences"] > 4:
        found.append(f"{body_id}: a vertex has {stats['max_influences']} influences")
    if stats["bad_weight_sums"]:
        found.append(f"{body_id}: {stats['bad_weight_sums']} vertices whose weights do not sum to 1")
    if stats["triangles"] - stats["head_triangles"] > BODY_BUDGET:
        found.append(f"{body_id}: {stats['triangles']} triangles over the body budget")
    if stats["head_triangles"] > HEAD_BUDGET:
        found.append(f"{body_id}: head with hair and beard {stats['head_triangles']} triangles")
    for part in PARTS:
        if part not in ("hair", "beard") and part not in stats["parts"]:
            found.append(f"{body_id}: part {part} is missing")
    return found


def build(bpy, body_id: str, spec: dict, method: str, out_dir: str | None) -> dict:
    from mathutils import Vector

    sex = spec["sex"]
    female = sex == "female"
    width, depth, limb = BUILDS[spec["build"]]
    shoulder = spec.get("shoulder", 1.0) * (0.88 if female else 1.0)
    hips = spec.get("hip", 1.0) * (1.12 if female else 1.0)
    waist = 0.92 if female else 1.0
    dead = spec.get("dead")
    outfit = spec.get("outfit", "tunic")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=UAL1)
    rig = bpy.data.objects["Rig"]
    for obj in list(bpy.data.objects):
        if obj.type == "MESH":
            bpy.data.objects.remove(obj)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    if rig.animation_data:
        rig.animation_data_clear()
    bones = {b.name: b for b in rig.data.bones}

    def head(name: str) -> Vector:
        return Vector(bones[name].head_local)

    def tail(name: str) -> Vector:
        return Vector(bones[name].tail_local)

    def role(name: str) -> int:
        if dead and name == "skin":
            name = "rot"
        return ROLES.index(name)

    # ---- geometry -------------------------------------------------------------------------
    verts: list[Vector] = []
    faces: list[tuple[int, ...]] = []
    face_part: list[int] = []
    face_role: list[int] = []
    vert_weights: list[dict[str, float]] = []
    SIDES = 8

    def smooth(x: float) -> float:
        x = max(0.0, min(1.0, x))
        return x * x * (3 - 2 * x)

    def chain_weights(points, names, blend, p):
        """Rigid weights along a bone chain with a blended ring at each joint (blend[j-1] is the
        half width at joint j). points has len(names) + 1 joints."""
        best = (1e9, 0.0)
        arc = 0.0
        arcs = [0.0]
        for i in range(len(names)):
            a, b = points[i], points[i + 1]
            ab = b - a
            ln = ab.length
            t = max(0.0, min(1.0, (p - a).dot(ab) / (ln * ln)))
            d = (p - (a + ab * t)).length
            if d < best[0]:
                best = (d, arc + t * ln)
            arc += ln
            arcs.append(arc)
        s = best[1]
        seg = 0
        for i in range(len(names)):
            if s >= arcs[i]:
                seg = i
        weights = {names[seg]: 1.0}
        for j in range(1, len(names)):
            w = blend[j - 1]
            if abs(s - arcs[j]) < w:
                t = smooth((s - (arcs[j] - w)) / (2 * w))
                weights = {names[j - 1]: 1 - t, names[j]: t}
        return weights

    def tube(part, path, rings, up, chain, caps=True, bone_if=None):
        """A faceted tube along a polyline. rings: (arc fraction 0..1, half width along `up`
        crossed with the axis, half depth, role of the band above it). Ends are capped."""
        total = sum((path[i + 1] - path[i]).length for i in range(len(path) - 1))
        ring_ids = []
        centers = []
        for frac, a, b, _role in rings:
            target = frac * total
            acc = 0.0
            center = path[-1]
            axis = (path[-1] - path[-2]).normalized()
            for i in range(len(path) - 1):
                ln = (path[i + 1] - path[i]).length
                if target <= acc + ln or i == len(path) - 2:
                    t = (target - acc) / ln
                    center = path[i] + (path[i + 1] - path[i]) * t
                    axis = (path[i + 1] - path[i]).normalized()
                    break
                acc += ln
            u = (up - axis * up.dot(axis)).normalized()
            v = axis.cross(u).normalized()
            ids = []
            for k in range(SIDES):
                ang = 2 * math.pi * (k + 0.5) / SIDES
                point = center + u * (math.cos(ang) * a) + v * (math.sin(ang) * b)
                verts.append(point)
                vert_weights.append(chain(point))
                ids.append(len(verts) - 1)
            ring_ids.append(ids)
            centers.append(center)
        part_index = PARTS.index(part)
        for r in range(len(rings) - 1):
            for k in range(SIDES):
                k2 = (k + 1) % SIDES
                faces.append((ring_ids[r][k], ring_ids[r][k2], ring_ids[r + 1][k2], ring_ids[r + 1][k]))
                face_part.append(part_index)
                face_role.append(role(rings[r][3]))
        if not caps:
            return
        for r, flip in ((0, True), (len(rings) - 1, False)):
            verts.append(centers[r])
            vert_weights.append(chain(centers[r]))
            c = len(verts) - 1
            for k in range(SIDES):
                k2 = (k + 1) % SIDES
                a_id, b_id = ring_ids[r][k], ring_ids[r][k2]
                faces.append((c, b_id, a_id) if flip else (c, a_id, b_id))
                face_part.append(part_index)
                face_role.append(role(rings[r][3]))

    X = Vector((1, 0, 0))
    Y = Vector((0, 1, 0))
    Z = Vector((0, 0, 1))

    cloth = {"tunic": ("tunic", "sleeve", "trousers", "boot", "belt"),
             "bare": ("skin", "skin", "trousers", "skin", "belt"),
             "plate": ("belt", "belt", "belt", "belt", "belt")}[outfit]  # fmt: skip
    top, sleeve, legs, boots, belt = cloth

    # ---- torso: pelvis to shoulders, weighted along hips and the three spine bones ----------
    spine = ["DEF-hips", "DEF-spine.001", "DEF-spine.002", "DEF-spine.003"]
    spine_pts = [head("DEF-hips"), head("DEF-spine.001"), head("DEF-spine.002"),
                 head("DEF-spine.003"), tail("DEF-spine.003")]  # fmt: skip

    def spine_chain(p):
        return chain_weights(spine_pts, spine, [0.05, 0.06, 0.06], p)

    bust = 0.018 if female else 0.0
    rib = "bone" if dead == "bone" else top
    tube(
        "torso",
        [Vector((0, 0.04, 0.86)), Vector((0, 0.0, 1.20)), Vector((0, 0.0, 1.50))],
        [
            (0.00, 0.14 * hips * width, 0.10 * depth, legs),
            (0.10, 0.175 * hips * width, 0.115 * depth, belt),
            (0.21, 0.155 * waist * width, 0.105 * depth, top),
            (0.45, 0.145 * waist * width, 0.10 * depth, rib),
            (0.70, 0.19 * shoulder * width, 0.125 * depth + bust, rib),
            (0.90, 0.20 * shoulder * width, 0.13 * depth, top),
            (1.00, 0.12 * shoulder * width, 0.09 * depth, top),
        ],
        X,
        spine_chain,
    )

    # ---- head and neck ---------------------------------------------------------------------
    head_names = ["DEF-spine.003", "DEF-neck", "DEF-head"]
    head_pts = [head("DEF-neck") - Vector((0, 0, 0.1)), head("DEF-neck"), head("DEF-head"),
                head("DEF-head") + Vector((0, 0, 0.15))]  # fmt: skip

    def head_chain(p):
        return chain_weights(head_pts, head_names, [0.03, 0.03], p)

    hs = 0.95 if female else 1.0
    cheek = 0.85 if dead == "sunken" else 1.0
    # jaw widens for square, skull stretches for long
    jaw, tall = {"egg": (1.0, 1.0), "square": (1.18, 0.97), "long": (0.94, 1.1)}[spec["head"]]
    top_z = 1.47 + 0.29 * tall
    jaw_role = "bone" if dead == "skull" else "skin"
    skull_rings = [
        (0.00, 0.06 * hs, 0.06 * hs, "skin"),
        (0.22, 0.055 * hs, 0.058 * hs, jaw_role),
        (0.32, 0.07 * hs * jaw * cheek, 0.085 * hs, jaw_role),
        (0.50, 0.08 * hs * cheek, 0.10 * hs, "skin"),
        (0.75, 0.085 * hs, 0.105 * hs, "skin"),
        (0.92, 0.07 * hs, 0.085 * hs, "skin"),
        (1.00, 0.03 * hs, 0.04 * hs, "skin"),
    ]
    head_path = [Vector((0, 0.0, 1.47)), Vector((0, -0.01, top_z))]
    tube("head", head_path, skull_rings, X, head_chain)
    face_z = 1.47 + 0.20 * tall
    on_head = lambda p: {"DEF-head": 1.0}  # noqa: E731
    # nose, brow ridge, eyes (dark insets), ears: small solids on the head bone
    tube("head", [Vector((0, -0.075, face_z)), Vector((0, -0.125, face_z - 0.025))],
         [(0, 0.012, 0.025, "skin"), (1, 0.006, 0.01, "skin")], X, on_head)  # fmt: skip
    tube("head", [Vector((-0.05, -0.098, face_z + 0.045)), Vector((0.05, -0.098, face_z + 0.045))],
         [(0, 0.012, 0.016, "skin"), (1, 0.012, 0.016, "skin")], Z, on_head)  # fmt: skip
    eye = 0.017 if dead == "sunken" else 0.011
    for sx in (-1, 1):
        tube("head", [Vector((sx * 0.032, -0.100, face_z + 0.018)),
                      Vector((sx * 0.032, -0.108, face_z + 0.018))],
             [(0, eye, eye, "eye"), (1, eye * 0.8, eye * 0.8, "eye")], X, on_head)  # fmt: skip
        tube("head", [Vector((sx * 0.083, 0.0, face_z + 0.0)), Vector((sx * 0.097, 0.0, face_z + 0.0))],
             [(0, 0.022, 0.014, "skin"), (1, 0.02, 0.012, "skin")], Z, on_head)  # fmt: skip

    # ---- hair and beard: solid masses on the head bone (the nape and beard follow the neck) --
    hair = spec["hair"]
    # The cap sits back and high: a ring centered on the head would wrap the face (the old cap
    # started at the eyes and reached past the forehead), so the front stays skin.
    cap = [Vector((0, 0.03, top_z - 0.09)), Vector((0, 0.03, top_z + 0.01))]
    if hair in ("buzzed", "short", "long", "bun", "braid"):
        grow = 0.006 if hair == "buzzed" else 0.014
        tube("hair", cap,
             [(0, 0.08 * hs + grow, 0.10 * hs + grow, "hair"),
              (0.45, 0.088 * hs + grow, 0.108 * hs + grow, "hair"),
              (0.85, 0.07 * hs + grow, 0.09 * hs + grow, "hair"),
              (1.00, 0.03 * hs + grow, 0.04 * hs + grow, "hair")], X, head_chain)  # fmt: skip
    if hair in ("long", "braid"):
        n = 0.05 if hair == "braid" else 0.075
        tube("hair", [Vector((0, 0.085, top_z - 0.06)), Vector((0, 0.10, 1.42)),
                      Vector((0, 0.09, 1.32 if hair == "long" else 1.20))],
             [(0, n, 0.025, "hair"), (0.5, n * 1.1, 0.032, "hair"),
              (1.0, n * 0.7, 0.025, "hair")], X, head_chain)  # fmt: skip
    if hair == "bun":
        tube("hair", [Vector((0, 0.08, top_z - 0.04)), Vector((0, 0.13, top_z - 0.04))],
             [(0, 0.04, 0.04, "hair"), (0.5, 0.05, 0.05, "hair"), (1, 0.03, 0.03, "hair")],
             X, head_chain)  # fmt: skip
    beard = spec["beard"]
    if beard != "none":
        length = {"short": 0.07, "full": 0.12, "long": 0.22}[beard]
        tube("beard", [Vector((0, -0.06, face_z - 0.075)),
                       Vector((0, -0.075, face_z - 0.075 - length))],
             [(0, 0.055, 0.045, "hair"), (0.4, 0.062, 0.05, "hair"), (1, 0.035, 0.035, "hair")],
             X, head_chain)  # fmt: skip

    # ---- arms and legs, per side -----------------------------------------------------------
    for side, sign in (("L", 1.0), ("R", -1.0)):
        s = side
        arm_names = [f"DEF-shoulder.{s}", f"DEF-upper_arm.{s}", f"DEF-forearm.{s}", f"DEF-hand.{s}"]
        sh = Vector((sign * 0.07, -0.01, 1.455))
        ua, fa, hd = head(f"DEF-upper_arm.{s}"), head(f"DEF-forearm.{s}"), head(f"DEF-hand.{s}")
        hd_end = hd + Vector((sign * 0.10, 0, 0))
        arm_pts = [sh, ua, fa, hd, hd_end]

        def arm_chain(p, arm_pts=arm_pts, arm_names=arm_names):
            return chain_weights(arm_pts, arm_names, [0.12, 0.06, 0.03], p)

        k = limb * (0.9 if female else 1.0)
        bare = "bone" if dead == "bone" else "skin"
        # the deltoid ring overlaps the torso so the shoulder stays closed overhead
        start = sh + (ua - sh) * 0.35
        tube("upper_arm", [start, fa],
             [(0.00, 0.085 * k, 0.085 * k, sleeve), (0.14, 0.078 * k, 0.078 * k, sleeve),
              (0.45, 0.058 * k, 0.058 * k, sleeve), (0.90, 0.048 * k, 0.048 * k, sleeve),
              (1.00, 0.045 * k, 0.045 * k, sleeve)], Y, arm_chain)  # fmt: skip
        tube("lower_arm", [fa, hd],
             [(0.00, 0.045 * k, 0.045 * k, bare), (0.12, 0.047 * k, 0.047 * k, bare),
              (0.50, 0.040 * k, 0.040 * k, bare), (0.92, 0.030 * k, 0.026 * k, bare),
              (1.00, 0.030 * k, 0.026 * k, bare)], Y, arm_chain)  # fmt: skip
        tube("hand", [hd, hd_end + Vector((sign * 0.06, 0, 0))],
             [(0.00, 0.032, 0.026, "skin"), (0.30, 0.046, 0.022, "skin"),
              (0.75, 0.044, 0.020, "skin"), (1.00, 0.030, 0.014, "skin")], Y, arm_chain)  # fmt: skip

        leg_names = [f"DEF-thigh.{s}", f"DEF-shin.{s}", f"DEF-foot.{s}"]
        th, sn, ft = head(f"DEF-thigh.{s}"), head(f"DEF-shin.{s}"), head(f"DEF-foot.{s}")
        toe = tail(f"DEF-foot.{s}")
        leg_pts = [th, sn, ft, toe]

        def leg_chain(p, leg_pts=leg_pts, leg_names=leg_names):
            return chain_weights(leg_pts, leg_names, [0.07, 0.05], p)

        shin = "bone" if dead == "bone" else boots
        tube("upper_leg", [th + Vector((0, 0.0, 0.05)), sn],
             [(0.00, 0.095 * hips * limb, 0.10 * limb, legs), (0.12, 0.095 * hips * limb, 0.10 * limb, legs),
              (0.50, 0.075 * limb, 0.08 * limb, legs), (0.92, 0.058 * limb, 0.058 * limb, legs),
              (1.00, 0.056 * limb, 0.056 * limb, legs)], X, leg_chain)  # fmt: skip
        tube("lower_leg", [sn, ft],
             [(0.00, 0.056 * limb, 0.056 * limb, legs), (0.15, 0.058 * limb, 0.062 * limb, legs),
              (0.55, 0.045 * limb, 0.050 * limb, shin), (0.92, 0.040 * limb, 0.044 * limb, shin),
              (1.00, 0.040 * limb, 0.044 * limb, shin)], X, leg_chain)  # fmt: skip
        tube("foot", [ft, toe, toe + Vector((0, -0.08, 0))],
             [(0.00, 0.040, 0.050, boots), (0.30, 0.048, 0.050, boots),
              (0.62, 0.050, 0.030, boots), (1.00, 0.030, 0.018, boots)], X, leg_chain)  # fmt: skip

    # ---- mesh object, flat faces, role colors, weights --------------------------------------
    mesh = bpy.data.meshes.new(body_id)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    obj = bpy.data.objects.new(body_id, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for name in PARTS:
        mesh.materials.append(bpy.data.materials.new(name))
    for poly, part in zip(mesh.polygons, face_part):
        poly.material_index = part
        poly.use_smooth = False
    # float colors: written to the glTF as they are (role index / 255 in red, no color management)
    layer = mesh.color_attributes.new("Color", "FLOAT_COLOR", "CORNER")
    for poly, index in zip(mesh.polygons, face_role):
        for loop in poly.loop_indices:
            layer.data[loop].color = (index / 255.0, 0.0, 0.0, 1.0)
    mesh.color_attributes.active_color = layer
    mesh.update()

    obj.parent = rig
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    if method == "rigid":
        groups = {}
        for index, weights in enumerate(vert_weights):
            for bone, weight in weights.items():
                if weight <= 0.001:
                    continue
                if bone not in groups:
                    groups[bone] = obj.vertex_groups.new(name=bone)
                groups[bone].add([index], weight, "REPLACE")
    else:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    # ---- numbers for check() ----------------------------------------------------------------
    used = {obj.vertex_groups[g.group].name for v in mesh.vertices for g in v.groups if g.weight > 0}
    unweighted = [
        b.name
        for b in rig.data.bones
        if b.name not in used and not any(b.name.removeprefix("DEF-").startswith(p) for p in UNWEIGHTED)
    ]
    most = 0
    bad = 0
    for v in mesh.vertices:
        ws = [g.weight for g in v.groups if g.weight > 0.001]
        most = max(most, len(ws))
        if ws and abs(sum(ws) - 1.0) > 0.02:
            bad += 1
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    head_tris = sum(
        len(p.vertices) - 2 for p in mesh.polygons if PARTS[p.material_index] in ("head", "hair", "beard")
    )
    stats = {
        "vertices": len(mesh.vertices),
        "triangles": tris,
        "head_triangles": head_tris,
        "max_influences": most,
        "bad_weight_sums": bad,
        "unweighted_bones": unweighted,
        "parts": sorted({PARTS[p.material_index] for p in mesh.polygons}),
    }

    if out_dir is not None:
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, f"{body_id}.glb")
        bpy.ops.object.select_all(action="DESELECT")
        bpy.ops.export_scene.gltf(
            filepath=path,
            export_format="GLB",
            export_animations=False,
            export_skins=True,
            export_apply=False,
            export_yup=True,
            export_vertex_color="ACTIVE",
            export_active_vertex_color_when_no_material=True,
            export_materials="EXPORT",
        )
        write_import(path)
        print("WROTE", path, tris, "triangles")
    return stats


def write_import(path: str) -> None:
    """The .import file Godot needs to retarget the skeleton with the UAL1 bone map (the same
    params as UAL1.glb.import); Godot fills in the uid and the imported path itself."""
    if os.path.exists(path + ".import"):
        return
    template = open(UAL1 + ".import", encoding="utf-8").read()
    lines = [line for line in template.splitlines() if not line.startswith("uid=")]
    text = "\n".join(lines) + "\n"
    text = text.replace("res://assets/quaternius/ual/UAL1.glb", "res://assets/bodies/" + os.path.basename(path))
    name = os.path.basename(path)
    text = text.replace("UAL1.glb-2cc87a8b9c663f2a132336d3216f5d44", name + "-x")
    text = text.replace("UAL1.glb", name)
    with open(path + ".import", "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main() -> None:
    cmd = [BLENDER_EXE, "--background", "--python", os.path.abspath(__file__), "--", *sys.argv[1:]]
    sys.exit(subprocess.call(cmd))


if __name__ == "__main__":
    try:
        import bpy  # noqa: F401
    except ImportError:
        main()
    else:
        main_blender(sys.argv[sys.argv.index("--") + 1 :])
