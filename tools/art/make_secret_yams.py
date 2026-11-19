"""Draws the public pictures for the Music secret (assets/secret/yam_*.svg).

Original artwork for Polox, made by this script and nothing else: no photograph, font or outside
picture goes in, so every public copy of the game may ship them. A private copy can list its own
pictures in assets/local/addon.json ("secret_images"); scripts/ui/secret_pictures.gd picks the set.

    python tools/art/make_secret_yams.py            writes the eight SVGs
    python tools/art/make_secret_yams.py --check    exits 1 if a committed SVG differs from what this draws

The drawings only use what Godot's SVG importer (ThorVG) renders: paths, ellipses, circles, rounded
rectangles, and linear and radial gradients. No text, filters, masks or <use>.
"""

import argparse
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "secret")
W, H = 1280, 720

PURPLE = ("#b784d6", "#7a479c", "#4a2466")
ORANGE = ("#ffb877", "#e07a34", "#9a4514")
ROSE = ("#ff9fc0", "#d9507f", "#8a2148")
GOLD = ("#ffe08a", "#e0a52c", "#96640c")


class Picture:
    """Collects gradient definitions and shapes, then writes one SVG file."""

    def __init__(self):
        self.defs = []
        self.shapes = []
        self._ids = 0

    def _new_id(self, prefix):
        self._ids += 1
        return "%s%d" % (prefix, self._ids)

    def linear(self, stops, x1=0, y1=0, x2=0, y2=1):
        gid = self._new_id("l")
        self.defs.append('<linearGradient id="%s" x1="%g" y1="%g" x2="%g" y2="%g">%s</linearGradient>'
                         % (gid, x1, y1, x2, y2, _stops(stops)))
        return "url(#%s)" % gid

    def radial(self, stops, cx=0.5, cy=0.5, r=0.5):
        gid = self._new_id("r")
        self.defs.append('<radialGradient id="%s" cx="%g" cy="%g" r="%g">%s</radialGradient>'
                         % (gid, cx, cy, r, _stops(stops)))
        return "url(#%s)" % gid

    def add(self, shape):
        self.shapes.append(shape)

    def write(self, name):
        body = "\n".join(self.shapes)
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n'
               '<defs>\n%s\n</defs>\n%s\n</svg>\n' % (W, H, W, H, "\n".join(self.defs), body))
        return name, svg


def _stops(stops):
    out = []
    for stop in stops:
        offset, colour = stop[0], stop[1]
        opacity = stop[2] if len(stop) > 2 else 1
        out.append('<stop offset="%g" stop-color="%s" stop-opacity="%g"/>' % (offset, colour, opacity))
    return "".join(out)


def ellipse(cx, cy, rx, ry, fill, opacity=1.0, rotate=0.0):
    turn = ' transform="rotate(%g %g %g)"' % (rotate, cx, cy) if rotate else ""
    return '<ellipse cx="%g" cy="%g" rx="%g" ry="%g" fill="%s" opacity="%g"%s/>' % (cx, cy, rx, ry, fill, opacity, turn)


def path(d, fill, opacity=1.0, stroke="none", width=0.0):
    return '<path d="%s" fill="%s" opacity="%g" stroke="%s" stroke-width="%g" stroke-linecap="round"/>' % (
        d, fill, opacity, stroke, width)


def rect(x, y, w, h, fill, radius=0.0, opacity=1.0):
    return '<rect x="%g" y="%g" width="%g" height="%g" rx="%g" fill="%s" opacity="%g"/>' % (x, y, w, h, radius, fill, opacity)


# --- Backdrops ---------------------------------------------------------------------------------------

def sky(pic, top, middle, bottom):
    pic.add(rect(0, 0, W, H, pic.linear([(0, top), (0.55, middle), (1, bottom)])))


def sun_glow(pic, cx, cy, radius, colour="#ffffff"):
    pic.add(ellipse(cx, cy, radius, radius, pic.radial([(0, colour, 0.95), (0.35, colour, 0.45), (1, colour, 0)])))


