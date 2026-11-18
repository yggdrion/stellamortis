"""Builds the game's skinned character bodies with Blender (M40).

    python tools/make_bodies.py [--skin=rigid|auto] [--out=PATH]

Runs `blender --background --python` on itself. The UAL1 armature is imported from
game/assets/quaternius/ual/UAL1.glb (never rebuilt: the clips retarget by bone name and rest
pose), the body is built from faceted tubes (one per body part, one material slot per part) and
skinned to it, vertex colors are written, and the result is exported as glTF without the
armature's clips. The outputs in game/assets/bodies/ are committed; this script is the source.

Spike (M40 task 1): one average male body, two skinning methods to compare.
"""

import math
import os
import subprocess
import sys

BLENDER_VERSION = "5.3"  # pinned: exporter options change between versions
BLENDER_EXE = r"C:\Program Files\Blender Foundation\Blender 5.3\blender.exe"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UAL1 = os.path.join(ROOT, "game", "assets", "quaternius", "ual", "UAL1.glb")
OUT_DIR = os.path.join(ROOT, "game", "assets", "bodies")

# Colors (spike: baked; M40 task 2 writes role indices instead).
SKIN = (0.62, 0.44, 0.34)
TUNIC = (0.20, 0.17, 0.12)
SLEEVE = (0.22, 0.19, 0.14)
TROUSERS = (0.16, 0.14, 0.12)
BOOT = (0.09, 0.07, 0.06)
BELT = (0.07, 0.05, 0.04)

PARTS = ["head", "torso", "upper_arm", "lower_arm", "hand", "upper_leg", "lower_leg", "foot"]


