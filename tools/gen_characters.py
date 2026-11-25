"""Genera los modelos 3D de los personajes de NEXORA con Blender (bpy).

Uso (con Blender instalado como módulo de Python, `pip install bpy`):
    python tools/gen_characters.py

Crea en models/:
    humanoid.glb   jugadores, NPCs y bandidos (ropa por capas, accesorios intercambiables)
    shade.glb      las sombras nocturnas (manto andrajoso, garras, ojos que brillan)
    brute.glb      el bruto sombrío (enorme, cuernos, hombreras de hueso, grietas que brillan)

Estilo: inspirado en Albion Online (proporciones robustas, manos y botas grandes, ropa en
capas, colores planos) pero low-poly, para que rinda bien en el celular.

Los tres modelos comparten el mismo esqueleto (mismos nombres de huesos que las
articulaciones de scripts/characters/humanoid.gd): las animaciones del juego se calculan
por código y mueven estos huesos. Todos los huesos apuntan hacia arriba y sin giro, así en
Godot su orientación de reposo es la identidad.

Coordenadas: se escribe todo en el sistema de Godot (X derecha, Y arriba, el personaje mira
hacia -Z) y se convierte al de Blender al crear los vértices.

Materiales: los que se llaman Skin, Hair, Shirt, Pants, Boots y Cape se recolorean en el
juego según la apariencia de cada personaje. Los accesorios son objetos "acc_<nombre>"
que el juego muestra u oculta.
"""

import math
import os
import random
import sys

import bpy  # Tiene que ir antes que bmesh y mathutils (los registra).
import bmesh
from mathutils import Vector

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models")

BONES = [
    # nombre, padre, posición (Godot, en metros)
    ("hips", None, (0.0, 0.92, 0.0)),
    ("spine", "hips", (0.0, 1.00, 0.0)),
    ("head", "spine", (0.0, 1.62, 0.0)),
    ("shoulder_l", "spine", (-0.245, 1.47, 0.0)),
    ("elbow_l", "shoulder_l", (-0.245, 1.18, 0.0)),
    ("hand_l", "elbow_l", (-0.245, 0.90, 0.0)),
    ("shoulder_r", "spine", (0.245, 1.47, 0.0)),
    ("elbow_r", "shoulder_r", (0.245, 1.18, 0.0)),
    ("hand_r", "elbow_r", (0.245, 0.90, 0.0)),
    ("hip_l", "hips", (-0.1, 0.90, 0.0)),
    ("knee_l", "hip_l", (-0.1, 0.46, 0.0)),
    ("ankle_l", "knee_l", (-0.1, 0.04, 0.0)),
    ("hip_r", "hips", (0.1, 0.90, 0.0)),
    ("knee_r", "hip_r", (0.1, 0.46, 0.0)),
    ("ankle_r", "knee_r", (0.1, 0.04, 0.0)),
]

MATERIALS = {
    # nombre: (color base, rugosidad, emisión)
    "Skin": ((0.9, 0.74, 0.6), 0.7, 0.0),
    "Hair": ((0.25, 0.17, 0.1), 0.8, 0.0),
    "Shirt": ((0.3, 0.5, 0.8), 0.85, 0.0),
    "Pants": ((0.25, 0.27, 0.32), 0.9, 0.0),
    "Boots": ((0.28, 0.2, 0.14), 0.75, 0.0),
    "Cape": ((0.62, 0.1, 0.12), 0.9, 0.0),
    "Leather": ((0.33, 0.22, 0.14), 0.7, 0.0),
    "Metal": ((0.62, 0.64, 0.68), 0.35, 0.0),
    "Gold": ((1.0, 0.78, 0.25), 0.3, 0.0),
    "Dark": ((0.06, 0.05, 0.05), 0.9, 0.0),
    "Straw": ((0.85, 0.75, 0.45), 0.9, 0.0),
    "Apron": ((0.42, 0.29, 0.17), 0.9, 0.0),
    "Bandana": ((0.45, 0.1, 0.1), 0.9, 0.0),
    "Gem": ((0.85, 0.1, 0.2), 0.2, 0.6),
    "Shadow": ((0.05, 0.04, 0.08), 1.0, 0.0),
    "ShadowCloth": ((0.16, 0.12, 0.22), 1.0, 0.0),
    "Glow": ((1.0, 0.25, 0.12), 0.5, 6.0),
    "Bone": ((0.78, 0.74, 0.66), 0.8, 0.0),
}


