"""Turns a downloaded PBR asset into an item model this game can carry.

    blender -b <source>.blend -P tools/import-item-model.py -- \
        --out godot/assets/items/ornate_dagger.glb

The assets worth using come as a .blend plus a 1k PBR set -- diffuse, normal,
roughness, metallic -- and none of that survives contact with this game. Props
here are drawn by shaders/prop.gdshader, which takes one albedo texture and a
baked lamp tint and has no channel to put a normal map in; the other three maps
would be exported, downloaded by every browser, and then ignored. So this keeps
the diffuse, resizes it, drops the rest, and writes one self-contained glb.

The geometry gets the same treatment, and for the same reason. A downloaded
asset is modelled for a render, so it arrives with a few thousand triangles on
something the size of a hand; the props already in this train are built out of
dozens, and one item carrying more geometry than the whole carriage around it
is weight nobody sees. Vertex data is also the bulk of what a glb weighs -- a
1k albedo resized to 256 saves a tenth of what collapsing the mesh does.

It also lies the object down. A weapon asset is modelled standing up, because
that is how a product shot wants it, and an item in this game is on the floor
of a carriage or on a table in one. Standing it up would need a rotation
authored per item to undo a convention that was never about this game.

Origin goes to the ground under the mesh, which is the convention the prop
library already follows: `above` in a placement is then the height of whatever
surface the thing stands on, and nothing needs a fudge factor per model.
"""

import argparse
import sys
from pathlib import Path

import bpy


def args_after_double_dash() -> list[str]:
    # Blender takes everything before `--` for itself and passes the rest on;
    # with no `--` at all there are no script arguments, not the whole line.
    if '--' not in sys.argv:
        return []
    return sys.argv[sys.argv.index('--') + 1:]


def parse() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', required=True, help='glb to write')
    p.add_argument('--name', default='', help='mesh name in the glb; defaults to the out stem')
    p.add_argument('--texture-size', type=int, default=256,
                   help='square size the albedo is resized to')
    p.add_argument('--triangles', type=int, default=800,
                   help='triangle budget; the mesh is collapsed down to it')
    p.add_argument('--stand', action='store_true',
                   help='keep the asset upright instead of laying it down')
    return p.parse_args(args_after_double_dash())


def triangles_in(mesh: bpy.types.Mesh) -> int:
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


def meshes() -> list[bpy.types.Object]:
    return [o for o in bpy.data.objects if o.type == 'MESH']


def albedo_of(material: bpy.types.Material) -> bpy.types.Image | None:
    """The image feeding Base Color, followed back through whatever sits between.

    Poly Haven wires the diffuse through a Mapping/Texture Coordinate pair and
    sometimes a colour-space node, so the link off Base Color is not always the
    image node itself. Walking back up the inputs finds it wherever it is,
    rather than assuming a shape that only holds for some of the library.
    """
    if not material or not material.use_nodes:
        return None
    principled = next((n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if principled is None:
        return None
    seen: set[str] = set()
    frontier = [principled.inputs['Base Color']]
    while frontier:
        socket = frontier.pop(0)
        for link in socket.links:
            node = link.from_node
            if node.name in seen:
                continue
            seen.add(node.name)
            if node.type == 'TEX_IMAGE' and node.image is not None:
                return node.image
            frontier.extend(node.inputs)
    return None


def flatten(material: bpy.types.Material, image: bpy.types.Image) -> None:
    """Rebuilds the material as base colour and nothing else.

    Rebuilt rather than pruned: the glTF exporter reads the node graph, and a
    graph with a normal map still linked exports that map no matter what the
    renderer would have done with it. Three 1k EXRs is three megabytes the
    browser downloads to feed a shader with no input for them.
    """
    material.node_tree.nodes.clear()
    out = material.node_tree.nodes.new('ShaderNodeOutputMaterial')
    bsdf = material.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    tex = material.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = image
    material.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    material.node_tree.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])


def main() -> None:
    opts = parse()
    out = Path(opts.out).resolve()
    name = opts.name or out.stem

    objects = meshes()
    if not objects:
        raise SystemExit('the .blend holds no mesh to export')

    for o in bpy.data.objects:
        o.select_set(o.type == 'MESH')
    bpy.context.view_layer.objects.active = objects[0]

    # One mesh, because one placement in shared/data is one MeshInstance3D. An
    # asset that ships as several parts -- a dagger and its scabbard -- is one
    # thing lying on a floor, not two things to be positioned separately.
    if len(objects) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name

    if not opts.stand:
        obj.rotation_euler = (-1.5707963267948966, 0.0, 0.0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Collapse, not un-subdivide: collapse is the one decimate mode that keeps
    # the UV layout, and the whole model is one image on one map. Applied before
    # the origin is measured, because collapsing moves the outermost vertices
    # and the origin has to sit under where the mesh ends up.
    # Counted as triangles rather than as faces, because collapse triangulates
    # before it measures its own ratio: a ratio worked out against a mesh of
    # quads asks for half the reduction it looks like it is asking for.
    before = triangles_in(obj.data)
    if before > opts.triangles:
        shrink = obj.modifiers.new('budget', 'DECIMATE')
        shrink.decimate_type = 'COLLAPSE'
        shrink.ratio = opts.triangles / before
        shrink.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=shrink.name)

    # Origin on the ground under the mesh, matching the prop library. Set from
    # the bounding box rather than by the bounds-centre operator, which would
    # bury half the model under the floor.
    lowest = min((obj.matrix_world @ v.co).z for v in obj.data.vertices)
    middle = sum((obj.matrix_world @ v.co for v in obj.data.vertices),
                 start=obj.matrix_world.translation * 0.0) / len(obj.data.vertices)
    bpy.context.scene.cursor.location = (middle.x, middle.y, lowest)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    obj.location = (0.0, 0.0, 0.0)

    for slot in obj.material_slots:
        image = albedo_of(slot.material)
        if image is None:
            raise SystemExit(f'material "{slot.name}" has no image feeding Base Color')
        image.scale(opts.texture_size, opts.texture_size)
        # Packed, so the exporter embeds the resized pixels rather than
        # re-reading the 1k file off disk and shipping that instead.
        image.pack()
        flatten(slot.material, image)

    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format='GLB',
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_image_format='JPEG',
    )
    print(f'wrote {out} ({out.stat().st_size // 1024}K), {triangles_in(obj.data)} triangles '
          f'from {before}, {tuple(round(d, 4) for d in obj.dimensions)} metres')


main()
