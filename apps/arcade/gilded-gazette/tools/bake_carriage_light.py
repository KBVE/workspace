"""Bakes the carriage's gas lighting into vertex colours.

Run headless through Blender. The lamps are read off the same numbers Consist
stands them on, so a lamp moved in the engine is a lamp moved here:

    blender --background --python tools/bake_carriage_light.py -- \
        out/ godot/assets/train/carriage_empty.gltf godot/assets/train/carriage_seating.gltf

Every source named is imported into one scene and baked together, then written back
out one file per source. Baking them apart is what it looks like: the benches cast no
shadow on the floor they stand on and take no bounce off the wall behind them, because
in their own scene neither was there.

Vertex colours rather than a lightmap. A game glTF has no second UV set and its
first one tiles, so a texture bake would need an unwrap that changes the asset;
colours per vertex need nothing, cost no VRAM, keep every carriage sharing one
material, and are what the hardware this look comes from actually used.

What is baked is irradiance only -- no albedo -- so the result multiplies the
existing base colour rather than replacing it. That keeps one bake correct for
every texture the carriage might be reskinned with.
"""
import json
import os
import sys

import bpy

LAMP_COUNT = 6
LAMP_FIRST_X = -6.2
LAMP_PITCH = 2.48
LAMP_HEIGHT = 4.05
LAMP_COLOUR = (1.0, 0.84, 0.6)
LAMP_WATTS = 45.0
LAMP_RADIUS = 0.18

NIGHT_SKY = (0.02, 0.03, 0.05, 1.0)

SAMPLES = 64
COLOUR_ATTRIBUTE = "Col"

## What the bake is multiplied by, and what it is never allowed to fall below.
##
## Six point lamps in a night carriage are physically correct and unplayable: the
## ceiling clips to white and the floor between lamps lands near 0.03, so the aisle
## reads as black with pools in it. The ambient is the light a real carriage gets for
## free -- bounce off varnished wood and upholstery that an irradiance bake with no
## colour pass never carries -- and it is warm because everything in here is.
EXPOSURE = 1.35
AMBIENT = (0.16, 0.14, 0.11)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def hang_the_lamps():
    """Six gas lamps down the ceiling, where Consist puts them.

    Godot is Y up and Blender is Z up, and the glTF importer has already turned the
    carriage, so the lamp positions turn with it: Godot (x, y, z) is Blender (x, -z, y).
    """
    for i in range(LAMP_COUNT):
        light = bpy.data.lights.new(name=f"Lamp_{i}", type="POINT")
        light.color = LAMP_COLOUR
        light.energy = LAMP_WATTS
        light.shadow_soft_size = LAMP_RADIUS
        holder = bpy.data.objects.new(f"Lamp_{i}", light)
        holder.location = (LAMP_FIRST_X + i * LAMP_PITCH, 0.0, LAMP_HEIGHT)
        bpy.context.scene.collection.objects.link(holder)


def night_outside():
    world = bpy.data.worlds.new("Night")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = NIGHT_SKY
    bpy.context.scene.world = world


def set_up_cycles():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.render.bake.target = "VERTEX_COLORS"
    # irradiance only: the colour pass would bake the texture into the vertices and
    # the material would then be multiplying its own albedo by itself
    scene.render.bake.use_pass_direct = True
    scene.render.bake.use_pass_indirect = True
    scene.render.bake.use_pass_color = False


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def give_every_mesh_somewhere_to_bake():
    for mesh_object in meshes():
        mesh = mesh_object.data
        existing = mesh.color_attributes.get(COLOUR_ATTRIBUTE)
        if existing is not None:
            mesh.color_attributes.remove(existing)
        attribute = mesh.color_attributes.new(
            name=COLOUR_ATTRIBUTE, type="BYTE_COLOR", domain="CORNER")
        mesh.color_attributes.active_color = attribute
        mesh.color_attributes.render_color_index = \
            mesh.color_attributes.find(COLOUR_ATTRIBUTE)


def tone(mesh_object):
    """Lifts the bake off the floor and clips it, in place, before export."""
    colours = mesh_object.data.color_attributes.get(COLOUR_ATTRIBUTE)
    if colours is None:
        return
    for entry in colours.data:
        lit = entry.color
        entry.color = (
            min(1.0, AMBIENT[0] + lit[0] * EXPOSURE),
            min(1.0, AMBIENT[1] + lit[1] * EXPOSURE),
            min(1.0, AMBIENT[2] + lit[2] * EXPOSURE),
            1.0,
        )