def hill(pic, baseline, height, shift, light, dark, gloss=0.35):
    """A glossy rolling hill across the whole picture (the title screen's hills, drawn flat)."""
    left, right = -80, W + 80
    top = baseline - height
    d = "M%g %g C%g %g %g %g %g %g S%g %g %g %g L%g %g L%g %g Z" % (
        left, baseline, W * 0.18 + shift, top - height * 0.35, W * 0.42 + shift, top + height * 0.1,
        W * 0.6 + shift, baseline - height * 0.55, W * 0.95 + shift, top - height * 0.1, right, baseline - height * 0.3,
        right, H + 40, left, H + 40)
    pic.add(path(d, pic.linear([(0, light), (1, dark)])))
    sheen = "M%g %g C%g %g %g %g %g %g" % (
        W * 0.08 + shift, baseline - height * 0.55, W * 0.2 + shift, top - height * 0.25,
        W * 0.36 + shift, top + height * 0.02, W * 0.5 + shift, baseline - height * 0.62)
    pic.add(path(sheen, "none", gloss, "#ffffff", 10))


def lake(pic, top):
    pic.add(rect(0, top, W, H - top, pic.linear([(0, "#bff3ff"), (0.4, "#5cc8ec"), (1, "#1c7fb8")])))
    for i in range(7):
        y = top + 26 + i * 34
        x = 90 + (i * 173) % 900
        pic.add(ellipse(x, y, 120 - i * 9, 5, "#ffffff", 0.38))


def bubble(pic, cx, cy, r, tint="#ffffff", strength=1.0):
    pic.add(ellipse(cx, cy, r, r, pic.radial([(0, tint, 0.05 * strength), (0.72, tint, 0.14 * strength),
                                              (0.93, "#ffffff", 0.6 * strength), (1, "#ffffff", 0.15 * strength)])))
    pic.add(ellipse(cx - r * 0.36, cy - r * 0.42, r * 0.3, r * 0.17, "#ffffff", 0.75 * strength, -32))
    pic.add(ellipse(cx + r * 0.42, cy + r * 0.46, r * 0.1, r * 0.06, "#ffffff", 0.5 * strength, -32))


def stars(pic, seed, count):
    rng = random.Random(seed)
    for _ in range(count):
        x, y, r = rng.uniform(20, W - 20), rng.uniform(15, H * 0.62), rng.uniform(1.2, 3.4)
        pic.add(ellipse(x, y, r, r, "#ffffff", rng.uniform(0.45, 1.0)))


# --- The yam -----------------------------------------------------------------------------------------

def yam(pic, cx, cy, size, colours=PURPLE, tilt=0.0, look=(0.6, 0.1), eyes=True, shades=False, sprout=False,
        shadow=True):
    """One yam: a plump tuber with tapered ends, a glossy highlight and (the point of the joke) eyes.

    cx, cy   the middle of the body, in picture pixels
    size     half its length
    look     where the pupils sit inside each eye, -1..1 on both axes
    """
    light, mid, dark = colours
    half_len, half_wid = size, size * 0.56
    if shadow:
        pic.add(ellipse(cx, cy + half_wid * 1.02, half_len * 0.86, half_wid * 0.2, "#0b1e33", 0.26))
    group = '<g transform="rotate(%g %g %g)">' % (tilt, cx, cy)
    pic.add(group)
    x0, x1 = cx - half_len, cx + half_len
    body = ("M%g %g C%g %g %g %g %g %g C%g %g %g %g %g %g C%g %g %g %g %g %g C%g %g %g %g %g %g Z" % (
        x0, cy + half_wid * 0.05,
        x0 + half_len * 0.1, cy - half_wid * 0.75, cx - half_len * 0.55, cy - half_wid * 1.05, cx - half_len * 0.05, cy - half_wid * 0.98,
        cx + half_len * 0.5, cy - half_wid * 0.92, x1 - half_len * 0.16, cy - half_wid * 0.62, x1, cy - half_wid * 0.02,
        x1 - half_len * 0.12, cy + half_wid * 0.66, cx + half_len * 0.48, cy + half_wid * 1.04, cx - half_len * 0.02, cy + half_wid * 1.0,
        cx - half_len * 0.6, cy + half_wid * 0.96, x0 + half_len * 0.08, cy + half_wid * 0.7, x0, cy + half_wid * 0.05))
    pic.add(path(body, pic.linear([(0, light), (0.5, mid), (1, dark)])))
    # The skin's little marks, then the gloss on top of them.
    for along, down, length in ((-0.5, 0.42, 0.12), (-0.12, 0.6, 0.16), (0.34, 0.5, 0.1), (0.58, 0.18, 0.08), (-0.66, -0.05, 0.07)):
        mx, my = cx + half_len * along, cy + half_wid * down
        pic.add(path("M%g %g q%g %g %g 0" % (mx, my, half_len * length * 0.5, half_wid * 0.08, half_len * length),
                     "none", 0.34, dark, max(2.0, size * 0.022)))
    pic.add(ellipse(cx - half_len * 0.18, cy - half_wid * 0.58, half_len * 0.56, half_wid * 0.24,
                    pic.linear([(0, "#ffffff", 0.78), (1, "#ffffff", 0.04)]), 1.0, -4))
    pic.add(ellipse(cx + half_len * 0.56, cy - half_wid * 0.36, half_len * 0.09, half_wid * 0.09, "#ffffff", 0.55))
    # Root hairs at the tapered ends.
    for end, direction in ((x0, -1), (x1, 1)):
        pic.add(path("M%g %g q%g %g %g %g" % (end, cy, direction * size * 0.1, -size * 0.07, direction * size * 0.17, -size * 0.02),
                     "none", 0.9, dark, max(2.0, size * 0.03)))
    if sprout:
        _sprout(pic, cx - half_len * 0.1, cy - half_wid * 0.96, size)
    if eyes:
        _eyes(pic, cx + half_len * 0.12, cy - half_wid * 0.12, size, look, shades)
    pic.add("</g>")


