# Polox add-ons

An add-on is a folder that changes some of Polox's pictures, music, sound effects, tiles or on-screen
words, and can (only after you trust it) run scripts. Open **Title > Add-ons** to see the add-ons Polox
found, turn each one on or off (Polox remembers your choices), open the add-ons folder and check for
problems with an add-on's files.

## Where add-ons go

- **Every copy of Polox:** `addons/` in your save folder (`PersonalData/addons/` on a PC).
- **Run from the source:** also `local-addons/` in the checkout. Git ignores this folder and exports
  leave it out. Put music, pictures and themes there that you aren't allowed to share.
- **Bundled with the game:** `bundled-addons/`. **Polox Originals** lives there: turn it on to use
  Polox's own tunes and the Dream Drop Soul instead of what's built in.
- **Private Hub exports:** the optional **UTDR Theme** comes from `assets/local/addons/utdr-theme/`.
  The source checkout uses the editable copy under `local-addons/`. Both copies keep the same add-on ID
  and use the choices saved on that device.

Each add-on gets its own subfolder with an `addon.json` file in it. Polox reads only that file when it
looks for add-ons. It checks the other files when you turn the add-on on.

## Built in on this PC

`assets/local/` holds what this PC's Polox has built in: a soundtrack for the music cues and a picture
for the Soul. Git ignores this folder. Private Hub exports include the selected media. It uses the same
`addon.json` format as an add-on, is always on, sits under every add-on and isn't shown in the Add-ons
list. A copy of Polox without this folder (a fresh checkout or a public copy) plays Polox's own tunes
and shows the Dream Drop.

## addon.json

```json
{
  "id": "my-addon",
  "name": "My add-on",
  "version": "1.0.0",
  "description": "What it changes, in a sentence.",
  "author": "You",
  "priority": 0,
  "enabled_by_default": false,
  "overrides": {
    "music":    {"menu": "music/menu.ogg", "survey": "music/making-home.ogg", "light": "music/light.ogg",
                 "dark": "music/dream.ogg", "battle": "music/battle.ogg"},
    "songs":    [{"file": "music/extra.ogg", "title": "An extra song", "from": "Where it's from",
                  "seconds": 90, "gain_db": -3}],
    "textures": {"soul": "pictures/soul.png", "logo": "pictures/logo.png"},
    "sfx":      {"chime": "sounds/chime.ogg", "battle_hit": "sounds/hit.wav"},
    "tiles":    {"cozy_home/rug": "tiles/rug.png"},
    "text":     {"Dream World": "Somewhere Else", "Bramins": "Dreamers", "Bramin": "Dreamer"},
    "scripts":  ["scripts/hello.gd"]
  }
}
```

Every file path is relative to the add-on's folder. Paths that leave the folder (such as `..` or
`C:/...`) are refused.

| Override | What it changes |
| --- | --- |
| `music` | The five music cues: `menu` (the title), `survey` (making your Light World home), `light` (the Light World), `dark` (the Dream World) and `battle`. Supports `.ogg`, `.mp3` and `.wav` files. |
| `songs` | Adds songs to Settings > Music and to the song lists for places and friends. `gain_db` (from -24 to 6) evens out a song that's louder or quieter than the rest. |
| `textures` | `soul` is the Soul on the title screen and the cursor you steer in battles. Its white background is removed and a light outline is added. Only the picture changes: the cursor still moves and collides the same way. `logo` is the Polox logo on the title screen. Supports `.png`, `.jpg` and `.webp` files. |
| `sfx` | Any of Polox's sound effects by name (`chime`, `pop`, `door`, `hum`, `battle_<kind>`...). Supports `.ogg`, `.mp3` and `.wav` files. |
| `tiles` | A tile's picture, written as `<tile set id>/<tile id>`. |
| `text` | Words on screen. Each phrase on the left is shown as the phrase on the right, and the same phrase in capitals changes too. Nothing saved is changed: turn the add-on off and the words come back. |
| `scripts` | GDScript files that `extend Node`. A script runs only while the add-on is on **and** after you choose **Trust scripts…** for exactly that version. If a script file changes, Polox asks you again. A script can do anything Polox can, so only trust add-ons from people you trust. If a script defines `_addon_start(api)`, Polox calls it with `{id, folder, notify}`. |

Instead of a file, a music cue can say `"@own"` (Polox's own tune; while you make your home, its low
hum) and the `soul` can say `"@dream_drop"`. Polox Originals uses these.

When two add-ons that are on change the same thing, the higher `priority` wins. A missing, unreadable,
too large (over 64 MB) or wrong-type file is listed on the add-on's card under Title > Add-ons, and Polox
uses its own asset instead.

## What a fresh copy of Polox uses

Without `assets/local/`, Polox ships no songs. Every music cue plays Polox's own tune, made in code (`battle_audio.gd`),
and making your home plays its own low hum. The Soul is Polox's own Dream Drop, drawn in code
(`scripts/ui/soul.gd`). The Dream Gate, the Dream World and the Bramins use the game's own names and
models.
