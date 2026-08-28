"""Blender-python toolchain for KBVE game assets.

Two kinds of module live here, and the split is what the layout is for.

The bakers -- ``retarget``, ``vat_bake``, ``turf_bake``, ``model_sprites`` --
import ``bpy`` at module scope and only run inside Blender. Each is launched by
a thin wrapper in :mod:`kbve.blender.cli`, which resolves a Blender binary and
re-runs the module through ``blender -b -P <module> -- <args>``:

- ``retarget`` -- headless Rokoko retarget from a Mesh2Motion source rig onto a
  Synty SIDEKICK target rig (correctly resolves the A-pose <-> T-pose rest
  difference; needs the Rokoko addon in the launching Blender).
- ``vat`` -- bakes a looping skinned animation to a vertex animation texture.
- ``turf`` -- bakes a tiling turf surface down to flat maps for the ground
  shader's parallax pass.
- ``model-sprites`` -- renders a model to a sheet of facing sprites.

The rest never enter Blender. ``pack_orm``, ``sprite_postprocess`` and
``skin_variant`` are Pillow and numpy image passes that sit either side of a
bake, which is why the ``blender`` extra installs image libraries for a package
whose bakers need none: Blender brings its own interpreter, and these do not
run in it.

That is also why model_sprites and sprite_postprocess are siblings rather than
neighbours in separate packages. The baker shells out to the post-process step
by looking for it as a file beside itself -- Blender's bundled python usually
lacks Pillow, so it hands off to the system python3 -- and moving either one
alone would break that handoff silently, leaving frames written and the sheet
never stitched.
"""
