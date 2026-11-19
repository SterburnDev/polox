# Blender (background): Poly Haven's CC0 sky panorama -> Polox's reflection sky (smaller Radiance HDR).
#   blender -b --factory-startup --python tools/blender_scripts/prepare_sky.py -- <in.hdr> <out.hdr> <width>
import bpy, sys

src, out, width = sys.argv[sys.argv.index("--") + 1:]
width = int(width)
img = bpy.data.images.load(src)
img.scale(width, width // 2)
img.filepath_raw = out
img.file_format = "HDR"
img.save()
print("sky", img.size[0], img.size[1])
