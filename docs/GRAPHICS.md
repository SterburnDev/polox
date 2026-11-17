# Graphics: what each setting does, and what it costs

## How Polox draws

- **The worlds are 3D** (Forward+ on a PC; Compatibility on phones and in the browser). Characters
  and items are pixel-art sprites standing in the 3D rooms, so the lighting work lands on the 3D
  surfaces, furniture and lamps, and the sprites stay crisp and readable.
- **Menus, editors and battles are 2D** (Controls drawn over the world). Battles stay flat and
  high-contrast on purpose: the bullets and the Soul must always read first. Their Presentation
  (backdrop and effects) is drawn quietly under the arena.
- Rooms are editable at any time, so the lighting is **all real-time**. Nothing is baked: global light
  (SDFGI) follows what you place, live.

## Settings (Settings > Display)

| Setting | Where | What it changes |
| --- | --- | --- |
| Graphics: Automatic / High / Balanced / Battery saver | Every device | Shadows, glow and colour grading; Battery saver drops shadows and effects |
| PC graphics: Auto / High / Ultra / Off | PCs | The preset for the features below (Auto is High and steps down if frames stay slow) |
| Lighting: Basic / Soft / Global | Fine-tune | Soft adds SSAO contact shading and SSIL bounce light; Global adds SDFGI (light bounces off what you place) |
| Shadows: Low / Medium / High / Ultra | Fine-tune | Sun splits (2 or 4), atlas size, soft-shadow filter; Ultra lets the 4 lamps nearest the camera cast soft shadows |
| Reflections: Off / Under the sky / Everywhere | Fine-tune | Screen-space reflections, outdoors only or everywhere |
| Atmosphere: Clear / Mist outdoors / Light shafts | Fine-tune | Volumetric fog: the Dream World's mist, or a faint haze lamps and the sun light up |
| Textures: Standard / Sharp / Sharpest / Detailed | Fine-tune | Anisotropic filtering 4x/8x/16x; Detailed also uses the optional Detailed pack |
| Model detail: Light / Normal / Full | Fine-tune | How soon distant models switch to simpler versions (mesh LOD threshold) |
| Render resolution: 50 to 100% | Fine-tune | The 3D world's pixel count; below 100% FSR 2 sharpens it. Previewed for 10 s, then it goes back unless you keep it |

Nothing here needs a restart. Worlds don't store graphics choices, so a world looks right on every
device. **Measure this scene** (under the presets) times the world behind Settings for 4 seconds.

## Measured (7 November 2026)

**PC:** Intel Arc B580 (Vulkan 1.4), AMD Ryzen 7 5800XT (8 cores, 16 threads), Windows 11, Forward+,
1920×1080 window, V-Sync off. **Scenes:** the player's own world (a copy of the save), the outdoor
Garden at night, and the same room in the builder with Advanced and the minimap open (the busiest
editor screen). Each was measured over 5 seconds after 2.5 seconds to settle. "Memory" is Godot's
static memory; "video" is VRAM in use. Another copy of Polox ran in the background, capped at 30 fps.

| Scene | Preset | FPS | Frame time | Slowest 5% | Memory | Video memory |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| World | Off | 746 | 1.3 ms | 1.4 ms | 153 MB | 340 MB |
| World | High | 439 | 2.3 ms | 2.2 ms | 153 MB | 444 MB |
| World | Ultra (+ SDFGI, 4 sun splits) | 267 | 3.7 ms | 3.6 ms | 153 MB | 815 MB |
| World | Ultra, every feature at its highest | 201 | 5.0 ms | 20.2 ms | 153 MB | 951 MB |
| World | Ultra at 75% resolution | 270 | 3.7 ms | 3.5 ms | 154 MB | 859 MB |
| Builder | Off | 720 | 1.4 ms | 1.6 ms | 163 MB | 346 MB |
| Builder | High | 426 | 2.3 ms | 2.2 ms | 163 MB | 449 MB |
| Builder | Ultra | 253 | 4.0 ms | 3.8 ms | 163 MB | 820 MB |
| Builder | Ultra, every feature at its highest | 202 | 5.0 ms | 19.1 ms | 163 MB | 956 MB |
| Builder | Ultra at 75% resolution | 331 | 3.0 ms | 3.4 ms | 164 MB | 863 MB |

What it means:

- **Ultra costs about 1.5 ms over High** on this GPU, mostly SDFGI and the 4-split shadows, and it
  roughly doubles video memory (SDFGI's cascades).
- **"Everything at its highest"** (lamp shadows, reflections everywhere, light shafts) costs another
  1.3 ms on average, but its slowest frames reach about 20 ms. Those are SDFGI and lamp-shadow updates as
  the camera moves, so it's a choice for screenshots and strong GPUs, not a preset.
- **75% resolution** barely helps in the world, where FSR 2's own cost cancels the saving at this load,
  but saves about 1 ms in the busier builder. It's for weaker GPUs.
- Auto's step-down (pc_detail.gd) still drops a level when frames stay above 20 ms for 2 seconds.

**The Detailed pack** (Textures: Detailed), in a Light World showroom with all ten pack pieces, Ultra, the
same PC and 1600×900: 181 fps either way, GPU 3.8 ms either way, video memory 695 MB → 888 MB. Its cost is
memory (the 2K maps), not frame time.

Phones and the browser keep their own profiles. Their settings are unchanged; the tests in test_pc_detail.gd
check that no PC setting reaches them.
