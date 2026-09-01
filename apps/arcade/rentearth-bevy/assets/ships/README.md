# How `pinnace.png` is made

The sheet is baked from Poly Haven's Ship Pinnace with `kbve-model-sprites`
(`packages/python/kbve/kbve/blender/model_sprites.py`). The source `.blend` is
not in this repository -- see `NOTICE.md`.

The exact command was written down nowhere, which meant the asset could not be
reproduced: the numbers that survive in `pinnace.json` describe the camera, and
say nothing about the light or the foam. Recovering them took a calibration
sweep against the shipped pixels. Hence this file.

    blender -b ship_pinnace_1k.blend -P model_sprites.py -- \
        --model ship_pinnace_1k.blend --out ships/pinnace \
        --keep-materials --exclude 'wdg_*,hlp_*' \
        --frames 32 --res 512 --elev 41.25 --pitch 0 --clip-below 1.2 \
        --no-shadow --foam \
        --ambient 0.65 --ambient-color 0.85,0.78,0.66

`--no-shadow` matters and is not the default: the baked ground shadow is a wide
soft ellipse, and a ship carries its own foam instead. `--ambient` is what makes
the hull read at map zoom rather than going to silhouette on the side away from
the sun; the warm ambient colour is a departure from the default, which is blue.

Verified by re-baking against the shipped sheet: `frame_world_size`,
`origin_frame_fraction` and `waterline_frame_fraction` come out identical, and
the solid silhouette matches to seven pixels in five hundred thousand.

## The two poses

The model's default is a ship at anchor: canvas rolled along the yards. That is
`pinnace.png`, and it is what this game drew for a long time without anyone
saying which pose it was.

Sails set is a second bake of the same ship with the rig hauled:

    --bone-move 'ctrl_*_up:0,1.2,0'

The asset switches poses by driver, not by a hidden object. Each sail has a
pair of control bones and a driver compares the distance between them against
1.137: closer than that shows the canvas rolled up, further apart shows it
drawing. Un-hiding the meshes achieves nothing, because the driver puts the
flag straight back on the next depsgraph update -- and the geometry for the set
sails is parked below the waterline until the control moves it, where
`--clip-below` throws it away for good measure. Move the control.

`--bone-move` runs before the visibility filter for the same reason. A driven
variant is hidden until its control says otherwise, and the filter drops hidden
meshes -- so posing afterwards moves the controls of a ship whose other set of
sails has already been deleted.

## The sail masks

`--mask-material ship_pinnace_sails` bakes a coverage mask of just the canvas,
for tinting sails by side without guessing which pixels those are from
brightness. It aligns with the beauty pass to the pixel and respects occlusion,
so a mast in front of a sail punches a hole in the mask.

One per pose, baked with the same flags as its own beauty pass and without
`--foam` or the shadow, which are not part of the model. Canvas is about a
sixth of a moored ship and three quarters of one under sail, which is most of
why the two poses read apart at a glance.