def _eyes(pic, cx, cy, size, look, shades):
    eye_rx, eye_ry, gap = size * 0.15, size * 0.19, size * 0.19
    if shades:
        bar = size * 0.03
        for side in (-1, 1):
            pic.add(rect(cx + side * gap - eye_rx * 1.15, cy - eye_ry * 0.75, eye_rx * 2.3, eye_ry * 1.5,
                         pic.linear([(0, "#3a4a66"), (1, "#0c1220")]), eye_rx * 0.5))
            pic.add(ellipse(cx + side * gap - eye_rx * 0.4, cy - eye_ry * 0.3, eye_rx * 0.42, eye_ry * 0.16, "#ffffff", 0.6, -20))
        pic.add(rect(cx - gap * 0.5, cy - eye_ry * 0.42, gap, bar, "#0c1220"))
        return
    for side in (-1, 1):
        ex = cx + side * gap
        pic.add(ellipse(ex, cy + eye_ry * 0.08, eye_rx * 1.08, eye_ry * 1.08, "#2b1240", 0.35))
        pic.add(ellipse(ex, cy, eye_rx, eye_ry, pic.linear([(0, "#ffffff"), (1, "#dfe9f5")])))
        px, py = ex + look[0] * eye_rx * 0.46, cy + look[1] * eye_ry * 0.42
        pic.add(ellipse(px, py, eye_rx * 0.52, eye_ry * 0.52, "#1a1326"))
        pic.add(ellipse(px - eye_rx * 0.16, py - eye_ry * 0.2, eye_rx * 0.17, eye_ry * 0.15, "#ffffff", 0.95))


def _sprout(pic, x, y, size):
    stem = "M%g %g q%g %g %g %g" % (x, y, -size * 0.02, -size * 0.2, size * 0.05, -size * 0.34)
    pic.add(path(stem, "none", 1.0, "#3f9a3c", max(3.0, size * 0.045)))
    for side in (-1, 1):
        lx, ly = x + size * 0.05, y - size * 0.34
        leaf = "M%g %g q%g %g %g %g q%g %g %g %g Z" % (
            lx, ly, side * size * 0.16, -size * 0.2, side * size * 0.32, -size * 0.06,
            -side * size * 0.14, size * 0.14, -side * size * 0.32, size * 0.06)
        pic.add(path(leaf, pic.linear([(0, "#b9f277"), (1, "#3f9a3c")])))


# --- The eight pictures ------------------------------------------------------------------------------

