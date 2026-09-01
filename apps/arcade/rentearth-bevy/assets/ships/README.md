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

## The sails, and what cannot be masked

`--mask-material ship_pinnace_sails` bakes a coverage mask of just the canvas,
for tinting sails by side without guessing which pixels those are from
brightness. It aligns with the beauty pass to the pixel and respects occlusion,
so a mast in front of a sail punches a hole in the mask.

There is no furled pose to pair it with, and this is a property of the model
rather than of the baker. The asset carries `*_top` and `*_down` variants of
every sail and the `_down` half is switched off, which looks like set-versus-
furled and is not: rendered on their own the `_down` sail objects come out
completely transparent. Selecting them gives a ship under bare poles, and the
extra geometry that appears is not stowed canvas -- it is the masts and rigging
that the sails had been hiding.

So a moored pose is available and it has nothing on it to colour.
