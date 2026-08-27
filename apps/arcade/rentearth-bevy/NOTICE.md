# Third-party notices

## Realistic Water Shader

Parts of the water surface -- the Gerstner wave formulation, the Beer's-law
depth blend, and the normal, UV-distortion and foam textures -- derive from the
Realistic Water Shader for Godot.

    Copyright (c) 2019 UnionBytes, Achim Menzel (alias AiYori)
    Copyright (c) 2019 Realistic Water Shader Contributors

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

Source: https://github.com/godot-extended-libraries/godot-realistic-water

This notice is public on purpose. The shader and textures themselves live under
`src/private/`, which is git-crypt encrypted, but MIT requires the notice to
travel with any distribution -- encrypting the source does not lift that, and a
notice nobody can read would not discharge it.

## Natural Earth

`src/game/core/earth_mask.txt` is rasterised from Natural Earth's 10m land
polygons, which are public domain (CC0).

Source: https://github.com/nvkelso/natural-earth-vector