def main_blender(argv: list[str]) -> None:
    import bpy
    from mathutils import Vector

    opts = dict(a.lstrip("-").split("=", 1) for a in argv if "=" in a)
    skin_method = opts.get("skin", "rigid")
    out = opts.get("out", os.path.join(OUT_DIR, f"male_average_{skin_method}.glb"))

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

    # ---- geometry -------------------------------------------------------------------------
    verts: list[Vector] = []
    faces: list[tuple[int, ...]] = []
    face_part: list[int] = []
    face_color: list[tuple[float, float, float]] = []
    vert_weights: list[dict[str, float]] = []
    SIDES = 8

    def smooth(x: float) -> float:
        x = max(0.0, min(1.0, x))
        return x * x * (3 - 2 * x)

    def chain_weights(points: list[Vector], names: list[str], blend: list[float], p: Vector):
        """Weights of p along a bone chain: rigid per bone with a blended ring at each joint.
        points has len(names)+1 joints; blend[j] is the half width at joint j+1."""
        # nearest point on the polyline, as arc length
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
        # a vertex beyond the ends belongs to the end bones
        weights: dict[str, float] = {}
        seg = 0
        for i in range(len(names)):
            if s >= arcs[i]:
                seg = i
        weights[names[seg]] = 1.0
        for j in range(1, len(names)):
            w = blend[j - 1]
            if abs(s - arcs[j]) < w:
                t = smooth((s - (arcs[j] - w)) / (2 * w))
                weights = {names[j - 1]: 1 - t, names[j]: t}
        return weights

    def tube(
        part: str,
        path: list[Vector],
        rings: list[tuple[float, float, float, tuple[float, float, float]]],
        up: Vector,
        chain,
        offset: Vector | None = None,
    ) -> None:
        """A faceted tube along a polyline. rings: (arc fraction 0..1, half width along `up`
        crossed with the axis, half depth, color of the band above it). First and last ring are
        capped. offset moves a ring's center sideways in (u, v) units of its own size."""
        total = sum((path[i + 1] - path[i]).length for i in range(len(path) - 1))
        ring_ids: list[list[int]] = []
        centers = []
        for frac, a, b, _color in rings:
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
            centers.append((center, axis))
        part_index = PARTS.index(part)
        for r in range(len(rings) - 1):
            for k in range(SIDES):
                k2 = (k + 1) % SIDES
                faces.append(
                    (ring_ids[r][k], ring_ids[r][k2], ring_ids[r + 1][k2], ring_ids[r + 1][k])
                )
                face_part.append(part_index)
                face_color.append(rings[r][3])
        for r, flip in ((0, True), (len(rings) - 1, False)):
            center, _axis = centers[r]
            verts.append(center)
            vert_weights.append(chain(center))
            c = len(verts) - 1
            for k in range(SIDES):
                k2 = (k + 1) % SIDES
                a_id, b_id = ring_ids[r][k], ring_ids[r][k2]
                faces.append((c, b_id, a_id) if flip else (c, a_id, b_id))
                face_part.append(part_index)
                face_color.append(rings[r][3])

    X = Vector((1, 0, 0))
    Y = Vector((0, 1, 0))

    # ---- torso: pelvis to shoulders, weighted along hips, spine.001..003 -------------------
    spine = ["DEF-hips", "DEF-spine.001", "DEF-spine.002", "DEF-spine.003"]
    spine_pts = [head("DEF-hips"), head("DEF-spine.001"), head("DEF-spine.002"),
                 head("DEF-spine.003"), tail("DEF-spine.003")]

    def spine_chain(p: Vector):
        return chain_weights(spine_pts, spine, [0.05, 0.06, 0.06], p)

    torso_path = [Vector((0, 0.04, 0.86)), Vector((0, 0.0, 1.20)), Vector((0, 0.0, 1.50))]
    tube(
        "torso",
        torso_path,
        [
            (0.00, 0.14, 0.10, TROUSERS),
            (0.10, 0.175, 0.115, BELT),
            (0.21, 0.155, 0.105, TUNIC),
            (0.45, 0.145, 0.10, TUNIC),
            (0.70, 0.19, 0.125, TUNIC),
            (0.90, 0.20, 0.13, TUNIC),
            (1.00, 0.12, 0.09, TUNIC),
        ],
        X,
        spine_chain,
    )

    # ---- head and neck ---------------------------------------------------------------------
    head_names = ["DEF-spine.003", "DEF-neck", "DEF-head"]
    head_pts = [head("DEF-neck") - Vector((0, 0, 0.1)), head("DEF-neck"), head("DEF-head"),
                head("DEF-head") + Vector((0, 0, 0.15))]

    def head_chain(p: Vector):
        return chain_weights(head_pts, head_names, [0.03, 0.03], p)

    head_path = [Vector((0, 0.0, 1.47)), Vector((0, -0.01, 1.76))]
    tube(
        "head",
        head_path,
        [
            (0.00, 0.06, 0.06, SKIN),
            (0.22, 0.055, 0.058, SKIN),
            (0.32, 0.07, 0.085, SKIN),
            (0.50, 0.08, 0.10, SKIN),
            (0.75, 0.085, 0.105, SKIN),
            (0.92, 0.07, 0.085, SKIN),
            (1.00, 0.03, 0.04, SKIN),
        ],
        X,
        head_chain,
    )
    # nose: a small wedge on the front of the head (-Y), weighted fully to the head bone
    nose_path = [Vector((0, -0.075, 1.665)), Vector((0, -0.125, 1.64))]
    tube("head", nose_path,
         [(0, 0.012, 0.025, SKIN), (1, 0.006, 0.01, SKIN)], X,
         lambda p: {"DEF-head": 1.0})

    # ---- arms and legs, per side -----------------------------------------------------------
    for side, sign in (("L", 1.0), ("R", -1.0)):
        s = side
        arm_names = [f"DEF-shoulder.{s}", f"DEF-upper_arm.{s}", f"DEF-forearm.{s}", f"DEF-hand.{s}"]
        sh = Vector((sign * 0.07, -0.01, 1.455))
        ua, fa, hd = head(f"DEF-upper_arm.{s}"), head(f"DEF-forearm.{s}"), head(f"DEF-hand.{s}")
        hd_end = hd + Vector((sign * 0.10, 0, 0))
        arm_pts = [sh, ua, fa, hd, hd_end]

        def arm_chain(p: Vector, arm_pts=arm_pts, arm_names=arm_names):
            return chain_weights(arm_pts, arm_names, [0.08, 0.06, 0.03], p)

        def along(a: Vector, b: Vector, t: float) -> Vector:
            return a + (b - a) * t

        # upper arm: deltoid ring just inside the shoulder joint, tapering to the elbow
        tube(
            "upper_arm",
            [along(sh, ua, 0.6), fa],
            [
                (0.00, 0.075, 0.075, SLEEVE),
                (0.14, 0.072, 0.075, SLEEVE),
                (0.45, 0.058, 0.058, SLEEVE),
                (0.90, 0.048, 0.048, SLEEVE),
                (1.00, 0.045, 0.045, SLEEVE),
            ],
            Y,
            arm_chain,
        )
        tube(
            "lower_arm",
            [fa, hd],
            [
                (0.00, 0.045, 0.045, SKIN),
                (0.12, 0.047, 0.047, SKIN),
                (0.50, 0.040, 0.040, SKIN),
                (0.92, 0.030, 0.026, SKIN),
                (1.00, 0.030, 0.026, SKIN),
            ],
            Y,
            arm_chain,
        )
        tube(
            "hand",
            [hd, hd_end + Vector((sign * 0.06, 0, 0))],
            [
                (0.00, 0.032, 0.026, SKIN),
                (0.30, 0.046, 0.022, SKIN),
                (0.75, 0.044, 0.020, SKIN),
                (1.00, 0.030, 0.014, SKIN),
            ],
            Y,
            arm_chain,
        )

        leg_names = [f"DEF-thigh.{s}", f"DEF-shin.{s}", f"DEF-foot.{s}"]
        th, sn, ft = head(f"DEF-thigh.{s}"), head(f"DEF-shin.{s}"), head(f"DEF-foot.{s}")
        toe = tail(f"DEF-foot.{s}")
        leg_pts = [th, sn, ft, toe]

        def leg_chain(p: Vector, leg_pts=leg_pts, leg_names=leg_names):
            return chain_weights(leg_pts, leg_names, [0.07, 0.05], p)

        top = th + Vector((0, 0.0, 0.05))
        tube(
            "upper_leg",
            [top, sn],
            [
                (0.00, 0.095, 0.10, TROUSERS),
                (0.12, 0.095, 0.10, TROUSERS),
                (0.50, 0.075, 0.08, TROUSERS),
                (0.92, 0.058, 0.058, TROUSERS),
                (1.00, 0.056, 0.056, TROUSERS),
            ],
            X,
            leg_chain,
        )
        tube(
            "lower_leg",
            [sn, ft],
            [
                (0.00, 0.056, 0.056, TROUSERS),
                (0.15, 0.058, 0.062, TROUSERS),
                (0.55, 0.045, 0.050, BOOT),
                (0.92, 0.040, 0.044, BOOT),
                (1.00, 0.040, 0.044, BOOT),
            ],
            X,
            leg_chain,
        )
        tube(
            "foot",
            [ft, toe, toe + Vector((0, -0.08, 0))],
            [
                (0.00, 0.040, 0.050, BOOT),
                (0.30, 0.048, 0.050, BOOT),
                (0.62, 0.050, 0.030, BOOT),
                (1.00, 0.030, 0.018, BOOT),
            ],
            X,
            leg_chain,
        )

    # ---- mesh object, flat faces, colors, weights ------------------------------------------
    mesh = bpy.data.meshes.new("Body")
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    obj = bpy.data.objects.new("Body", mesh)
    bpy.context.scene.collection.objects.link(obj)
    for name in PARTS:
        material = bpy.data.materials.new(name)
        mesh.materials.append(material)
    for poly, part in zip(mesh.polygons, face_part):
        poly.material_index = part
        poly.use_smooth = False
    layer = mesh.color_attributes.new("Color", "BYTE_COLOR", "CORNER")
    for poly, color in zip(mesh.polygons, face_color):
        for loop in poly.loop_indices:
            layer.data[loop].color = (*color, 1.0)
    mesh.color_attributes.active_color = layer
    mesh.update()

    obj.parent = rig
    obj.parent_type = "OBJECT"
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig

    if skin_method == "rigid":
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

    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    kwargs = dict(
        filepath=out,
        export_format="GLB",
        export_animations=False,
        export_skins=True,
        export_apply=False,
        export_yup=True,
        export_vertex_color="ACTIVE",
        export_active_vertex_color_when_no_material=True,
        export_materials="EXPORT",
    )
    bpy.ops.export_scene.gltf(**kwargs)
    print("WROTE", out, len(verts), "verts", len(faces), "faces")


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
