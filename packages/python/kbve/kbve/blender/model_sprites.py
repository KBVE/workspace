#!/usr/bin/env python3
"""Blender headless 360 sprite-sheet baker for iso / billboard renderers.

Loads a model (OBJ/FBX/BLEND), lays the hull flat on the ground plane, spins it
through N yaw steps under an orthographic camera, and bakes one transparent PNG
per facing — then stitches them into a square sheet and a 1xN strip that the
Phaser `EnvDef` / class rigs read row-major (frame index = facing).

The output is engine-agnostic: what a consumer needs to place the sprite in its
own world is the camera elevation it was baked at and the world size one frame
spans, and both are written to `meta.json` beside the sheet.

Why "lay flat": many ship/vehicle models import standing upright (nose along the
model's up axis). An env sprite is drawn as an upright screen billboard, so an
upright render reads as a ship standing on its tail. `--pitch` rotates the hull
onto the ground (deck toward +Z) before the spin, so each frame reads as a
vehicle resting on the floor. A model that is already level wants `--pitch 0`.

Two source shapes, and they want opposite handling:

  * A bare OBJ/FBX plus one `--skin` texture. Every mesh is joined into one and
    given a single emissive-plus-diffuse material, which is what makes a
    low-detail model read as bright flat sprite art. This is the default.
  * An authored `.blend` that already has its own PBR materials, an armature and
    modifiers — a Poly Haven asset, say. Here joining is destructive (a join
    keeps only the active object's modifier stack, so rigged sails and
    geometry-node rigging collapse) and overriding the materials throws away the
    detail that is the whole reason to pre-render. Pass `--keep-materials`, and
    the meshes are left alone and parented to a pivot instead of joined.

Authored scenes also tend to carry objects that are not the subject: rig control
widgets, helpers, reference planes. `--exclude` and `--include` take
comma-separated `fnmatch` patterns over object names and are applied before
anything is parented, so those never reach a frame.

Dial the angle interactively first with `preview-model-sprites.html` (same Z-up /
ortho / pitch / yaw math) — it prints the exact flags to paste here.

This module imports `bpy`, so it only runs inside Blender's bundled python. Launch
it via the console entrypoint, which finds Blender and execs it headless:

    uv run kbve-model-sprites -- \
        --model fighter1.obj --skin idolknight.jpg --out render_flat \
        --frames 16 --res 256 --elev 35 --pitch 90 --yaw-offset 0

    uv run kbve-model-sprites -- \
        --model ship_pinnace_1k.blend --out ships/pinnace --keep-materials \
        --exclude 'wdg_*,hlp_*' --frames 16 --res 256 --elev 41.25 --pitch 0

Or directly: blender -b -P model_sprites.py -- <args>

Single parked frame (no spin): pass --frames 1 with the chosen --yaw-offset.
"""
import argparse
import fnmatch
import json
import math
import os
import sys

