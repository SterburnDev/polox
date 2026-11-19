# Polox's boot splash from the logo: a square transparent canvas with the logo centred at 70% width.
# blender -b --factory-startup --python tools/blender_scripts/make_splash.py -- <logo.png> <splash.png>
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
src_path, out_path = args[0], args[1]
SIDE = 1024
LOGO_W = 720

src = bpy.data.images.load(src_path)
w, h = src.size
logo_h = max(1, round(h * LOGO_W / w))
src.scale(LOGO_W, logo_h)
logo = list(src.pixels)   # RGBA floats, rows from the bottom

canvas = [0.0] * (SIDE * SIDE * 4)
x0 = (SIDE - LOGO_W) // 2
y0 = (SIDE - logo_h) // 2
for row in range(logo_h):
    a = row * LOGO_W * 4
    b = ((y0 + row) * SIDE + x0) * 4
    canvas[b:b + LOGO_W * 4] = logo[a:a + LOGO_W * 4]

out = bpy.data.images.new("polox_splash", SIDE, SIDE, alpha=True)
out.pixels = canvas
out.filepath_raw = out_path
out.file_format = "PNG"
out.save()
print("splash", out_path, LOGO_W, "x", logo_h, "on", SIDE)