def hello():
    pic = Picture()
    sky(pic, "#4fb6f2", "#aee6ff", "#f2fdff")
    sun_glow(pic, 1010, 150, 260)
    hill(pic, 560, 150, 60, "#c5f58a", "#4fb04a")
    hill(pic, 660, 120, -160, "#a8ee6c", "#2f9440")
    for cx, cy, r in ((170, 190, 46), (300, 110, 22), (1130, 420, 34), (960, 520, 18)):
        bubble(pic, cx, cy, r)
    yam(pic, 600, 430, 250, PURPLE, -8, (0.75, 0.05))
    return pic.write("yam_01_hello")


def family():
    pic = Picture()
    sky(pic, "#62c7f5", "#c2f0ff", "#fdfff2")
    sun_glow(pic, 240, 130, 220, "#fff7c9")
    hill(pic, 600, 130, -40, "#d1f79a", "#5cb84e")
    hill(pic, 690, 90, 220, "#aef070", "#36a046")
    yam(pic, 370, 470, 210, ORANGE, -5, (0.7, 0.2))
    yam(pic, 790, 500, 150, PURPLE, 7, (-0.7, 0.1))
    yam(pic, 1020, 560, 86, ROSE, -10, (-0.8, -0.3), sprout=True)
    bubble(pic, 1120, 170, 52)
    bubble(pic, 640, 130, 24)
    return pic.write("yam_02_family")


def afloat():
    pic = Picture()
    sky(pic, "#3fa8ee", "#9fe0ff", "#dff8ff")
    sun_glow(pic, 900, 110, 240)
    hill(pic, 470, 90, 120, "#baf283", "#48aa4a", 0.25)
    lake(pic, 470)
    yam(pic, 640, 300, 150, GOLD, -14, (0.1, 0.75), shadow=False)
    bubble(pic, 640, 300, 235, "#bdf3ff", 1.35)
    for cx, cy, r in ((210, 250, 40), (330, 400, 20), (1080, 330, 58), (1010, 180, 16), (140, 520, 26)):
        bubble(pic, cx, cy, r)
    pic.add(ellipse(640, 610, 190, 16, "#0b3c5c", 0.22))
    return pic.write("yam_03_afloat")


def moonlight():
    pic = Picture()
    sky(pic, "#0c1440", "#28337a", "#5a4f9c")
    stars(pic, 7, 90)
    sun_glow(pic, 1010, 170, 300, "#cfd9ff")
    pic.add(ellipse(1010, 170, 92, 92, pic.radial([(0, "#ffffff"), (0.7, "#eef2ff"), (1, "#c6cef5")], 0.4, 0.4, 0.7)))
    pic.add(ellipse(980, 150, 16, 12, "#aab4e6", 0.5))
    pic.add(ellipse(1040, 200, 22, 17, "#aab4e6", 0.4))
    hill(pic, 590, 120, 0, "#3f6fae", "#1a2f66", 0.22)
    hill(pic, 680, 100, -220, "#2f5c9a", "#122552", 0.18)
    yam(pic, 520, 480, 220, PURPLE, 5, (0.8, -0.55))
    return pic.write("yam_04_moonlight")


def tower():
    pic = Picture()
    sky(pic, "#57bdf4", "#b9ecff", "#f7fff0")
    sun_glow(pic, 180, 120, 230, "#fff7c9")
    hill(pic, 640, 110, 100, "#c8f690", "#4db14b")
    yam(pic, 640, 560, 210, ORANGE, 0, (0.0, -0.7))
    yam(pic, 655, 372, 160, PURPLE, -6, (0.5, -0.6), shadow=False)
    yam(pic, 630, 225, 112, ROSE, 9, (-0.4, 0.75), shadow=False, sprout=True)
    for cx, cy, r in ((1050, 230, 54), (1140, 390, 26), (260, 330, 34)):
        bubble(pic, cx, cy, r)
    return pic.write("yam_05_tower")


def peek():
    pic = Picture()
    sky(pic, "#49b2f0", "#a7e4ff", "#effcff")
    sun_glow(pic, 640, 90, 300)
    for cx, cy, r in ((220, 170, 60), (1060, 220, 44), (900, 90, 20), (380, 60, 18)):
        bubble(pic, cx, cy, r)
    # A very large yam rising from behind the nearest hill: mostly eyes.
    yam(pic, 640, 690, 520, PURPLE, 0, (0.0, -0.8), shadow=False)
    hill(pic, 790, 110, -60, "#b4f078", "#3aa344")
    return pic.write("yam_06_peek")