import bpy
import mathutils


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser(prog="kbve-model-sprites")
    p.add_argument("--model", required=True, help="source .obj, .fbx or .blend")
    p.add_argument("--skin", default=None,
                   help="texture applied to all meshes; required unless --keep-materials")
    p.add_argument("--out", required=True, help="output dir (frames + sheet + strip)")
    # --- authored-scene handling ---
    p.add_argument("--keep-materials", action="store_true",
                   help="render the model's own materials and skip the join; for a .blend "
                        "that already has PBR materials, an armature or modifiers")
    p.add_argument("--include", default="",
                   help="comma-separated name patterns to keep (default: everything)")
    p.add_argument("--exclude", default="",
                   help="comma-separated name patterns to drop, e.g. 'wdg_*,hlp_*'")
    p.add_argument("--show", default="",
                   help="comma-separated name patterns to un-hide before filtering; picks "
                        "the pose an asset ships switched off, e.g. sails set vs furled")
    p.add_argument("--mask-material", default="",
                   help="render a coverage mask instead of the model: faces whose "
                        "material name matches this fnmatch pattern come out white and "
                        "everything else black, with alpha and occlusion unchanged. For "
                        "picking one part of a baked sprite out later -- sails to tint "
                        "by side, say -- without a second guess at which pixels those "
                        "were. Bake it with the same flags as the beauty pass and "
                        "WITHOUT --foam or the shadow, which are not part of the model")
    p.add_argument("--mask-object", default="",
                   help="objects whose NAME matches this fnmatch pattern come out white "
                        "in the mask, on top of --mask-material. For a pose where the "
                        "part wanted is not its own material: an asset with its sails "
                        "furled may carry the stowed canvas on the rigging mesh, and "
                        "then the only thing that names it is the object")
    p.add_argument("--clip-below", type=float, default=None,
                   help="hide everything below this height in the SOURCE model's own "
                        "space, e.g. 0 for a hull modelled about its waterline. The cut "
                        "follows the real geometry, so it curves with the heading")
    p.add_argument("--ambient", type=float, default=0.0,
                   help="world background strength; fills the side the sun does not reach")
    p.add_argument("--ambient-color", default="0.75,0.80,0.95",
                   help="world background colour as r,g,b in 0..1")
    p.add_argument("--frames", type=int, default=16, help="yaw facings (1 = static)")
    p.add_argument("--res", type=int, default=256, help="px per frame (square)")
    # --- animation (spool-up / takeoff, or hover idle) ---
    p.add_argument("--anim-frames", type=int, default=1,
                   help="animation frames PER facing (1 = static). >1 bakes an animation")
    p.add_argument("--anim-mode",
                   choices=["lift", "idle", "move", "bank", "launch"], default="lift",
                   help="lift=rise once; idle=hover bob loop; move=flying bob+sway loop; "
                        "bank=monotonic roll left->right (turn lean, index by turn-rate); "
                        "launch=cinematic ascent to space (leaving atmosphere; reverse for entering)")
    p.add_argument("--lift", type=float, default=0.6,
                   help="hover height as a fraction of model size (lift target / idle+move+bank base)")
    p.add_argument("--bob", type=float, default=0.06,
                   help="vertical bob amplitude as a fraction of model size (idle/move)")
    p.add_argument("--sway", type=float, default=8.0,
                   help="bank/roll amplitude in degrees (move sway / bank extent)")
    # --- launch (leaving atmosphere) cinematic ---
    p.add_argument("--launch-height", type=float, default=5.0, help="ascent height x model size")
    p.add_argument("--launch-pitch", type=float, default=70.0, help="nose-up pitch deg at apex")
    p.add_argument("--launch-shrink", type=float, default=0.12, help="final scale (fakes distance)")
    p.add_argument("--elev", type=float, default=35.0, help="camera elevation deg (iso pitch); 35=2:1")
    p.add_argument("--pitch", type=float, default=90.0, help="lay-flat hull pitch about X, baked before spin")
    p.add_argument("--yaw-offset", type=float, default=0.0, help="heading added to every frame; sets frame_00")
    p.add_argument("--emit", type=float, default=0.55, help="0=unlit emissive .. 1=pure diffuse shading mix")
    # shadow knobs forwarded to sprite_postprocess.py (fractions of frame size)
    # --- real shadow (Cycles shadow-catcher pass) ---
    p.add_argument("--real-shadow", action="store_true",
                   help="render a TRUE cast shadow (Cycles + ground catcher); overrides the fake 2D shadow")
    p.add_argument("--sun-elev", type=float, default=55.0,
                   help="sun elevation deg; applies to every bake, not only --real-shadow")
    p.add_argument("--sun-az", type=float, default=135.0,
                   help="sun azimuth deg; the shadow falls opposite. Always applies")
    p.add_argument("--sun-energy", type=float, default=3.0,
                   help="sun strength. Set with --ambient: it is their ratio, not either "
                        "alone, that decides how washed out the result looks")
    p.add_argument("--sun-soft", type=float, default=4.0, help="sun angular size deg = penumbra softness")
    p.add_argument("--samples", type=int, default=64, help="Cycles samples (real-shadow)")
    # --- fake 2D shadow (default; post-process) ---
    p.add_argument("--no-shadow", action="store_true", help="skip the baked ground shadow")
    # --- foam, forwarded to sprite_postprocess ---
    p.add_argument("--foam", action="store_true",
                   help="bake a foam line along the bottom of the silhouette; for a hull "
                        "cut at its waterline that is exactly where the water meets it")
    p.add_argument("--foam-alpha", type=float, default=0.40, help="foam opacity 0..1")
    p.add_argument("--foam-thickness", type=float, default=0.010, help="foam band width / frame")
    p.add_argument("--foam-spread", type=float, default=0.010, help="foam blur / frame")
    p.add_argument("--foam-lift", type=float, default=0.0, help="foam offset / frame")
    p.add_argument("--foam-color", default="255,255,255", help="foam rgb 0..255")
    p.add_argument("--foam-climb", type=float, default=0.006,
                   help="how far foam may rise above the waterline / frame")
    p.add_argument("--shadow-alpha", type=float, default=0.45, help="shadow darkness 0..1")
    p.add_argument("--shadow-blur", type=float, default=0.06, help="shadow blur radius / frame")
    p.add_argument("--shadow-squash", type=float, default=0.7, help="shadow vertical flatten 0..1")
    p.add_argument("--shadow-shear", type=float, default=0.15, help="shadow iso ground skew")
    p.add_argument("--shadow-grow", type=float, default=0.05, help="shadow dilate / frame (rim halo)")
    p.add_argument("--shadow-dx", type=float, default=0.0, help="shadow x offset / frame")
    p.add_argument("--shadow-dy", type=float, default=0.045, help="shadow y offset / frame")
    return p.parse_args(argv)


