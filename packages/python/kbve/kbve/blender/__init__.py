"""Blender-python toolchain for KBVE game assets.

Runs inside Blender's bundled Python (``bpy``), launched via the thin venv
wrappers in :mod:`kbve.blender.cli`. Current tools:

- ``retarget`` -- headless Rokoko retarget from a Mesh2Motion source rig onto a
  Synty SIDEKICK target rig (correctly resolves the A-pose <-> T-pose rest
  difference; needs the Rokoko addon in the launching Blender).
- ``vat`` -- bakes a looping skinned animation to a vertex animation texture.
- ``turf`` -- bakes a tiling turf surface down to flat maps for the ground
  shader's parallax pass.

:mod:`kbve.blender.pack_orm` is the exception: it packs two baked maps into the
ORM layout with Pillow and never enters Blender, so it needs the ``blender``
extra rather than a Blender install.
"""