def seaside():
    pic = Picture()
    sky(pic, "#35a6ee", "#8fdcff", "#e5faff")
    sun_glow(pic, 1040, 140, 280, "#fff2a8")
    lake(pic, 390)
    sand = "M-40 560 C260 500 520 520 760 545 S1180 600 1320 540 L1320 760 L-40 760 Z"
    pic.add(path(sand, pic.linear([(0, "#fff0c2"), (1, "#f0c878")])))
    pic.add(path("M60 548 C300 505 520 524 700 544", "none", 0.5, "#ffffff", 8))
    yam(pic, 560, 520, 235, ORANGE, -9, (0, 0), shades=True)
    # A beach ball, to keep it company.
    pic.add(ellipse(1010, 610, 70, 70, pic.radial([(0, "#ffffff"), (0.6, "#ff8fb3"), (1, "#d1426f")], 0.35, 0.3, 0.8)))
    pic.add(path("M1010 540 C975 585 975 635 1010 680", "none", 0.85, "#ffffff", 9))
    pic.add(ellipse(986, 578, 20, 11, "#ffffff", 0.75, -30))
    return pic.write("yam_07_seaside")


def garden():
    pic = Picture()
    sky(pic, "#5cc3f5", "#c0efff", "#fbfff0")
    sun_glow(pic, 300, 120, 240, "#fff7c9")
    hill(pic, 520, 120, 80, "#cbf792", "#55b54c")
    soil = "M-40 600 C300 560 700 570 1320 600 L1320 760 L-40 760 Z"
    for x, size, colours, look_at in ((230, 120, PURPLE, (0.8, 0.2)), (500, 150, ORANGE, (0.2, -0.6)),
                                      (800, 135, ROSE, (-0.5, 0.3)), (1060, 110, GOLD, (-0.8, -0.2))):
        yam(pic, x, 548, size, colours, 0, look_at, sprout=True, shadow=False)
    pic.add(path(soil, pic.linear([(0, "#9a6a3c"), (1, "#5a3718")])))
    pic.add(path("M0 606 C320 572 700 580 1280 606", "none", 0.3, "#ffffff", 6))
    bubble(pic, 1100, 200, 48)
    bubble(pic, 940, 110, 22)
    return pic.write("yam_08_garden")


def vault_aero():
    """Public fallback vault art for typing 'aero': glossy aqua crystal sky and floating orb yam."""
    pic = Picture()
    sky(pic, "#0d74c8", "#4fd2f5", "#e2fff9")
    sun_glow(pic, 980, 140, 320, "#ffffff")
    hill(pic, 560, 150, 40, "#b8ff7a", "#2ca64b", 0.5)
    lake(pic, 520)
    # Glossy glass ribbon sweeping across the sky
    pic.add(path("M-60 280 C280 120 620 420 1340 160", "none", 0.55, "#c4fbff", 28))
    pic.add(path("M-60 305 C280 145 620 445 1340 185", "none", 0.3, "#ffffff", 10))
    for cx, cy, r in ((210, 190, 74), (350, 340, 38), (940, 310, 62), (1120, 210, 44), (1070, 470, 28)):
        bubble(pic, cx, cy, r, "#7ff5ff", 1.25)
    yam(pic, 640, 360, 200, PURPLE, -11, (0.4, -0.3), sprout=True, shadow=False)
    bubble(pic, 640, 360, 265, "#9ff8ff", 1.35)
    return pic.write("vault_aero")


