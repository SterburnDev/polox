# Polox style guide

One page. If something on screen doesn't follow it, it's a bug. `scripts/ui/theme_builder.gd` holds the values
below, and `tests/test_soul.gd` checks the ones a test can see (palettes, type scale, themed widgets, sounds).

## The feel
Cosy, handmade, a little strange. Two worlds that are clearly the same game: the **Dream World** is a dream (deep
violet, glowing, playful) and the **Light World** is your real life (warm, quiet, lamp-lit). Nothing should look
like a settings dialog from an office program.

## Palettes
Every screen uses one of these. Accents are shared, so a yellow button means the same thing everywhere.

| Role | Dream World | Light World | The Deep |
|---|---|---|---|
| Background | `#120e24` night violet | `#1c1612` dark walnut | `#0b0a14` ink |
| Panel | `#1d1736` | `#2a201a` tea-brown | `#15132a` |
| Raised (buttons) | `#2e2552` | `#43342a` | `#232046` |
| Hover | `#3d3270` | `#5a4635` | `#302c63` |
| Text | `#f3e9d2` cream | `#f3e9d2` cream | `#f3e9d2` cream |
| Quiet text | `#b8aed6` lavender | `#d4c3ad` oat | `#a39fc9` |
| Accent (yes, chosen, focus) | `#ffd166` yolk | `#ffd166` yolk | `#ffd166` yolk |
| Love, friends | `#e86a8a` | `#e86a8a` | `#e86a8a` |
| Growth, done | `#7ad6b0` | `#7ad6b0` | `#7ad6b0` |
| Careful | `#ff7b7b` | `#ff7b7b` | `#ff7b7b` |

The world palettes follow you: walk through the Dream Gate and the panels change with the sky.

## Lines and shapes
- **Corners:** 10 px (chips, fields), 14 px (buttons, tabs, rows), 20 px (cards, toolbars, panels).
  `theme_builder.gd` RADIUS_S / RADIUS_M / RADIUS_L.
- **Buttons:** 14 px corners, a thin cream rim; pressed and chosen are yolk with dark text; disabled is flat
  and faded (no gloss), so each state differs by more than colour. Minimum 48 px tall (52 by default).
- **Bottom sheets (phones):** square bottom corners, a handle, the rim on top only.
- **Focus:** a 3 px yolk ring, never a dotted line.

## Glass
Polox's finish: a little Frutiger Aero, a little Apple. Glass is for what you *use*, not what you *read*.
- **Glass (translucent, glossy):** buttons, tabs, the title's card, toolbars and floating bars over the
  world (`ThemeBuilder.glass`, `bar`). A soft gradient sheen on the top half, a 1 px light rim along the
  top edge, an aqua glow (`#7fdcf0`) only on hover and primary actions.
- **Solid (opaque, a faint rim):** panels with text, property editors, palettes, lists, popups, tooltips
  (`ThemeBuilder.solid_panel`). Dense text never sits on glass.
- **Aqua** is the one extra accent: glows, the "more below" cue, water. Never text, never a whole panel.
- **The title** may have a watery reflection of the logo and a few slow bubbles on an aqua horizon. The logo
  and the app icon themselves never change.
- **Reduce transparency** (Settings > Accessibility) turns all glass solid and drops the sheen;
  **Reduce motion** stops the bubbles and ripples.
- No gloss on dense controls.

### Four references, four jobs (2026-11-08)
- **Frutiger Aero: the mood.** Glossy highlights, aqua and sea-green, water, nature, soft gradients, inside
  Polox's violet. The title (hills, a lake, rising bubbles, `shaders/aero_backdrop.gdshader`), the primary
  key, the creator's toolbars (`ThemeBuilder.aero_bar`, `aero_toggle`: the open mode lights up aqua).
- **Early iOS skeuomorphism: things you touch.** Keys stand on an edge and sit down when pressed
  (`ThemeBuilder.key`, `glass_box.gd depth`), switches flip with a click (`_switch_icon`, `main.gd _tactile`),
  the journal is a paper notebook with tabs, the bag a tray of sunken slots (`ThemeBuilder.well`),
  Settings > Music a stereo, the Light World has a wall light switch. Sounds: Kenney's UI Audio and a
  synthesized page turn (`synth.gd`).
- **iOS 7: screens that show a lot.** Settings and the builder's inspector (`ThemeBuilder.info_theme`):
  flat rows, hairlines, switches, more room, opaque layers. Close (or Done) is always top right.
- **iOS 26 Liquid Glass: what floats.** The world's navigation and quick actions, the phone's tab bar,
  the title's card, the Today card and phone sheets (`liquid_glass.gd`): blurred and bent background, a
  tint that follows it (darker over a bright room), a light rim. Glass on glass is fine here: each glass
  copies the screen just before it, so it sees what's really under it. Text on it stays sharp (it's drawn
  above the shader, never through it).
- Apple's interfaces are references only: everything is drawn in code for Polox.

## Pixel scale
- Characters and items are pixel art drawn at 1 texel = 1 screen pixel step at the default zoom, always with
  nearest filtering (no blur). Never scale pixel art by a non-whole factor in 2D UI; portraits use 2x, 3x or 4x.
- Symbols are a 12 x 12 grid (`symbol_font.gd`), tinted by the text colour.
- 3D blocks and furniture are flat-shaded, low-poly, with vertex colours; no textures that fight the pixel art.

## Type
The game font at these sizes only (the **type scale**): **14** fine print, **16** quiet notes, **18** body,
**20** list items, **22** buttons and default, **26** screen titles, **32** big titles, **46 / 56 / 72** moments
(the Survey, the title, a first look). One weight; emphasis is colour (yolk), not bold.

## Icons
One symbol before a word, never a row of emoji. Symbols come from the 12 x 12 set: ♥ friends, ☰ menu, 🗺 world,
📦 bag, 🛠 build, ✦ something special, ☀ the Light World, 🌙 the Dream World, ⚠ careful. A symbol never replaces a word on
a main button.

## Words
- Polox talks like a friend who lives in your house: short, warm, a bit playful. "Your room's ready." not
  "Room generation complete."
- Half the words you'd first write. One line for a hint; details one tap away.
- Say what happens, not how it works. Show it (a preview, a picture) rather than explain it.
- Never blame, never nag, no exclamation marks in errors.
- Each friend has their own voice (gentle, bubbly, calm, grumpy, and travellers' mysterious one).

## Motion
Short (under half a second), interruptible, and a quick fade under Reduce motion (`anim_fx.gd`). Big moments
(the first look at your home, your street, the Dream Gate, coming home after a battle) are little scenes: a light
change, a motif, a skip hint.

## Sound
- **UI:** a soft click for buttons, a pop for placing, a chime for good news. Quiet (-14 dB under the world).
- **Footsteps** by what's underfoot: wood, stone, grass, carpet (soft), water, metal.
- **Ambience** per world: the Light World's house and street (day and night), the Dream World's hum, the Deep's
  low drone.
- **Motifs** (a few notes, the same intervals in different clothes): the title, home in the Light World, the
  Dream World, battles.