def bake():
    targets = meshes()
    if not targets:
        raise SystemExit("nothing to bake: the import brought in no meshes")
    bpy.ops.object.select_all(action="DESELECT")
    for mesh_object in targets:
        mesh_object.select_set(True)
    bpy.context.view_layer.objects.active = targets[0]
    bpy.ops.object.bake(type="DIFFUSE")


def import_and_claim(source):
    """Imports one file and hands back the objects it brought, so it can be written
    back out on its own once everything has been baked together."""
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=source)
    arrived = [o for o in bpy.context.scene.objects if o not in before]
    for stray in [o for o in arrived if o.type in {"LIGHT", "CAMERA"}]:
        bpy.data.objects.remove(stray, do_unlink=True)
    return [o for o in arrived if o.name in bpy.context.scene.objects]


def main(into, sources):
    clear_scene()
    by_source = {source: import_and_claim(source) for source in sources}

    night_outside()
    hang_the_lamps()
    set_up_cycles()
    give_every_mesh_somewhere_to_bake()
    print(f"baking {len(meshes())} meshes at {SAMPLES} samples")
    bake()
    for mesh_object in meshes():
        tone(mesh_object)

    for lamp in [o for o in bpy.context.scene.objects if o.type == "LIGHT"]:
        bpy.data.objects.remove(lamp, do_unlink=True)

    os.makedirs(into, exist_ok=True)
    for source, arrived in by_source.items():
        bpy.ops.object.select_all(action="DESELECT")
        for mesh_object in arrived:
            mesh_object.select_set(True)
        stem = os.path.splitext(os.path.basename(source))[0]
        destination = os.path.join(into, f"{stem}_lit.gltf")
        bpy.ops.export_scene.gltf(
            filepath=destination,
            export_format="GLTF_SEPARATE",
            export_vertex_color="ACTIVE",
            export_all_vertex_colors=False,
            export_yup=True,
            use_selection=True,
        )
        prune_unlit_textures(destination)
        print(f"wrote {destination}")


def prune_unlit_textures(path):
    """Drops the normal and roughness maps out of the exported materials.

    Nothing samples them once the carriage is unshaded, but a material that still
    names a texture is a texture Godot loads: between them they are 7.4MB of source
    art and a pair of compressed 2048s resident in VRAM for surfaces that are lit by
    a vertex colour. On a phone that is the difference worth having.
    """
    with open(path) as f:
        gltf = json.load(f)

    for material in gltf.get("materials", []):
        material.pop("normalTexture", None)
        material.get("pbrMetallicRoughness", {}).pop("metallicRoughnessTexture", None)

    kept = set()
    for material in gltf.get("materials", []):
        base = material.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if base is not None:
            kept.add(base["index"])
        for slot in ("emissiveTexture", "occlusionTexture"):
            if slot in material:
                kept.add(material[slot]["index"])

    # textures and images are indexed, so pruning means renumbering everything that
    # points at them rather than deleting in place
    textures = gltf.get("textures", [])
    order = sorted(kept)
    remap = {old: new for new, old in enumerate(order)}
    gltf["textures"] = [textures[i] for i in order]
    for material in gltf.get("materials", []):
        base = material.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if base is not None:
            base["index"] = remap[base["index"]]
        for slot in ("emissiveTexture", "occlusionTexture"):
            if slot in material:
                material[slot]["index"] = remap[material[slot]["index"]]

    used_images = {t["source"] for t in gltf["textures"] if "source" in t}
    images = gltf.get("images", [])
    image_order = sorted(used_images)
    image_remap = {old: new for new, old in enumerate(image_order)}
    gltf["images"] = [images[i] for i in image_order]
    for texture in gltf["textures"]:
        if "source" in texture:
            texture["source"] = image_remap[texture["source"]]

    with open(path, "w") as f:
        json.dump(gltf, f, indent=2)
    print(f"  kept {len(gltf['images'])} image(s): "
          f"{[i.get('uri') for i in gltf['images']]}")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(argv) < 2:
        raise SystemExit("usage: ... -- <output directory> <source.gltf> [source.gltf ...]")
    main(argv[0], argv[1:])