def patterns(spec):
    """Split a comma-separated pattern list, dropping blanks."""
    return [p.strip() for p in spec.split(",") if p.strip()]


def wanted(name, include, exclude):
    """Does an object name survive the include/exclude filters?

    An empty include list means "everything", which is what keeps the filters
    off the path of a bare OBJ import that has nothing to filter.
    """
    if include and not any(fnmatch.fnmatch(name, p) for p in include):
        return False
    return not any(fnmatch.fnmatch(name, p) for p in exclude)


def load_model(a):
    """Open the source and return the mesh objects that make up the subject.

    A `.blend` is opened rather than imported, so its materials, armature and
    modifiers arrive intact; its own cameras and lights are dropped, because
    this script supplies both and a stray key light in the file would make the
    bake depend on how the asset happened to be lit.
    """
    ext = os.path.splitext(a.model)[1].lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=a.model)
        for o in [o for o in bpy.data.objects if o.type in {"CAMERA", "LIGHT"}]:
            bpy.data.objects.remove(o, do_unlink=True)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if ext == ".obj":
            bpy.ops.wm.obj_import(filepath=a.model)
        elif ext == ".fbx":
            bpy.ops.import_scene.fbx(filepath=a.model)
        else:
            raise SystemExit("unsupported model ext: " + ext)

    # An asset often ships more than one pose, with the unused half switched off
    # rather than absent -- a set of sails furled and the same sails drawn. Those
    # are hidden objects, so un-hiding by name is how a variant is selected, and
    # it happens before the filters so `--exclude` can drop the pose not wanted.
    show = patterns(a.show)
    if show:
        for o in bpy.context.scene.objects:
            if any(fnmatch.fnmatch(o.name, p) for p in show):
                o.hide_render = False

    include, exclude = patterns(a.include), patterns(a.exclude)
    meshes = [
        o for o in bpy.context.scene.objects
        if o.type == "MESH" and not o.hide_render and wanted(o.name, include, exclude)
    ]
    if not meshes:
        raise SystemExit("no mesh to render (check --include / --exclude)")

    # Everything the filters rejected is deleted rather than merely skipped: an
    # object left in the scene still renders, and rig control widgets are
    # visible objects sitting right on top of the subject.
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH" and o not in meshes:
            bpy.data.objects.remove(o, do_unlink=True)
    return meshes