def vault_frutiger():
    """Public fallback vault art for typing 'frutiger': iridescent meadow, prism arcs and sunglasses yam."""
    pic = Picture()
    sky(pic, "#259ef2", "#8be8ff", "#f2ffec")
    sun_glow(pic, 240, 130, 300, "#fffad1")
    # Translucent glossy prism arcs
    for radius, col in ((560, "#7df5ff"), (500, "#99ff9e"), (440, "#fff08a")):
        pic.add(path("M%g 640 A%g %g 0 0 1 %g 640" % (640 - radius, radius, radius, 640 + radius), "none", 0.28, col, 24))
    hill(pic, 540, 160, -80, "#ceff80", "#3cb04a", 0.45)
    hill(pic, 650, 110, 180, "#99f56e", "#208c45", 0.4)
    for cx, cy, r in ((180, 320, 56), (410, 160, 32), (890, 170, 50), (1100, 330, 68), (990, 500, 26)):
        bubble(pic, cx, cy, r, "#c4ffea", 1.2)
    yam(pic, 640, 445, 225, GOLD, 6, (0.0, 0.0), shades=True, sprout=True)
    return pic.write("vault_frutiger")


def vault_code():
    """Public fallback vault art for typing 'code': midnight phosphor grid and coder yam."""
    pic = Picture()
    sky(pic, "#060b16", "#0b1a2e", "#092638")
    # Perspective terminal grid lines
    for y in range(40, H, 48):
        pic.add(rect(0, y, W, 2, "#1ef0b8", 0, 0.14))
    for x in range(40, W, 64):
        pic.add(rect(x, 0, 2, H, "#1ef0b8", 0, 0.11))
    # Decorative phosphor code bars (no text elements so ThorVG stays 100% consistent)
    bars = [
        (90, 95, 220, "#4fffc8"), (90, 130, 150, "#66d2ff"), (120, 165, 290, "#ffe082"),
        (90, 200, 180, "#ff87b2"), (940, 95, 240, "#66d2ff"), (980, 130, 160, "#4fffc8"),
        (920, 165, 260, "#c89eff"), (960, 200, 190, "#4fffc8"),
    ]
    for bx, by, bw, col in bars:
        pic.add(rect(bx, by, bw, 16, col, 8, 0.55))
    sun_glow(pic, 640, 390, 320, "#2ef5c8")
    yam(pic, 640, 400, 235, ROSE, -5, (0.0, -0.2), shades=True)
    bubble(pic, 640, 400, 295, "#4fffc8", 0.65)
    return pic.write("vault_code")


def vault_rot():
    """Public fallback vault art for typing 'rot': chaotic hypnotic yam vortex."""
    pic = Picture()
    sky(pic, "#2d0740", "#7d1658", "#ff6633")
    for idx, (r, col) in enumerate(((520, "#ff4d94"), (410, "#ffd24d"), (310, "#59ff9e"), (220, "#5cd6ff"), (140, "#c266ff"))):
        pic.add(ellipse(640, 360, r * 1.25, r * 0.72, col, 0.26, idx * 14 - 20))
    stars(pic, 42, 110)
    yam(pic, 330, 300, 165, ORANGE, -28, (0.9, 0.4), shadow=False)
    yam(pic, 950, 310, 165, GOLD, 26, (-0.9, 0.4), shadow=False)
    yam(pic, 640, 445, 245, PURPLE, 4, (0.0, -0.85), sprout=True)
    for cx, cy, r in ((200, 560, 42), (1080, 560, 48), (640, 120, 36)):
        bubble(pic, cx, cy, r, "#ff99dd", 1.1)
    return pic.write("vault_rot")


PICTURES = (hello, family, afloat, moonlight, tower, peek, seaside, garden,
            vault_aero, vault_frutiger, vault_code, vault_rot)


def main():
    parser = argparse.ArgumentParser(description="Draw the public Music-secret pictures.")
    parser.add_argument("--check", action="store_true", help="compare with the committed files instead of writing")
    parser.add_argument("--out", default=OUT, help="another folder to write to (for a preview)")
    args = parser.parse_args()
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    stale = []
    for draw in PICTURES:
        name, svg = draw()
        target = os.path.join(out, name + ".svg")
        if args.check:
            current = open(target, encoding="utf-8").read() if os.path.exists(target) else ""
            if current.replace("\r\n", "\n") != svg:
                stale.append(name)
            continue
        with open(target, "w", encoding="utf-8", newline="\n") as f:
            f.write(svg)
        print("wrote %s" % os.path.relpath(target, ROOT).replace(os.sep, "/"))
    if stale:
        print("out of date: " + ", ".join(stale))
        sys.exit(1)


if __name__ == "__main__":
    main()
