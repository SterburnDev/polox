# Drop-in audio

Your own sounds don't go here: put them in your PersonalData folder
(**Settings > Gameplay > Open Personal Data Folder**), in `audio/music/` and `audio/sfx/`. They are
loaded at run time, no editor needed. Supported: `.ogg`, `.mp3`, `.wav`.

- `audio/music/`: your own songs. They appear in Settings > Music, Build mode > Room and as a friend's
  theme music.
- `audio/sfx/`: optional overrides. Use these file names to replace the built-in sounds: `click`, `blip`,
  `door`, `place`, `remove`, `chime`, `pop` (any supported extension).

The `music/` and `sfx/` folders beside this file are read too, but only when the game is run from
source; an exported game reads PersonalData alone. Polox's own
blips, chimes, motifs and tunes are synthesized in code (`scripts/core/synth.gd`); the only recorded
sounds in the game are Kenney's footsteps and UI clicks (`assets/kenney/`). To change the music for a
whole cue, or to share a set of songs, make an add-on (`docs/ADDONS.md`).