def skin_material(a):
    """One emissive-plus-diffuse material off a single texture.

    Emission is what makes a low-detail model read as bright flat sprite art;
    the diffuse share keeps the form shading rather than going uniform.
    """
    mat = bpy.data.materials.new("skin")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(a.skin)
    bsdf = nt.nodes.new("ShaderNodeBsdfDiffuse")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = a.emit
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], mix.inputs[1])
    nt.links.new(bsdf.outputs["BSDF"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return mat


def world_bounds(meshes):
    """World-space bounding box of the evaluated meshes.

    Evaluated, not raw: an object's `bound_box` is its cage before modifiers,
    and a rope built by geometry nodes or an array can reach well outside it.
    Framing on the raw box crops exactly that geometry out of the frame.
    """
    dg = bpy.context.evaluated_depsgraph_get()
    lo = mathutils.Vector((float("inf"),) * 3)
    hi = mathutils.Vector((float("-inf"),) * 3)
    for o in meshes:
        ev = o.evaluated_get(dg)
        for corner in ev.bound_box:
            w = ev.matrix_world @ mathutils.Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def build_pivot(meshes, pitch_deg):
    """Hang the meshes off a two-empty rig and return the outer (yaw) empty.

    A rig rather than a baked rotation, because the meshes cannot always be
    joined into one object -- an authored asset's armature and modifiers do not
    survive a join -- and N loose objects need one handle to spin.

    The order matters and the nesting is what enforces it. World transform is
    `Rz(yaw) . Rx(pitch) . T(-centre)`: the model is centred on the origin, laid
    flat, and only then spun about world Z. Pitching after the yaw would tip the
    hull sideways on every facing but the first.
    """
    lo, hi = world_bounds(meshes)
    centre = (lo + hi) / 2.0

    pivot = bpy.data.objects.new("sprite_pivot", None)
    base = bpy.data.objects.new("sprite_base", None)
    centred = bpy.data.objects.new("sprite_centre", None)
    for e in (pivot, base, centred):
        bpy.context.scene.collection.objects.link(e)
    base.parent = pivot
    centred.parent = base
    base.rotation_euler = (math.radians(pitch_deg), 0.0, 0.0)
    centred.location = -centre

    # Only roots get reparented: a mesh already parented to another object in
    # the source scene -- to the armature, typically -- keeps that parent, and
    # moving it here would tear it off its rig.
    for o in meshes:
        if o.parent is None:
            o.parent = centred
    # An armature is a root that drives its meshes, so it has to travel too.
    for o in bpy.context.scene.objects:
        if o.type == "ARMATURE" and o.parent is None:
            o.parent = centred

    bpy.context.view_layer.update()
    # `centred` sits exactly where the source file's own origin ended up, which
    # is the one height in the frame that means something outside the render.
    # `centre` comes back too, because locating a plane in the frame needs the
    # subject's own middle to measure from.
    return pivot, centred, centre


def main():
    a = parse_args()
    if not a.skin and not a.keep_materials:
        raise SystemExit("--skin is required unless --keep-materials is passed")
    os.makedirs(a.out, exist_ok=True)

    meshes = load_model(a)

    if not a.keep_materials:
        # Joining is only safe once the materials are being thrown away anyway:
        # a join keeps the active object's modifier stack alone, so it is
        # destructive to anything rigged. The --keep-materials path skips it.
        bpy.ops.object.select_all(action="DESELECT")
        for m in meshes:
            m.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        if len(meshes) > 1:
            bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        meshes = [obj]
        mat = skin_material(a)
        obj.data.materials.clear()
        obj.data.materials.append(mat)

    # ---- lay flat and give the loose meshes one handle to spin ----
    obj, anchor, centre = build_pivot(meshes, a.pitch)

    # ---- frame the model ----
    lo, hi = world_bounds(meshes)
    size = max(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
    min_z = lo[2]  # hull underside — where the shadow-catcher plane sits

    # Lift animation: the hull rises this many world units over `anim_frames`. The
    # camera + ground stay fixed (so the contact line keeps a constant screen y and
    # one originY works for every frame); we just add headroom above and nudge the
    # framing down so the lifted hull never clips.
    lift_world = a.lift * size if a.anim_frames > 1 else 0.0

    # ---- orthographic iso camera, along -Y lifted by elevation ----
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = (size + lift_world) * 1.6
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    elev = math.radians(a.elev)
    dist = size * 3.0
    base_loc = mathutils.Vector((0.0, -dist * math.cos(elev), dist * math.sin(elev)))
    # shift framing down by moving the camera along its local up (keeps it parallel)
    up = mathutils.Vector((0.0, math.sin(elev), math.cos(elev)))
    cam.location = base_loc + up * (lift_world * 0.5)
    cam.rotation_euler = (math.radians(90.0) - elev, 0.0, 0.0)
    bpy.context.scene.camera = cam

    # ---- sun: straight down at sun_elev=90, tilted toward the horizon otherwise,
    # rotated by azimuth. The cast shadow falls opposite the sun. ----
    light_data = bpy.data.lights.new("sun", "SUN")
    light_data.energy = a.sun_energy
    if a.real_shadow:
        light_data.angle = math.radians(a.sun_soft)  # penumbra
    light = bpy.data.objects.new("sun", light_data)
    light.rotation_euler = (
        math.radians(90.0 - a.sun_elev),
        0.0,
        math.radians(a.sun_az),
    )
    bpy.context.scene.collection.objects.link(light)

    # ---- clip: a holdout plane at the model's own waterline ----
    #
    # A holdout renders as a hole rather than as a surface: with a transparent
    # film, everything the plane covers comes back with zero alpha. So a
    # horizontal plane at the waterline erases exactly the submerged part of the
    # hull, and it erases it along the line where the water really meets the
    # planking -- a curve, different for every heading.
    #
    # Doing it here rather than in the consuming engine is the whole point. Down
    # there a sprite is a flat billboard and the only cut available is a
    # straight horizontal one, which is wrong by as much as the subject is long:
    # a sea-level plane seen at `elev` sweeps `length * sin(elev)` of screen
    # height from near end to far, which for this hull is 41% of the frame. Up
    # here the geometry is still real and the cut is exact.
    #
    # Parented to `centred`, so it is the source file's own z-plane -- it moves
    # with the centring and tilts with `--pitch` rather than being a height in
    # some intermediate space nobody can name.
    clip = None
    if a.clip_below is not None:
        bpy.ops.mesh.primitive_plane_add(size=size * 8.0)
        clip = bpy.context.active_object
        clip.name = "sprite_clip"
        clip.parent = anchor
        clip.location = (0.0, 0.0, a.clip_below)
        clip.rotation_euler = (0.0, 0.0, 0.0)
        # A Holdout *shader*, not the object flag of the same name: the object
        # flag is a Cycles feature and EEVEE Next quietly renders the plane as
        # an ordinary surface instead, which moved the hull's silhouette by a
        # few pixels rather than cutting it. The shader node works in both.
        mat = bpy.data.materials.new("sprite_clip")
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        hold = nt.nodes.new("ShaderNodeHoldout")
        nt.links.new(hold.outputs[0], out.inputs["Surface"])
        clip.data.materials.clear()
        clip.data.materials.append(mat)

    # ---- ambient: a flat world colour so the side the sun misses is dark rather
    # than black. The skin material is mostly emissive and needs none of this,
    # which is why it defaults off; a PBR asset under one sun needs it. ----
    if a.ambient > 0.0:
        rgb = [float(v) for v in a.ambient_color.split(",")]
        if len(rgb) != 3:
            raise SystemExit("--ambient-color wants three comma-separated numbers")
        world = bpy.data.worlds.new("ambient")
        world.use_nodes = True
        bg = world.node_tree.nodes["Background"]
        bg.inputs["Color"].default_value = (*rgb, 1.0)
        bg.inputs["Strength"].default_value = a.ambient
        bpy.context.scene.world = world

    # ---- mask: the same render with every material flattened to a light ----
    #
    # White where the named material is, black everywhere else, and nothing else
    # about the scene touched -- same camera, same yaw sequence, same clip, so
    # frame N of the mask is frame N of the beauty pass to the pixel.
    #
    # Emission rather than base colour because emission is the one channel that
    # does not care about the sun: a white diffuse surface would still be shaded,
    # and a mask with a shadow across it is a mask that dyes half a sail.
    #
    # The alpha input is deliberately left wired. The sails are a cutout -- their
    # shape is an alpha texture on a quad, not geometry -- so a mask that dropped
    # that link would mark the whole quad and dye the sky between the shrouds.
    # Everything else is left in the scene as well, unflattened but black, which
    # is what keeps a mast in front of a sail punching a hole in it.
    if a.mask_material or a.mask_object:
        # Objects first, and by a copy of each material rather than the material
        # itself: a material is shared, so lighting up `ship_pinnace_rigging`
        # because one object wants it would light up every rope on the ship.
        lit_objects = patterns(a.mask_object)
        for o in bpy.context.scene.objects:
            if o.type != "MESH" or not any(
                fnmatch.fnmatch(o.name, p) for p in lit_objects
            ):
                continue
            for slot in o.material_slots:
                if slot.material is not None:
                    slot.material = slot.material.copy()
                    slot.material.name = f"mask_lit_{slot.material.name}"

        for m in bpy.data.materials:
            if not m.use_nodes:
                continue
            bsdf = next(
                (n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None
            )
            if bsdf is None:
                continue
            lit = m.name.startswith("mask_lit_") or (
                bool(a.mask_material) and fnmatch.fnmatch(m.name, a.mask_material)
            )
            for name, value in (
                ("Base Color", (0.0, 0.0, 0.0, 1.0)),
                ("Emission Color", (1.0, 1.0, 1.0, 1.0) if lit else (0.0, 0.0, 0.0, 1.0)),
                ("Emission Strength", 1.0),
                ("Metallic", 0.0),
                ("Roughness", 1.0),
                # Named for the socket rather than the effect: a black surface
                # still has a specular highlight, and a highlight in a mask is a
                # bright spot that is not the thing being masked.
                ("Specular IOR Level", 0.0),
            ):
                socket = bsdf.inputs.get(name)
                if socket is None:
                    continue
                for link in list(socket.links):
                    m.node_tree.links.remove(link)
                socket.default_value = value
        # No sky either: an ambient world lights the black and lifts the floor
        # off zero, and a mask wants exactly two values in it.
        bpy.context.scene.world = None

    sc = bpy.context.scene
    sc.render.resolution_x = a.res
    sc.render.resolution_y = a.res
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"

    if a.real_shadow:
        # A large plane under the hull, flagged as a Cycles shadow catcher: with a
        # transparent film it contributes ONLY the cast shadow's alpha, so each
        # frame carries the true shadow for that facing + light. No fake 2D pass.
        sc.render.engine = "CYCLES"
        sc.cycles.samples = a.samples
        sc.cycles.use_denoising = True
        bpy.ops.mesh.primitive_plane_add(size=size * 8.0, location=(0.0, 0.0, min_z))
        catcher = bpy.context.active_object
        catcher.is_shadow_catcher = True
        # keep the catcher off the beauty (it only catches shadow)
        catcher.visible_diffuse = False
        catcher.visible_glossy = False
    else:
        engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
        sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"

    # ---- render: outer loop = facing (yaw), inner = anim frame (lift). Frame index
    # is row-major `dir * anim_frames + f`, exactly what Phaser's EnvDef reads
    # (directions rows x frames cols). anim_frames==1 collapses to the static spin. ----
    k = max(1, a.anim_frames)
    paths = []
    total = a.frames * k
    for d in range(a.frames):
        yaw = math.radians(a.yaw_offset + 360.0 * d / a.frames)
        obj.rotation_euler = (0.0, 0.0, yaw)
        for f in range(k):
            phase = 2.0 * math.pi * f / k  # seamless: frame k wraps to 0
            t = f / (k - 1) if k > 1 else 0.0  # 0..1 ramp for non-looping modes
            if a.anim_mode == "idle":
                obj.location.z = lift_world + a.bob * size * math.sin(phase)
            elif a.anim_mode == "move":
                # flying: vertical bob + bank/roll sway (roll about local forward Y,
                # applied before yaw by Blender's XYZ euler = correct bank-then-point).
                # bob lags the sway by 90deg so it reads organic, not mechanical.
                obj.location.z = lift_world + a.bob * size * math.sin(phase + math.pi / 2)
                obj.rotation_euler = (0.0, math.radians(a.sway) * math.sin(phase), yaw)
            elif a.anim_mode == "bank":
                # MONOTONIC roll: frame 0 = hard left .. last = hard right, so the game
                # indexes turn-rate -> frame to HOLD a lean (not a round-trip loop).
                obj.location.z = lift_world
                roll = math.radians(-a.sway + 2.0 * a.sway * t)
                obj.rotation_euler = (0.0, roll, yaw)
            elif a.anim_mode == "launch":
                # cinematic ascent: accelerate up (ease-in t^2), pitch nose to sky,
                # shrink to fake distance. Play forward = leaving; reverse = entering.
                obj.location.z = lift_world + a.launch_height * size * (t * t)
                obj.rotation_euler = (math.radians(a.launch_pitch) * t, 0.0, yaw)
                s = 1.0 - (1.0 - a.launch_shrink) * (t * t)
                obj.scale = (s, s, s)
            else:  # lift
                ease = t * t * (3.0 - 2.0 * t)  # smoothstep spool-up, holds at the top
                obj.location.z = ease * lift_world
            idx = d * k + f
            fp = os.path.join(a.out, f"frame_{idx:03d}.png")

            # A second pass with the clip plane hidden, when something
            # downstream needs to know where the water actually cut.
            #
            # The difference between the two renders is precisely the submerged
            # geometry, so the top of that region is the waterline -- per column,
            # exactly, including the fact that it does not exist under a
            # figurehead or a spar, which project forward over open water and
            # are cut by nothing. That is not recoverable from the finished
            # frame: down there the lowest opaque pixel of a figurehead looks
            # exactly like the lowest opaque pixel of a hull.
            #
            # Costs a second render of every frame, and only happens when the
            # foam pass is going to consume it.
            if clip is not None and a.foam:
                clip.hide_render = True
                sc.render.filepath = os.path.join(a.out, f"wl_{idx:03d}.png")
                bpy.ops.render.render(write_still=True)
                clip.hide_render = False

            sc.render.filepath = fp
            bpy.ops.render.render(write_still=True)
            paths.append(fp)
            print(f"rendered {idx + 1}/{total} (dir {d}, lift {f})")

    # Where the source file's own origin lands in the frame, as a fraction of
    # the frame height from its bottom edge. Projected the way the camera
    # projects: an orthographic camera at `elev` measures height along its own
    # up axis, so a point's screen height is its dot product with that axis.
    up_axis = mathutils.Vector((0.0, math.sin(elev), math.cos(elev)))

    def frame_fraction(local_z):
        """Where a horizontal plane at `local_z` lands in the frame.

        Measured at the subject's own middle, not at the model origin. A plane
        seen from above does not project to one height -- its screen position
        runs with depth -- so the frame's centre line is the only reading of it
        that is a single number, and it is also the one that does not move when
        the subject spins.

        Measuring at the origin instead read differently for every yaw, so the
        recorded anchor depended on which heading happened to be rendered last:
        the same bake at four frames and at sixteen disagreed by a hundredth of
        a frame, which is a hull floating a metre high.
        """
        # Rotation only. The vector is already measured from the subject's
        # centre, and the rig's translation is what put that centre on the
        # origin -- applying the full matrix would subtract the centring twice.
        local = mathutils.Vector((0.0, 0.0, local_z - centre.z))
        point = anchor.matrix_world.to_3x3() @ local
        return 0.5 + (point.dot(up_axis) - lift_world * 0.5) / cam_data.ortho_scale

    anchor_fraction = frame_fraction(0.0)
    # Where the subject was actually cut, which is the height a consumer has to
    # hang the sprite at. Only the same as the origin when the cut is at zero.
    clip_fraction = None if a.clip_below is None else frame_fraction(a.clip_below)

    write_meta(
        a, k, cam_data.ortho_scale,
        [hi[i] - lo[i] for i in range(3)], anchor_fraction, clip_fraction,
    )
    postprocess(a)
    print("DONE")


def sheet_layout(n, cols):
    """The grid `sprite_postprocess` will lay the frames out on.

    Imported from that module rather than reimplemented, by path because
    Blender's python does not have this package on its path. It is the module
    that actually pastes the sheet, so it is the one that gets to decide the
    grid; if it cannot be loaded the meta simply omits the layout rather than
    asserting a guess that might not match the pixels.
    """
    import importlib.util
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location(
        "sprite_postprocess", os.path.join(here, "sprite_postprocess.py"))
    if spec is None or spec.loader is None:
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.layout(n, cols)


def write_meta(a, anim_frames, ortho_scale, model_size, anchor_fraction, clip_fraction):
    """Record what a consumer needs to place the sprite in its own world.

    A frame on its own is unplaceable: it says nothing about how many world
    units it spans, so the engine drawing it has to guess a quad size, and the
    guess silently changes the moment the model or the framing does. Writing the
    orthographic width here makes that a number the game reads rather than a
    constant someone tuned by eye.

    `elev` is the other half. A billboard is only correct under the camera angle
    it was baked at, so the value belongs beside the pixels -- if the game's
    camera pitch ever moves, this is what says the sheet has to be rebaked.
    """
    meta = {
        "frames": a.frames,
        "anim_frames": anim_frames,
        "res": a.res,
        "elev_deg": a.elev,
        "pitch_deg": a.pitch,
        "yaw_offset_deg": a.yaw_offset,
        # Yaw of frame 0 and the step between frames, in degrees, counter-
        # clockwise seen from above. Frame index = round(heading / step) % frames.
        "yaw_step_deg": 360.0 / a.frames,
        # World units the full square frame spans, and what the model itself
        # occupies of it. The ratio is the padding the spin needs, and it is what
        # lets a consumer size a quad from the subject's real length rather than
        # from the frame it happens to be padded into.
        "frame_world_size": ortho_scale,
        "model_world_size": [round(v, 6) for v in model_size],
        # Longest horizontal extent, after the lay-flat pitch: for anything
        # vehicle-shaped this is its length, which is the dimension a consumer
        # actually knows a real-world figure for.
        "model_world_length": round(max(model_size[0], model_size[1]), 6),
        # Height of the source file's own origin plane within the frame, as a
        # fraction from the bottom edge. A frame is padded blank above and below
        # the subject, so nothing about the pixels says where the model was
        # anchored -- and that anchor is usually the one height a consumer needs:
        # the ground a vehicle rests on, or the water a hull floats at.
        #
        # Only as meaningful as the source file's origin. An asset modelled
        # about its centre puts this in the middle of the subject and says
        # nothing; one modelled about its waterline or its wheels puts it
        # exactly where it belongs.
        "origin_frame_fraction": round(anchor_fraction, 6),
    }

    if clip_fraction is not None:
        # The plane the subject was cut at, in the same frame-fraction terms.
        # This is the one a consumer wants: the cut edge is the sprite's real
        # bottom, and hanging it by the origin instead floats the subject by
        # exactly the distance between the two planes.
        meta["clip_below"] = a.clip_below
        meta["waterline_frame_fraction"] = round(clip_fraction, 6)

    grid = sheet_layout(a.frames * anim_frames, anim_frames if anim_frames > 1 else 0)
    if grid:
        meta["sheet_cols"], meta["sheet_rows"] = grid
    with open(os.path.join(a.out, "meta.json"), "w") as fh:
        json.dump(meta, fh, indent=2)
        fh.write("\n")


def postprocess(a):
    """Bake the ground shadow + stitch the sheet/strip via sprite_postprocess.py.

    That helper needs Pillow, which Blender's bundled python usually lacks, so we
    shell out to the system `python3` (which carries it). Frames are written either
    way; only the shadow + sheet depend on this step.
    """
    import shutil
    import subprocess
    py = shutil.which("python3") or shutil.which("python")
    here = os.path.dirname(os.path.abspath(__file__))
    helper = os.path.join(here, "sprite_postprocess.py")
    if not py or not os.path.exists(helper):
        print("no system python3 / helper for post-process; frames written, sheet skipped.")
        return
    cmd = [py, helper, "--dir", a.out, "--res", str(a.res)]
    if a.anim_frames > 1:
        # row-major layout: one row per facing, one column per anim frame, so
        # Phaser's frame index == dir * anim_frames + f (EnvDef directions x frames).
        cmd += ["--cols", str(a.anim_frames)]
    if a.foam:
        cmd += [
            "--foam",
            "--foam-alpha", str(a.foam_alpha),
            "--foam-thickness", str(a.foam_thickness),
            "--foam-spread", str(a.foam_spread),
            "--foam-lift", str(a.foam_lift),
            "--foam-color", a.foam_color,
            "--foam-climb", str(a.foam_climb),
        ]
    if a.no_shadow or a.real_shadow:
        cmd.append("--no-shadow")  # real shadow is already in the frames; just stitch
    cmd += [
        "--shadow-alpha", str(a.shadow_alpha),
        "--shadow-blur", str(a.shadow_blur),
        "--shadow-squash", str(a.shadow_squash),
        "--shadow-shear", str(a.shadow_shear),
        "--shadow-grow", str(a.shadow_grow),
        "--shadow-dx", str(a.shadow_dx),
        "--shadow-dy", str(a.shadow_dy),
    ]
    try:
        subprocess.run(cmd, check=True)
    except (subprocess.CalledProcessError, OSError) as e:
        print(f"post-process failed ({e}); frames written, sheet skipped.")


if __name__ == "__main__":
    main()