def g2b(v):
    """Godot (x, y, z) → Blender (x, -z, y)."""
    return Vector((v[0], -v[2], v[1]))


# --- Constructor de mallas ---------------------------------------------------------------

class Builder:
    """Junta piezas (tubos, esferas, cajas) en una sola malla con pesos por hueso."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.deform = self.bm.verts.layers.deform.verify()
        self.materials = []
        self.groups = [b[0] for b in BONES]

    def _mat(self, name):
        if name not in self.materials:
            self.materials.append(name)
        return self.materials.index(name)

    def _weigh(self, vert, weights):
        total = sum(weights.values())
        for bone, w in weights.items():
            vert[self.deform][self.groups.index(bone)] = w / total

    def tube(self, rings, mat, segs=10, cap_bottom=True, cap_top=True, smooth=True, twist=0.0):
        """rings: lista de (centro, rx, rz, {hueso: peso}). Anillos horizontales."""
        m = self._mat(mat)
        loops = []
        for center, rx, rz, weights in rings:
            loop = []
            for k in range(segs):
                a = 2 * math.pi * k / segs + twist
                p = (center[0] + math.cos(a) * rx, center[1], center[2] + math.sin(a) * rz)
                v = self.bm.verts.new(g2b(p))
                self._weigh(v, weights)
                loop.append(v)
            loops.append(loop)
        faces = []
        for i in range(len(loops) - 1):
            a, b = loops[i], loops[i + 1]
            for k in range(segs):
                k2 = (k + 1) % segs
                faces.append(self.bm.faces.new((a[k], a[k2], b[k2], b[k])))
        if cap_bottom:
            faces.append(self.bm.faces.new(list(reversed(loops[0]))))
        if cap_top:
            faces.append(self.bm.faces.new(loops[-1]))
        for f in faces:
            f.material_index = m
            f.smooth = smooth
        return loops

    def blob(self, center, radius, mat, weights, segs=10, rings=6, scale=(1, 1, 1), smooth=True, jitter=0.0, seed=0):
        m = self._mat(mat)
        rng = random.Random(seed)
        ret = bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings, radius=radius)
        for v in ret["verts"]:
            # create_uvsphere trabaja en coordenadas de Blender: lo pasamos a Godot para escalar.
            gx, gy, gz = v.co.x, v.co.z, -v.co.y
            gx, gy, gz = gx * scale[0], gy * scale[1], gz * scale[2]
            if jitter:
                gx += rng.uniform(-jitter, jitter)
                gy += rng.uniform(-jitter, jitter)
                gz += rng.uniform(-jitter, jitter)
            v.co = g2b((center[0] + gx, center[1] + gy, center[2] + gz))
            self._weigh(v, weights)
        for f in {f for v in ret["verts"] for f in v.link_faces}:
            f.material_index = m
            f.smooth = smooth

    def box(self, center, size, mat, weights, taper=1.0, rot_y=0.0, smooth=False, bevel=0.0):
        """Caja (con el techo achicado por "taper"), girada rot_y sobre Y."""
        m = self._mat(mat)
        ret = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = ret["verts"]
        for v in verts:
            gx, gy, gz = v.co.x * size[0], v.co.z * size[1], -v.co.y * size[2]
            if gy > 0:
                gx *= taper
                gz *= taper
            c, s = math.cos(rot_y), math.sin(rot_y)
            gx, gz = gx * c + gz * s, -gx * s + gz * c
            v.co = g2b((center[0] + gx, center[1] + gy, center[2] + gz))
            self._weigh(v, weights)
        faces = list({f for v in verts for f in v.link_faces})
        if bevel > 0:
            edges = list({e for v in verts for e in v.link_edges})
            res = bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=1, affect="EDGES")
            faces = [f for f in faces if f.is_valid] + list(res.get("faces", []))
            for f in res.get("faces", []):
                for v in f.verts:
                    self._weigh(v, weights)
        for f in faces:
            if f.is_valid:
                f.material_index = m
                f.smooth = smooth

    def cone(self, base, tip, radius, mat, weights, segs=6, smooth=False):
        """Cono de "base" a "tip" (cuernos, garras, púas)."""
        m = self._mat(mat)
        axis = Vector(tip) - Vector(base)
        axis_n = axis.normalized()
        helper = Vector((0, 1, 0)) if abs(axis_n.y) < 0.9 else Vector((1, 0, 0))
        u = axis_n.cross(helper).normalized()
        w = axis_n.cross(u).normalized()
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            p = Vector(base) + (u * math.cos(a) + w * math.sin(a)) * radius
            v = self.bm.verts.new(g2b(p))
            self._weigh(v, weights)
            ring.append(v)
        apex = self.bm.verts.new(g2b(tip))
        self._weigh(apex, weights)
        faces = [self.bm.faces.new(list(reversed(ring)))]
        for k in range(segs):
            faces.append(self.bm.faces.new((ring[k], ring[(k + 1) % segs], apex)))
        for f in faces:
            f.material_index = m
            f.smooth = smooth

    def build(self, armature, materials):
        mesh = bpy.data.meshes.new(self.name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.collection.objects.link(obj)
        for name in self.materials:
            mesh.materials.append(materials[name])
        for bone in self.groups:
            obj.vertex_groups.new(name=bone)
        obj.parent = armature
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = armature
        return obj


# --- Escena, esqueleto y materiales --------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_materials(overrides=None):
    result = {}
    for name, (color, rough, emission) in MATERIALS.items():
        if overrides and name in overrides:
            color = overrides[name]
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = 0.6 if name in ("Metal", "Gold") else 0.0
        if emission > 0:
            bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission
        result[name] = mat
    return result


def make_armature(bones=BONES):
    data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    edit = {}
    for name, parent, pos in bones:
        b = data.edit_bones.new(name)
        b.head = g2b(pos)
        b.tail = g2b((pos[0], pos[1] + 0.08, pos[2]))  # Todos hacia arriba, sin giro.
        b.roll = 0.0
        if parent:
            b.parent = edit[parent]
            b.use_connect = False
        edit[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def export(path, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_skins=True,
        export_animations=False, export_yup=True, export_apply=False, export_materials="EXPORT",
    )
    print("exportado:", path)


def lerp_w(a, b, t):
    return {a: 1.0 - t, b: t} if 0.0 < t < 1.0 else ({a: 1.0} if t <= 0.0 else {b: 1.0})


# --- Humanoide (jugadores, NPCs, bandidos) ------------------------------------------------

def humanoid_body(b):
    # Piernas: muslo y pantorrilla en una sola pieza que se dobla en la rodilla.
    for side, x in (("l", -0.1), ("r", 0.1)):
        hip, knee, ankle = "hip_" + side, "knee_" + side, "ankle_" + side
        b.tube([
            ((x, 0.93, 0.0), 0.112, 0.112, {hip: 1}),
            ((x, 0.72, 0.0), 0.104, 0.104, {hip: 1}),
            ((x, 0.52, 0.0), 0.088, 0.09, {hip: 0.7, knee: 0.3}),
            ((x, 0.44, 0.0), 0.084, 0.086, {hip: 0.3, knee: 0.7}),
            ((x, 0.3, 0.0), 0.078, 0.078, {knee: 1}),
            ((x, 0.12, 0.0), 0.066, 0.068, {knee: 0.6, ankle: 0.4}),
        ], "Pants", cap_top=False)
        # Botas robustas: caña ancha y pie con punta redondeada.
        b.tube([
            ((x, 0.06, 0.0), 0.088, 0.09, {ankle: 1}),
            ((x, 0.22, 0.0), 0.09, 0.092, {knee: 0.5, ankle: 0.5}),
            ((x, 0.36, 0.0), 0.104, 0.106, {knee: 1}),
            ((x, 0.4, 0.0), 0.112, 0.114, {knee: 1}),
        ], "Boots", cap_bottom=False, cap_top=False)
        b.box((x, 0.055, -0.055), (0.15, 0.11, 0.3), "Boots", {ankle: 1}, taper=0.85, bevel=0.03)
        b.box((x, 0.012, -0.055), (0.16, 0.03, 0.32), "Leather", {ankle: 1})  # suela

    # Torso: de la pelvis al cuello, más ancho en el pecho y los hombros.
    b.tube([
        ((0, 0.86, 0.0), 0.18, 0.13, {"hips": 1}),
        ((0, 0.98, 0.0), 0.172, 0.125, {"hips": 0.6, "spine": 0.4}),
        ((0, 1.12, 0.0), 0.18, 0.13, {"spine": 1}),
        ((0, 1.3, -0.01), 0.22, 0.15, {"spine": 1}),
        ((0, 1.44, 0.0), 0.24, 0.14, {"spine": 1}),
        ((0, 1.54, 0.0), 0.13, 0.1, {"spine": 1}),
    ], "Shirt", segs=12)
    b.tube([
        ((0, 1.5, 0.0), 0.06, 0.06, {"spine": 1}),
        ((0, 1.66, 0.0), 0.055, 0.055, {"spine": 0.3, "head": 0.7}),
    ], "Skin", segs=8, cap_bottom=False)
    # Faldón de la túnica (sobre el pantalón), con un tajo adelante y atrás.
    b.tube([
        ((0, 1.0, 0.0), 0.185, 0.137, {"hips": 1}),
        ((0, 0.82, 0.0), 0.215, 0.16, {"hips": 1}),
        ((0, 0.58, 0.0), 0.25, 0.19, {"hips": 1}),
    ], "Shirt", segs=12, cap_bottom=False, cap_top=False)
    # Cinturón con hebilla y bolsita.
    b.tube([
        ((0, 0.94, 0.0), 0.196, 0.146, {"hips": 1}),
        ((0, 1.02, 0.0), 0.19, 0.142, {"hips": 0.7, "spine": 0.3}),
    ], "Leather", segs=12, cap_bottom=False, cap_top=False)
    b.box((0, 0.98, -0.15), (0.08, 0.07, 0.02), "Metal", {"hips": 1})
    b.box((0.18, 0.92, -0.05), (0.08, 0.1, 0.07), "Leather", {"hips": 1}, taper=0.85, bevel=0.01)
    # Cuello de la camisa.
    b.tube([
        ((0, 1.52, 0.0), 0.1, 0.085, {"spine": 1}),
        ((0, 1.57, 0.0), 0.085, 0.075, {"spine": 1}),
    ], "Leather", segs=10, cap_bottom=False, cap_top=False)

    # Brazos: hombro redondo, manga, antebrazo con brazal y manos grandes.
    for side, x in (("l", -0.245), ("r", 0.245)):
        sh, el, ha = "shoulder_" + side, "elbow_" + side, "hand_" + side
        sx = 1 if x > 0 else -1
        b.blob((x - sx * 0.005, 1.45, 0.0), 0.1, "Shirt", {sh: 0.7, "spine": 0.3}, segs=10, rings=6)
        b.tube([
            ((x, 1.46, 0.0), 0.088, 0.088, {sh: 1}),
            ((x, 1.26, 0.0), 0.078, 0.078, {sh: 1}),
            ((x, 1.18, 0.0), 0.074, 0.074, {sh: 0.5, el: 0.5}),
            ((x, 1.12, 0.0), 0.072, 0.072, {el: 1}),
        ], "Shirt", segs=9, cap_top=False)
        b.tube([
            ((x, 1.14, 0.0), 0.064, 0.064, {el: 1}),
            ((x, 0.96, 0.0), 0.054, 0.054, {el: 0.8, ha: 0.2}),
        ], "Skin", segs=9, cap_top=False, cap_bottom=False)
        b.tube([  # brazal de cuero
            ((x, 0.92, 0.0), 0.066, 0.066, {el: 0.5, ha: 0.5}),
            ((x, 1.07, 0.0), 0.074, 0.074, {el: 1}),
        ], "Leather", segs=9)
        b.blob((x, 0.855, -0.005), 0.07, "Skin", {ha: 1}, segs=8, rings=5, scale=(0.85, 1.15, 0.75))
        b.blob((x - sx * 0.03, 0.875, -0.045), 0.027, "Skin", {ha: 1}, segs=6, rings=4, scale=(1, 1.4, 1))  # pulgar

    # Cabeza (un poco grande, como en Albion), orejas, nariz, ojos y cejas.
    b.blob((0, 1.75, 0.0), 0.125, "Skin", {"head": 1}, segs=14, rings=9, scale=(1.0, 1.1, 1.05))
    b.box((0, 1.66, -0.02), (0.15, 0.06, 0.15), "Skin", {"head": 1}, taper=1.1, smooth=True)  # mandíbula
    b.box((0, 1.735, -0.135), (0.036, 0.065, 0.05), "Skin", {"head": 1}, taper=0.6)
    for sx in (-1, 1):
        b.blob((sx * 0.128, 1.75, 0.01), 0.026, "Skin", {"head": 1}, segs=6, rings=4, scale=(0.5, 1.2, 0.9))
        b.box((sx * 0.047, 1.765, -0.12), (0.04, 0.036, 0.02), "Dark", {"head": 1})
        b.box((sx * 0.048, 1.802, -0.122), (0.058, 0.02, 0.025), "Hair", {"head": 1}, rot_y=0.0)
    b.box((0, 1.69, -0.122), (0.05, 0.01, 0.01), "Dark", {"head": 1})  # boca


def humanoid_accessories(materials, armature):
    """Cada accesorio es un objeto aparte que el juego muestra u oculta."""
    accs = []

    def acc(name, fn):
        b = Builder("acc_" + name)
        fn(b)
        accs.append(b.build(armature, materials))

    H = {"head": 1}
    acc("hair_short", lambda b: (
        b.blob((0, 1.79, 0.012), 0.135, "Hair", H, segs=14, rings=8, scale=(1.02, 0.85, 1.08), jitter=0.006, seed=1),
        b.box((0, 1.7, 0.09), (0.21, 0.12, 0.07), "Hair", H, taper=0.9, smooth=True),
    ))
    acc("hair_long", lambda b: (
        b.blob((0, 1.79, 0.012), 0.137, "Hair", H, segs=14, rings=8, scale=(1.04, 0.86, 1.1), jitter=0.006, seed=2),
        b.box((0, 1.58, 0.08), (0.25, 0.3, 0.09), "Hair", {"head": 0.6, "spine": 0.4}, taper=1.1, smooth=True),
    ))
    acc("bun", lambda b: b.blob((0, 1.86, 0.12), 0.065, "Hair", H, segs=8, rings=5))
    acc("beard", lambda b: b.box((0, 1.66, -0.085), (0.18, 0.09, 0.08), "Hair", H, taper=0.8, smooth=True, bevel=0.015))
    acc("long_beard", lambda b: b.box((0, 1.6, -0.1), (0.17, 0.24, 0.07), "Hair", H, taper=1.15, smooth=True, bevel=0.015))
    acc("cap", lambda b: (
        b.tube([((0, 1.83, 0.0), 0.138, 0.142, H), ((0, 1.9, 0.0), 0.12, 0.125, H)], "Pants", segs=12),
        b.box((0, 1.83, -0.15), (0.18, 0.02, 0.1), "Pants", H),
    ))
    acc("straw_hat", lambda b: (
        b.tube([((0, 1.85, 0.0), 0.3, 0.3, H), ((0, 1.86, 0.0), 0.3, 0.3, H)], "Straw", segs=14),
        b.tube([((0, 1.85, 0.0), 0.13, 0.13, H), ((0, 1.97, 0.0), 0.11, 0.11, H)], "Straw", segs=12),
    ))
    acc("hood", lambda b: (
        b.blob((0, 1.78, 0.03), 0.165, "Shirt", H, segs=12, rings=8, scale=(1.0, 1.15, 1.1)),
        b.tube([((0, 1.53, 0.0), 0.2, 0.15, {"spine": 1}), ((0, 1.64, 0.02), 0.15, 0.13, {"spine": 0.5, "head": 0.5})],
               "Shirt", segs=12, cap_bottom=False, cap_top=False),
    ))
    acc("apron", lambda b: b.box((0, 0.92, -0.17), (0.3, 0.5, 0.02), "Apron", {"hips": 1}))
    acc("crown", lambda b: [
        b.tube([((0, 1.86, 0.0), 0.138, 0.138, H), ((0, 1.91, 0.0), 0.14, 0.14, H)], "Gold", segs=12,
               cap_bottom=False, cap_top=False),
    ] + [b.cone((math.sin(a) * 0.135, 1.9, math.cos(a) * 0.135), (math.sin(a) * 0.135, 1.97, math.cos(a) * 0.135),
                0.025, "Gold", H, segs=4) for a in [i * 2 * math.pi / 6 for i in range(6)]]
        + [b.blob((0, 1.885, -0.14), 0.018, "Gem", H, segs=6, rings=4)])
    acc("helmet", lambda b: (
        b.blob((0, 1.8, 0.0), 0.15, "Metal", H, segs=12, rings=8, scale=(1.0, 0.95, 1.05)),
        b.tube([((0, 1.78, 0.0), 0.152, 0.158, H), ((0, 1.81, 0.0), 0.152, 0.158, H)], "Metal", segs=12),
        b.box((0, 1.74, -0.155), (0.025, 0.1, 0.02), "Metal", H),
    ))
    acc("chainmail", lambda b: (
        b.tube([((0, 0.8, 0.0), 0.2, 0.15, {"hips": 1}), ((0, 1.0, 0.0), 0.172, 0.125, {"hips": 0.6, "spine": 0.4}),
                ((0, 1.3, -0.01), 0.205, 0.14, {"spine": 1}), ((0, 1.46, 0.0), 0.225, 0.13, {"spine": 1}),
                ((0, 1.54, 0.0), 0.13, 0.1, {"spine": 1})], "Metal", segs=12, cap_bottom=False),
        b.box((0, 1.18, -0.15), (0.26, 0.5, 0.02), "Shirt", {"spine": 1}),  # sobreveste
        b.box((0, 0.84, -0.16), (0.26, 0.24, 0.02), "Shirt", {"hips": 1}),
    ))
    acc("cape", lambda b: (
        b.box((0, 1.0, 0.16), (0.48, 0.95, 0.03), "Cape", {"spine": 1}, taper=0.75),
        b.box((0, 1.5, 0.1), (0.42, 0.06, 0.18), "Cape", {"spine": 1}),
    ))
    acc("dress", lambda b: b.tube([
        ((0, 0.98, 0.0), 0.17, 0.125, {"hips": 1}), ((0, 0.6, 0.0), 0.25, 0.2, {"hips": 1}),
        ((0, 0.08, 0.0), 0.33, 0.28, {"hips": 1}),
    ], "Shirt", segs=14, cap_top=False))
    acc("bandana", lambda b: b.box((0, 1.69, -0.08), (0.24, 0.1, 0.1), "Bandana", H, smooth=True))
    return accs


def build_humanoid():
    reset_scene()
    materials = make_materials()
    arm = make_armature()
    b = Builder("Body")
    humanoid_body(b)
    body = b.build(arm, materials)
    accs = humanoid_accessories(materials, arm)
    export(os.path.join(OUT_DIR, "humanoid.glb"), [arm, body] + accs)


# --- Sombra ------------------------------------------------------------------------------

def build_shade():
    reset_scene()
    materials = make_materials()
    arm = make_armature()
    b = Builder("Body")
    rng = random.Random(7)
    # Piernas finas y oscuras (casi no se ven bajo el manto).
    for side, x in (("l", -0.1), ("r", 0.1)):
        b.tube([((x, 0.9, 0), 0.06, 0.06, {"hip_" + side: 1}), ((x, 0.46, 0), 0.045, 0.045, {"hip_" + side: 0.5, "knee_" + side: 0.5}),
                ((x, 0.05, 0.02), 0.035, 0.04, {"ankle_" + side: 1})], "Shadow", segs=7)
        b.cone((x, 0.05, -0.02), (x, 0.02, -0.2), 0.04, "Shadow", {"ankle_" + side: 1}, segs=5)
    # Cuerpo delgado y encorvado.
    b.tube([((0, 0.88, 0.02), 0.13, 0.1, {"hips": 1}), ((0, 1.12, 0.04), 0.13, 0.11, {"spine": 1}),
            ((0, 1.36, 0.0), 0.18, 0.13, {"spine": 1}), ((0, 1.52, -0.04), 0.1, 0.09, {"spine": 1})], "Shadow", segs=10)
    # Manto andrajoso: el borde de abajo cortado en jirones.
    segs = 16
    hem = []
    for k in range(segs):
        hem.append(rng.uniform(0.1, 0.45))
    loops = b.tube([((0, 1.42, 0.02), 0.22, 0.17, {"spine": 1}), ((0, 1.0, 0.04), 0.26, 0.22, {"hips": 0.5, "spine": 0.5}),
                    ((0, 0.6, 0.06), 0.31, 0.27, {"hips": 1}), ((0, 0.2, 0.08), 0.34, 0.3, {"hips": 1})],
                   "ShadowCloth", segs=segs, cap_bottom=False, cap_top=False)
    for k, v in enumerate(loops[-1]):
        v.co.z += hem[k] * (1.0 if k % 2 == 0 else 0.4)  # jirones a distinta altura (Z de Blender = altura)
    # Capucha grande con la cara en sombra y ojos que brillan.
    b.blob((0, 1.72, 0.0), 0.17, "ShadowCloth", {"head": 1}, segs=12, rings=8, scale=(1.0, 1.2, 1.15), jitter=0.01, seed=3)
    b.cone((0, 1.85, 0.12), (0, 1.75, 0.34), 0.08, "ShadowCloth", {"head": 1}, segs=6)  # punta de la capucha
    b.blob((0, 1.7, -0.15), 0.12, "Dark", {"head": 1}, segs=10, rings=6, scale=(1.0, 1.1, 0.55))
    for sx in (-1, 1):
        b.blob((sx * 0.05, 1.73, -0.21), 0.028, "Glow", {"head": 1}, segs=6, rings=4, scale=(1.5, 0.75, 0.6))
    # Brazos largos y huesudos con garras.
    for side, x in (("l", -0.245), ("r", 0.245)):
        sh, el, ha = "shoulder_" + side, "elbow_" + side, "hand_" + side
        b.tube([((x, 1.46, 0), 0.06, 0.06, {sh: 1}), ((x, 1.18, 0), 0.045, 0.045, {sh: 0.5, el: 0.5}),
                ((x, 0.92, 0), 0.035, 0.035, {el: 0.6, ha: 0.4})], "Shadow", segs=7)
        b.tube([((x, 1.44, 0.02), 0.085, 0.085, {sh: 1}), ((x, 1.2, 0.02), 0.1, 0.1, {sh: 0.5, el: 0.5}),
                ((x, 1.02, 0.03), 0.12, 0.12, {el: 1})], "ShadowCloth", segs=8, cap_bottom=False, cap_top=False)
        b.blob((x, 0.86, 0), 0.05, "Shadow", {ha: 1}, segs=7, rings=4, scale=(0.9, 1.1, 0.8))
        for i in range(3):
            off = (i - 1) * 0.03
            b.cone((x + off, 0.83, -0.02), (x + off * 1.6, 0.68, -0.08), 0.014, "Shadow", {ha: 1}, segs=4)
    body = b.build(arm, materials)
    # Jirones flotando alrededor (pegados a la espalda).
    wisps = Builder("acc_wisps")
    for i in range(5):
        a = rng.uniform(0, 2 * math.pi)
        y = rng.uniform(0.6, 1.6)
        p = (math.cos(a) * 0.32, y, 0.1 + math.sin(a) * 0.25)
        wisps.cone(p, (p[0] * 1.3, p[1] + 0.25, p[2] + 0.15), 0.03, "ShadowCloth", {"spine": 1}, segs=4)
    w = wisps.build(arm, materials)
    export(os.path.join(OUT_DIR, "shade.glb"), [arm, body, w])


# --- Bruto sombrío ------------------------------------------------------------------------

BRUTE_BONES = [
    ("hips", None, (0.0, 0.88, 0.0)),
    ("spine", "hips", (0.0, 0.98, 0.0)),
    ("head", "spine", (0.0, 1.66, -0.12)),
    ("shoulder_l", "spine", (-0.36, 1.5, 0.0)),
    ("elbow_l", "shoulder_l", (-0.4, 1.17, 0.0)),
    ("hand_l", "elbow_l", (-0.42, 0.86, 0.0)),
    ("shoulder_r", "spine", (0.36, 1.5, 0.0)),
    ("elbow_r", "shoulder_r", (0.4, 1.17, 0.0)),
    ("hand_r", "elbow_r", (0.42, 0.86, 0.0)),
    ("hip_l", "hips", (-0.14, 0.86, 0.0)),
    ("knee_l", "hip_l", (-0.15, 0.44, 0.0)),
    ("ankle_l", "knee_l", (-0.15, 0.05, 0.0)),
    ("hip_r", "hips", (0.14, 0.86, 0.0)),
    ("knee_r", "hip_r", (0.15, 0.44, 0.0)),
    ("ankle_r", "knee_r", (0.15, 0.05, 0.0)),
]


def build_brute():
    reset_scene()
    materials = make_materials()
    arm = make_armature(BRUTE_BONES)
    b = Builder("Body")
    # Piernas gruesas y patas anchas.
    for side, x in (("l", -0.15), ("r", 0.15)):
        hp, kn, an = "hip_" + side, "knee_" + side, "ankle_" + side
        b.tube([((x, 0.9, 0), 0.13, 0.13, {hp: 1}), ((x, 0.5, 0), 0.11, 0.11, {hp: 0.5, kn: 0.5}),
                ((x, 0.12, 0), 0.1, 0.1, {kn: 0.5, an: 0.5})], "Shadow", segs=9)
        b.box((x, 0.06, -0.06), (0.2, 0.12, 0.3), "Shadow", {an: 1}, taper=0.8, bevel=0.03)
        for i in range(3):
            b.cone((x + (i - 1) * 0.06, 0.05, -0.2), (x + (i - 1) * 0.07, 0.02, -0.3), 0.025, "Bone", {an: 1}, segs=4)
    # Torso enorme, inclinado hacia adelante, con grietas que brillan.
    b.tube([((0, 0.82, 0.02), 0.22, 0.17, {"hips": 1}), ((0, 1.02, 0.0), 0.25, 0.19, {"hips": 0.5, "spine": 0.5}),
            ((0, 1.3, -0.03), 0.36, 0.25, {"spine": 1}), ((0, 1.52, -0.02), 0.38, 0.24, {"spine": 1}),
            ((0, 1.64, -0.06), 0.2, 0.16, {"spine": 1})], "Shadow", segs=12)
    for y, x, rz in ((1.35, -0.1, 0.4), (1.22, 0.08, -0.3), (1.45, 0.12, 0.2)):
        b.box((x, y, -0.255), (0.03, 0.22, 0.02), "Glow", {"spine": 1}, rot_y=0.0)
    # Hombreras de hueso con púas.
    for side, x in (("l", -0.36), ("r", 0.36)):
        sx = 1 if x > 0 else -1
        b.blob((x, 1.55, 0.0), 0.16, "Bone", {"shoulder_" + side: 0.6, "spine": 0.4}, segs=8, rings=5, scale=(1.1, 0.8, 1.0),
               jitter=0.02, seed=4 + sx)
        for i in range(3):
            base = (x + sx * 0.05 * i, 1.65, -0.05 + 0.06 * i)
            b.cone(base, (base[0] + sx * 0.12, base[1] + 0.22, base[2] + 0.04), 0.04, "Bone", {"shoulder_" + side: 1}, segs=5)
        sh, el, ha = "shoulder_" + side, "elbow_" + side, "hand_" + side
        # Brazos enormes (más gruesos en el antebrazo) y puños gigantes.
        b.tube([((x, 1.5, 0), 0.12, 0.12, {sh: 1}), ((x + sx * 0.04, 1.17, 0), 0.11, 0.11, {sh: 0.5, el: 0.5}),
                ((x + sx * 0.05, 1.05, 0), 0.14, 0.14, {el: 1}), ((x + sx * 0.06, 0.92, 0), 0.12, 0.12, {el: 0.6, ha: 0.4})],
               "Shadow", segs=9)
        b.blob((x + sx * 0.06, 0.8, -0.02), 0.13, "Shadow", {ha: 1}, segs=9, rings=6, scale=(1.0, 1.0, 1.05), jitter=0.01, seed=8)
        for i in range(3):
            b.cone((x + sx * 0.06 + (i - 1) * 0.05, 0.74, -0.12), (x + sx * 0.06 + (i - 1) * 0.06, 0.66, -0.2), 0.022,
                   "Bone", {ha: 1}, segs=4)
    # Cabeza chica y hundida, con cuernos y ojos brillantes.
    b.blob((0, 1.72, -0.16), 0.14, "Shadow", {"head": 1}, segs=10, rings=7, scale=(1.1, 0.95, 1.1))
    b.box((0, 1.64, -0.27), (0.2, 0.08, 0.1), "Shadow", {"head": 1}, taper=0.8, bevel=0.02)  # mandíbula
    for sx in (-1, 1):
        b.cone((sx * 0.1, 1.8, -0.12), (sx * 0.3, 1.98, -0.02), 0.045, "Bone", {"head": 1}, segs=6)
        b.cone((sx * 0.3, 1.98, -0.02), (sx * 0.33, 2.08, -0.16), 0.028, "Bone", {"head": 1}, segs=5)
        b.blob((sx * 0.05, 1.73, -0.29), 0.024, "Glow", {"head": 1}, segs=6, rings=4, scale=(1.4, 0.7, 0.6))
        b.cone((sx * 0.06, 1.61, -0.31), (sx * 0.05, 1.68, -0.32), 0.015, "Bone", {"head": 1}, segs=4)  # colmillos
    body = b.build(arm, materials)
    export(os.path.join(OUT_DIR, "brute.glb"), [arm, body])


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    which = sys.argv[1:] or ["humanoid", "shade", "brute"]
    if "humanoid" in which:
        build_humanoid()
    if "shade" in which:
        build_shade()
    if "brute" in which:
        build_brute()
