# Polox

A cozy little 3D world about **your** life. Build rooms, draw the characters who live there, and
talk with them. They remember what you tell them, cheer on your real dreams, and live their own
small lives while you're away. Think Tomodachi Life meets Deltarune, with a sprinkle of Mario Maker.

Everything stays on your PC. It's fully playable with one hand: mouse only, or a few keys on the side of
the keyboard you like. You can also play the same world on your own phone at home (**Phone Link**).

---

## 1. Install and play (Windows)

Pick the one that suits you. All three are the same game.

| | What you do | Where your worlds live |
|---|---|---|
| **Setup program** | Run `Polox-<version>-Setup.exe`. It adds Polox to the Start menu (and the desktop if you tick the box). No administrator password is needed for "just me". | `%LOCALAPPDATA%\Polox\PersonalData`: outside the program folder, so updating or uninstalling Polox never touches them |
| **Portable zip** | Unzip `Polox-<version>-Windows-Portable.zip` anywhere (a USB stick is fine) and double-click `Polox.exe`. Nothing is installed. | `PersonalData` beside `Polox.exe`: move the folder and your worlds move with it |
| **From source** | Get the folder, double-click `tools\get_godot.bat` once (it downloads Godot 4.7.2, about 86 MB, from its official GitHub page and checks it), then `run.bat`. | `PersonalData` in the project folder |

**Settings > Gameplay > Open Personal Data Folder** opens the folder, whichever you use.

**Moving from a portable copy to the setup program:** the setup has a step called *Bring your worlds along*.
Choose your old Polox folder there and your worlds, settings and add-ons are copied in the first time the
installed Polox starts. The old folder is left exactly as it is. Updating an installed Polox is just running
the newer setup; uninstalling keeps your worlds unless you ask it to delete them.

Then press **Begin**. Name your world, (optionally) tell it a little about your life and a dream, pick your
first friend, and you're in. Click your friend to say hi.

**Mac / Linux:** install Godot 4.7.2, then run `./run.sh` (set `GODOT=/path/to/godot` if it isn't on your PATH).

Building the setup program, the portable zip, the phone version and the Android app yourself is described in
[BUILDING.md](BUILDING.md).

## 2. Controls (one hand)

| What | Mouse | Keyboard (left hand) |
|---|---|---|
| Walk | click the floor | W A S D or arrow keys |
| Talk / use / next line | click a friend, sign or door | E or Z |
| Back / close | right-click | Q or X |
| Menu | "☰ Menu" button | C or Tab |
| Bag (your items) | "Bag" button | B |
| Switch Real Me / Dream World Me | Menu > Switch to... | F |
| Left-handed? | Settings > Controls > *I play with my: Left hand* | I J K L walk, O talk, U back, P menu, H bag, Y form |
| Rotate (in Build mode) | "⟳ Rotate" button | R |
| Camera | scroll wheel zooms (or rotates, see Settings); round buttons bottom-right | |
| Send a chat message | big **Send** button | Enter |

There are no held key combos and no timing challenges. Typing is only needed for chatting (and naming things).
A gamepad also works: stick/D-pad to walk, A to talk, B for back, Start for the menu, shoulder buttons
rotate the camera and triggers zoom. Every menu can be navigated with the D-pad.

## 3. Talking with real AI (optional, free)

The game starts in **Mock mode**: no internet, and friends answer with cute canned lines. For real
conversations, open **Menu > Settings > AI**, pick a provider, and press **Test connection**.

| Provider | Cost | Privacy | How to set it up |
|---|---|---|---|
| **Ollama** | free | **fully private, runs on your PC** | Install from <https://ollama.com>. Open a terminal and run `ollama pull qwen2.5:7b-instruct` (about 4.7 GB). For a slower PC, try `ollama pull qwen2.5:3b` and type that model name in Settings. Pick *Ollama* in Settings; no key needed. |
| **Groq** | free tier | cloud | Sign in at <https://console.groq.com/keys>, press **Create API Key**, copy it, paste it into Settings > API key. The default model is `openai/gpt-oss-20b`. |
| **Google Gemini** | free tier | cloud (see privacy note) | Get a key at <https://aistudio.google.com/apikey>, paste it into Settings. The default model is `gemini-3.5-flash-lite`. |
| **Custom** | varies | varies | Any server with an OpenAI-style `/chat/completions` endpoint: fill in Base URL, Model and key. |

Tips:
- Your key is stored **only** in `settings.json` in your PersonalData folder on this PC. It's never
  written to chat logs, and it's blanked inside backup zips.
- Free tiers limit how much you can send per minute. The game paces itself (at most 20 requests a
  minute by default; change it under Settings > AI > Advanced). If a provider is busy, your friend says
  a gentle "say that again?" line and your message is still saved.
- **List models** shows what your provider offers (handy with Ollama).

## 4. What you can do

- **Chat** with friends. They remember facts you share (Menu > **Friends** shows and edits what they
  remember), keep a running summary of your story, and react with different faces. Tap a **suggested
  reply** under the text box to answer with one tap (Settings > Gameplay can hide them).
- **Coming back:** a world opens in the room you left, with a small **"Where was I?"** card (your last chat
  and a dream to cheer on). A quiet *✓ Saved* under the room name shows the game saving as you go.
- **World Bible** (Menu): describe your world's setting and lore, and as much of your real life as you like.
- **Dreams & Desires** (Menu): your real hopes. Friends bring them up and cheer you on; mark one **Done ★** to celebrate.
- **Memory Book** (Menu): moments saved automatically (first chats, finds, milestones) or by you (**★ Save** in a chat).
- **My character** (Menu): your **Player Profile** (name, pronouns, nicknames friends may use, birthday,
  "about me", whether friends know your dreams, your own text-blip voice), which every friend's AI reads.
  **Looks**: two forms, **Real Me** and **Dream World Me**, each made in the **doll maker** (skin, 8 hair
  styles, 6 eye styles, 6 outfits, 8 accessories, each with hue/strength/brightness, Randomize, presets you
  can save for every world) or **drawn by you** (all eight faces in the Character Creator). Switch any time
  (Menu or **F**), or tie a room to a form (Build > Room > "You: ..."). **Gear** shows what you wear and hold;
  equipped items are drawn on your character (switchable).
- **Bag** (top right, or **B**): every item you carry, by type, sortable and searchable, with details. Eat
  snacks, admire keepsakes, equip weapons and armor (head, body, accessory). Stats are just for fun:
  there is no fighting in Polox.
- **Item Workshop** (Bag or Menu): design weapons, armor, snacks and keepsakes: name, rarity colour,
  flavor text (**✨ Suggest** asks your AI, or gives an offline idea), gift tags, an icon (auto-drawn, drawn
  by you, or imported), an optional in-world picture, show-only stats and one tiny effect (a mood boost when
  gifted, an aura colour, a sound, a message, or a moment of coloured light). **Make one** puts it in your
  bag. New worlds start with a dozen whimsical items.
- **Pickups** (Build > Objects > Pickup): leave an item somewhere to find, once or every day.
- **New friend** (Menu): the **Character Creator**. Paint each face on a pixel canvas
  (16 to 128 px grid, brush sizes, eraser, fill, color picker, mirror, 100 undo steps), import a PNG,
  add custom faces, and write their personality, backstory, quirks and speech style.
- **Build** (top right): the editor. **Tiles** paints pictures from tile sets on three layers (Ground,
  Blocks, Foreground: canopies and curtains that fade when you walk behind them) or places cubes, slabs,
  ramps and pillars; **Objects** places doors, signs and plants; **Room** sets the name, size, start spot,
  floor/wall/sky colours, a backdrop picture, weather, music, and runs a **Room check**. Tools: place,
  brush, erase, pick (eyedropper), paint, edit, and in **Advanced**: line, rectangle, fill, select
  (copy/cut/paste/rotate/flip), stamps, brush size, elevation, random brush, the inspector and layer
  visibility/lock/opacity. Everything autosaves; Undo/Redo keeps 150 steps; "?" lists the optional keys.
- **Tile sets** (Build > Tile sets...): every world starts with Cozy Home, Dream Meadow, Dark Castle and
  Night Sky. Make your own from a PNG atlas, single PNGs, or by drawing (with a seamless preview); save sets
  to the Library to use them in any world; export/import `.polox-tiles`.
- **Templates & stamps** (Build > Room): nine built-in rooms (and a 3-room apartment) to start from or apply
  to the current room; save any room as a template; save any selected area as a stamp.
- **Life**: friends wander, greet you, chat with each other, find shiny things, get sleepy at night
  and a little lonely if you're away. The lighting follows your real clock.
- **Music**: drop `.ogg`, `.mp3` or `.wav` files into `PersonalData\audio\music\` (or the
  game's `assets\audio\music\`). You can also replace sounds in `audio\sfx\` (`blip`, `click`, `door`, `place`,
  `remove`, `chime`, `pop`).
- **Chat Log** (Menu): every message ever, searchable and filterable by friend, room and date. **Export** writes a dated `.txt` and `.jsonl`.
- **Worlds** (title screen, or Menu > Worlds): every save is a card with a cover, emoji, colour, notes and
  tags. Make as many worlds as you like (guided or blank), switch between them, copy one, export it as a
  single `.polox` file (and import it on another PC), verify its files, back it up, go back to an earlier
  snapshot, or move it to the Trash (30 days to change your mind). **F5** is quick-save. Each card has
  autosave settings (snapshot every N minutes, on room change, on quit; how many to keep). The screen's
  look (colours, frame, text size) and layout (grid or list, sort, filter) are remembered.
- **Gifts**: press **Gift** while chatting and pick something from your bag (up to three gifts per friend a
  day; the 2nd and 3rd bring half the closeness). Every friend has **liked and disliked tags** (Creator > Personality): matching items make them
  happier and closer, and you see it in the chat, a little note in the Chat Log, and Menu > Friends. Friends
  remember your recent gifts and can bring them up.
- **Friendship web** (Menu > Friends): see how close you are to everyone, and how close they are to each
  other. Friends bond by chatting and hanging out, and they know about each other.
- **Photos**: the **Photo** button (bottom right) or Menu > Take a photo snaps the room into your Memory
  Book (files go to `PersonalData\photos\`).
- **Seasons & weather**: the real date brings seasons, gentle daily weather (snow, rain, falling leaves,
  petals, summer fireflies) and special days, including your birthday if you add it in the World Bible.
  Switch weather off per room in Build mode, or everywhere in Settings > Gameplay > This world.
- **Theme music**: give a friend their own track (Creator > Personality > Theme music) and it plays while you chat.
- Little body language: friends bounce when happy, shake when angry, droop when sad.

### Make a tile room

Open **Build** to enter the editor. It opens on **Tiles** with a starter tile selected. Choose Ground, Blocks or Foreground, pick a tile from the palette, then click or drag on the room. Use **+ New tile set / manage...** to import an atlas (preview and slice), add PNGs one at a time, or draw a tile. Save a set to the Library to reuse it across rooms and worlds. The first-use hint stays in the palette until dismissed. The Home room has a door to **Tile Playground**, a small example of the tile layers and foreground fading.

Turn on **Advanced** for the deeper tools. **Smart tiles...** assigns all 16 north/east/south/west neighbor patterns from a sliced atlas; the brush updates nearby variants as you paint or erase. The **Layers** inspector can add, rename, reorder, lock and tune custom layers, and move a selected area between them. Cell events can show a message, play a sound, move rooms, change lighting or toggle a layer on step or interaction. **Find / replace...** changes exact tiles or re-skins by matching names. **World Map** lets you arrange room cards and drag the mint handles together to add two-way doors. The 1–9 hotbar stores favorite brushes, objects, stamps or items; recent brushes are also shown. Each advanced control has a tooltip and the **?** shortcut guide explains keyboard alternatives.
## 4b. Play on your phone (Phone Link)

Play your worlds in your phone's browser (Android or iPhone). The full guide is
**[PHONE_SETUP.md](PHONE_SETUP.md)**; it all happens in **Menu > Settings > Phone Link**.

**Phone can't connect?** Double-click **`ping.bat`** (or Settings > Phone Link > **Network test**): a tiny test
server shows, big, the addresses to open on the phone, and lists every device that reaches the PC. On the phone,
open the address and tap **Run the full connection test** (or open `<address>/test`): it checks each step, shows
red/green with the exact error, and sends its report to the PC. The whole 5-minute procedure is in
**[PHONE_TRIAGE.md](PHONE_TRIAGE.md)**. When Wi-Fi won't do it, the Phone Link screen's **Tailscale** card gets you
there in three steps; Advanced also offers a **bundled web server** engine (Plan B, `tools\fetch_server.bat`).

1. **Once, from source only:** build Polox's engine (see "Polox's own engine"), then Settings > Phone Link >
   **Build the phone version**. The setup program and the portable zip already carry the phone version.
2. **On the PC:** Settings > Phone Link > switch **ON** (or double-click **`host.bat`** for a small window
   without the game). It shows the address big, e.g. **`http://192.168.1.42:8765`**, a QR code and a
   **PIN** like **482 913**.
3. **On the phone, same Wi-Fi:** open that address. The **Polox Launcher** asks for the PIN, then shows
   **Your worlds**; tap **Play**. Next time it goes straight to your worlds. (Windows may ask once to allow
   Polox on the network: click Allow, or run **`allow_phone_link.bat`**.)
4. Play: tap to walk and talk, long-press = back, pinch = zoom, two fingers = turn. The phone keeps a copy
   and syncs with the PC (the PC's copy wins if both changed the same thing; the phone's is kept for you to
   review). Chats go through the PC, so your API key never leaves it.

**Away from home:** with **Tailscale** on the PC and the phone (same account), Phone Link also offers a private
`https://<pc>.<tailnet>.ts.net:8765` address. Something wrong? After a minute without a phone the Phone Link
screen shows a checklist and runs **`phone_doctor.bat`**'s checks. **`check_phone.bat`** proves the whole thing on
the PC; **[PHONE_TEST.md](PHONE_TEST.md)** is what's left for your phone. Phone Link is off every time Polox
starts, refuses public internet addresses, and never uses Tailscale Funnel. Save menu > ⋯ > **Available on
phone** decides which worlds a phone sees.

### Polox for Android (the app)

On an Android phone (64-bit, Android 7 or newer) you can install Polox as a real app instead of using the
browser: it finds your PC by itself, plays **offline** with its own copy, and syncs whenever the PC is reachable.
iPhones keep the browser version (Apple doesn't allow installing apps this way).

1. **Once, on the PC:** the Android tools (`tools\get_android_tools.ps1 -AcceptLicenses`, already done here) and
   Polox's engine (below), then Settings > Phone Link > **Polox for Android** > **Build the app** (a few minutes:
   Android's Gradle build). The first build makes this PC's signing key in `tools\android\`: keep that folder,
   because Android only updates the app with the same key.
2. **Install it**, either way:
   - **USB:** switch on USB debugging on the phone (the card shows the steps), plug it in, click **Install on my
     phone**.
   - **Download:** with Phone Link on, open the Launcher on the phone and tap **Android app** (or `<address>/app`),
     then **Download polox.apk**. Android asks to allow installing apps from Chrome once; the page shows each step.
3. **Open Polox on the phone:** **Connect to your PC** explains, then listens for your PC on the Wi-Fi (Phone Link
   on). One PC found goes straight to its PIN (several: tap yours). Type the PIN on the big keypad or with your
   phone's keyboard (the field under the keypad), or tap **Scan the QR code** and point the camera at **Pair the
   app** on the PC (the camera is asked for only then). Skipped it? The title screen and **Settings** both have
   **Connect to your PC** until the phone is paired.
4. Play. The app says which path it uses (home network, the last address that worked, or Tailscale away from
   home). Without the PC it keeps playing and tries again every minute; coming back to the app syncs too.
   **Settings > AI > Check connection** runs the connection test from the phone and sends it to the PC's Doctor.
   When the PC has a newer Polox, the app offers the update (your worlds stay).

### Polox's own engine

The Android app, the phone (web) version and `Polox.exe` run Polox's own build of Godot 4.7.2, not Godot's
ready-made templates: Godot's official source with Polox's engine fixes (`native\godot\patches`: a looping sound
can't read past its data, which crashed Android; sounds playing at quit are freed; a stale shader cache isn't a
warning) and only the parts of the engine the game uses (`native\godot\polox_profile.py`; a test keeps the game
from needing a part that's left out). The Android app is built with Gradle and carries Polox's Android plugin
(`native\android`). Build it with `tools\pyenv\Scripts\python tools\build_engine.py android web windows`: the
toolchains are portable in `tools\` (the top of `tools\build_engine.py` lists them), the results land in
`tools\engine\`, and the phone's crash symbols stay in `tools\engine\android\native-symbols.zip`.

## 4b-2. Places (what used to be rooms)

Every place is **indoors** (walls, but standing on the ground under the sky, not in a void), **outdoors** (open
sky, the ground to the horizon) or **somewhere strange** (floating in a dream sky). New worlds start as one world:
Home indoors, and the Garden and the Tile Playground outdoors, joined edge to edge (older worlds were opened up
the same way in 1.13.3, after a snapshot; places you'd changed in Build mode stayed as they were). In **Build mode > Place** pick the kind and the sky, and **Add a place** to any side: a
new place just like this one, joined at that edge. Walk off the edge and you're there, at the same spot along the
edge; beyond each join you can see the next place's ground and its name. Advanced (one click) chooses which walls
stand, the ground, and up to three background layers (hills, trees, mountains, a city, dunes, clouds, shapes,
stars) that drift past each other as the camera moves. **Menu > World Map** shows your places laid out like a land;
tap one to go there. **Menu > Places** makes new ones from templates (Cozy room, Meadow, Beach, Forest clearing,
City street, Cave, Cloud tops, Starfield). Doors still work too.

Big moments (moving between places, and more to come) are animated; tap to skip, or turn on **Settings > Accessibility >
Reduce motion** for short fades.

### The Light World and Dream Gates

Your everyday places are the **Light World**. Put a **Dream Gate** (a basin brimming with glossy orange liquid) in one (Build mode > Pieces), then tap it in
play: **Make a Dream World from this place** (the same layout, turned strange: a darker palette, a void sky, glowing
outlines) or link one you have, and **Enter the Dream World**: you fall through darkness and land as Dream World Me,
your friends as Bramins (the Dream World's people) in their Dream World looks. The Dream Gate there takes you
**back**. **Seal the Dream Gate** closes it for
now; nothing is deleted, and Menu > World Map > **Archive** can reopen it. Battles (below) happen in Dream Worlds by
default.

### Friendly battles

A friend may walk up in a Dream World with a reason from your chats (rarely; **Not now** is always fine), or start
one yourself: say "I want to fight" in a chat, **Menu > Battle**, or step on a **Battle Spot**. Pick a template or a
battle you saved, and up to two friends to fight beside you. Then: **FIGHT** (tap when the line is in the middle),
**ACT** (kind or silly things that fill their mercy), **ITEM** (snacks heal; your bag isn't used up), **SPARE** (when
their mercy is full) or **DEFEND** (Run away is in there too). On their turn, your Soul follows your finger or the
mouse inside the box; brushing past bullets fills TP. Nobody gets hurt for real: they get tired out, you spare each
other, or you're knocked down and get right back up. **Settings > Accessibility > Battle help** has Story mode and other
helpers. Your own HUD pictures can go in `PersonalData\skins\battle_hud\` (this PC only).

**Make your own battle:** Menu > **Battle Maker** (or **New...** before a battle). Pick who you face and how tough
they are, add their turns from the pattern list (Gentle rain, Crosswind, Hug...), **Draw a bullet** (its exact
shape is what touches your Soul), and watch the preview: pause it and drag the slider to any moment (the same
moment always shows the same bullets). **Save**, **▶ Test** (the whole battle, then straight back to the Maker as
you left it) or **Save and fight**. **Advanced** (one tap) splits everything into sections: **Encounter**,
**Enemies** (all at once or one after another, stats, ACTs and lines), **Waves** (order, reorder, duplicate,
preview, every spawner: straight, aimed, arc, wave, spiral, orbit, bounce, or a path you trace, and phases),
**Arena** (the box, the Soul's mode, hazard zones that sting or slow), **Rules** (spare or tire, spare only, or
last N turns; damage, Soul speed, a reward) and **Presentation** (music, backdrop, effect, opening line).
Anything missing is listed at the top, each a link to its control. Saved battles live in the world, so backups and
Phone Link carry them, and battles made before still play as they did.

### Add-ons

**Title > Add-ons** lists the add-ons Polox found. From there you can turn each one on or off (Polox
remembers your choices), open the add-ons folder (`PersonalData/addons/`) and see problems with an
add-on's files, such as a missing file. An add-on can change the music for each cue (title menu, making
your home, Light World, Dream World, battles), add songs, and change the Soul's picture, sound effects,
tiles and on-screen words. When an add-on's file can't be used, Polox uses its own. Polox runs an
add-on's scripts only after you trust them. The format is described in [ADDONS.md](ADDONS.md).

Built into this PC's Polox (`assets/local/`, which Git ignores): your soundtrack for the music cues and
**Mochi** as the Soul you steer in battles. Turn on the **Polox Originals** add-on to use Polox's own
tunes, made in code, and its **Dream Drop** Soul instead. A fresh copy without `assets/local/` uses
those originals anyway.

## 4c. Platform Mode (run and jump)

*The camera is higher now (you see the ground ahead and the next ledge); Settings > Display > Platform camera
switches between High, Classic and Low.*

A second way to move through your own rooms: free running and jumping over your tiles and blocks. It only
starts from a **Platform Pillar** (a tall glowing column with rune rings) and you can always leave.

- **Try it:** new worlds have one in the **Tile Playground** (and older worlds get one there). Walk up to it
  and press **E** (or click / tap it). A flash, a ring burst, the camera swoops in: you're in. An **Exit
  Pillar** appears where you started; **Leave Platform Mode (X)** is always on screen; **Esc** works too.
- **Controls** (one hand is always enough): **WASD**/arrows move, **Space** jumps, **R** run on/off, **Q/E**
  turn the camera, **V** first person, **F** use, **Tab** menu. Mouse only: hold the left button to run toward
  the pointer, click things to use them, big **Jump** / **Run** buttons. Phone: a thumb stick (push it all
  the way to run), a **Jump** button, tap to use, two fingers to orbit. Left-handed mirrors it all.
- **Assists** (on-screen button): Auto-run, Auto-jump (hops 1-block ledges), Slow-fall, Camera assist (on by
  default: the camera stays behind you, no camera control needed).
- **Kind rules:** no lives, no timers, no fall damage. Falling off or touching a soft hazard just fades you back
  to the last **checkpoint**. **Memory Shards** you collect are remembered. Saving or quitting puts you back at
  the checkpoint, walking normally.
- **Build courses:** Build > Objects (turn on **Advanced** for the platform pieces): **Platform Pillar** (label,
  colour, once or every time, optionally leading to another room), **Jump pad**, **One-way ledge**, **Moving
  platform**, **Checkpoint**, **Memory Shard**, **Soft hazard**. Tiles can be **Slippery** (tile editor).
  **Jump reach** (Advanced) shows where a running jump from the cursor can land. **Play-test** with *in
  Platform Mode* ticked starts it right away. Two ready courses are in the Library: **Sky Steps** and **Moon
  Ledges** (Room > Templates).
- **Your own run sprites:** Character Creator (or My character > draw your form) > **Animations**: idle, walk,
  run, jump, fall, land. Draw frames (the previous one shows faintly underneath), copy the previous frame,
  import a sprite strip, or **Generate from base sprite**; set the speed and watch the preview. Without frames
  every state still moves differently (running leans and kicks up dust).
- Switch Platform Mode off for a world in the World Bible.

## 4d. Every day a little different

Your world lives on the real calendar, gently. Nothing here is a chore: no streaks, no timers, nothing lost
while you're away. Everything works with the AI off.

- **Daily Moments:** each day 1-3 small happenings from a deck of 70 (and your own): a **visitor** with a
  story (invite them to stay; if they wander on, Menu > Story > Collection can invite them back any time), the **sky** (rain, snow, fireflies, an aurora),
  something **found** (it waits as a pickup), a **request** from a friend, a friendly **rumor**, a
  **celebration** (seasons, holidays, dates you add), and **Memory Echo** (a line from your own Memory Book;
  off unless you switch it on). They show in a small **Today in your world** card. Menu > **Today & Moments**:
  add your own Moments and dates you celebrate.
- **Routines:** Character Creator > Personality > **Daily routine**: where each friend is and what they do in
  the morning, afternoon, evening and night.
- **While you were away:** after 3+ hours, friends followed their routines and left 0-3 letters, diary pages
  or small gifts for you (pickups, also in the Memory Book). With an AI set up, one batched request writes
  them in their voices; otherwise built-in ones. Never a guilt trip.
- **Quests:** small optional goals from your friends, shaped by your Dreams board: build or decorate, visit a
  room, find a hidden spot, collect Memory Shards, tell a friend about your dream, give a gift, make an item or
  a tile, and (rarely, only if you want) a tiny real-life step you tick yourself. Rewards are cosmetic
  (keepsakes, a little outfit, a tile set, a Dream Door key). Menu > **Quests**; **Let it go** any time.
- **Dream Doors:** Build > Objects > **Dream Door**. Each time you go through, a new small room is dreamed for
  you (themed by your dreams and World Bible, with one surprise, and a little climb when Platform Mode is on).
  **★ Keep this dream room** makes it yours; otherwise the last 10 wait in the **Dream Archive**.
- **Almanac** (Menu): places made, Dream World visits, friendly battles and spares, Dark Crystals, discoveries,
  tile sets used, items made, friends met, Moments seen, quests done, shards found, Dream Doors opened, letters
  received, and titles to wear. Memory Shards add a memory to the Memory Book.
- **Story** (Menu): eight chapters that open as your world grows (a place of your own, beyond the edge, the
  Dream Gate, a friendly fight, mercy, makers, light returns, together). Each is a short scene and two or three
  things to do in any order; finishing one gives a title to wear. It's read from your world, never from the clock,
  and it waits as long as you like. The same screen has **Requests** (now and then a friend asks for something
  small, at most two at a time, no deadline, **Let it go** any time; doing one brings a thank-you, a Memory Book
  page and a little closeness), the **Battle Log** and your **Collection**.
- **Dark Crystals and discoveries:** the first visit to a Dream World place hides three Dark Crystals (they wait
  for you); the first visit to each place is a discovery. Both count in the Almanac.
- **Since you were last here:** the "Where was I?" card says where the story is, whether a friend asked
  something, and that nothing was missed while you were away. Friendship never fades; a friend's happiness drifts
  down to calm while you're gone.
- **Hang out** (Menu): pick a friend who's in the room for **Tea Time** (a teapot appears, you chat),
  **Stargazing** (an aurora; **Make a wish** puts it on your Dreams board) or a **Photo Walk** (a little stroll,
  then a photo into the Memory Book). Each one is a Memory Book moment; nothing to win or lose.
- **Seasonal decorations** follow the real calendar: string lights and little things in the corners for
  Halloween week, the winter holidays, New Year, Valentine's week, the spring equinox, midsummer, your birthday
  and the dates you celebrate, plus a quiet season touch (autumn leaves, winter snow, spring flowers, a summer
  sunflower). They're decoration only (never saved into your rooms); switch them off in Settings > Game.
- Switch it all off in a world's settings (Daily events).

## 5. Where your stuff lives

Everything is in your **PersonalData** folder (section 1 says where it is for your copy; **Settings > Gameplay > Open Personal Data Folder** opens it, and Menu > **Open save folder** opens the current world). These are
plain files you can read. Shared things sit at the top; each world has its own folder under `slots\`:

*Played an older version?* The first start copies what it finds in the places older versions used
(`Documents\Polox`, and `Documents\PocketDarkWorld` from when the game had that name) into PersonalData,
checks every file, and tells you so. The old folders are never touched; delete them whenever you like.

| File / folder | What's inside |
|---|---|
| `settings.json` | your settings (and API key); shared by all worlds |
| `audio\music\`, `audio\sfx\` | drop-in music and sound overrides, shared |
| `snapshots\` | a zip of the whole folder taken before any save-format update |
| `trash\` | worlds you deleted, kept 30 days |
| `exports\` | `.polox` bundles you exported |
| `slots\<world>\slot.json` | the card: name, emoji, colour, notes, tags, playtime, autosave settings |
| `slots\<world>\world.json` | world name, World Bible, your name, start room |
| `slots\<world>\rooms\*.json` | each room's size, colors, blocks and objects |
| `slots\<world>\characters\<name>\` | `character.json` (personality, mood, memories, gift tags) and `expressions\*.png` (faces) |
| `slots\<world>\player\real\`, `player\dark\` | your two forms' faces (PNG) |
| `slots\<world>\items\<item>\` | `item.json` plus optional `icon.png` / `sprite.png` for each Workshop item |
| `slots\<world>\inventory.json` | what's in your bag and what you're wearing |
| `library\dolls\` | doll-maker presets you saved (shared by all worlds) |
| `phone\` | Phone Link: `devices.json` (paired phone, key fingerprints only), `audit.log`, sync state |
| `slots\<world>\conflicts\` | your phone's version of files that changed on both sides (see PHONE_SETUP.md) |
| `slots\<world>\dreams.json`, `journal.json` | Dreams & Desires and the Memory Book |
| `slots\<world>\logs\*.jsonl` | every chat message, one per line (never auto-deleted) |
| `slots\<world>\backups\` | snapshot zips (automatic, manual, quick-save, before-restore) |
| `slots\<world>\manifest.json` | checksums written with each snapshot; **Verify** compares against it |
| `*.bak`, `*.broken` | the previous version of each save file, and anything that had to be restored |
| `slots\<world>\textures\`, `exports\`, `photos\` | your pictures, log exports and photos |

To move to a new PC, copy this whole folder over, or export a world as a `.polox` and import it there.

## 6. Privacy

**Everything about you is optional** (name, pronouns, birthday, about me, dreams, your real home): leave
any of it blank or skip it. **Everything stays on your device.** There are **no accounts, no Polox servers,
no telemetry and no multiplayer**. Something leaves your device only through what **you** switch on: the
chat requests sent to the online AI provider you choose in Settings, **cloud folder sync** (Polox writes
the worlds you pick into a folder your own Google Drive, OneDrive or Dropbox app uploads; never settings,
keys or your real home, see [SYNC.md](SYNC.md)), **Map my streets** (coordinates to OpenStreetMap, after
asking), and **Phone Link**: a small web server on this PC that your paired phones talk to over your own
network (details below). The full list is in [PRIVACY.md](../PRIVACY.md).
Each request carries what a friend needs to answer you: the World Bible, that friend's card and memories,
your **Player Profile** (name, pronouns, nicknames, about me, how you look and what you wear), your dreams
(unless you turn that off in My character) and the recent chat. Leave any profile field blank to keep it out.
Cloud free tiers may keep or review what you send; for example, Gemini's free tier may use content to
improve Google's products. **Ollama runs entirely on your PC** and is the fully private option.
**Mock** mode uses no network at all.

**Phone Link** (off unless you switch it on): your phone gets the launcher and game files, the list of worlds
you allow (names, covers, sizes), the Library and the world it plays; it sends back its changes and the chat
messages it wants answered, which the PC forwards to your AI provider like any chat. The phone holds a long
random key from the PIN (the PC stores only its fingerprint); every request without it is refused, as are
paths outside those worlds and the Library. `settings.json` and your API key never go to the phone or the app. While Phone Link is on, the PC also tells
your home network "Polox is here" every two seconds (a UDP broadcast with its name and port, nothing else) so the
Android app can find it. The app asks for the camera only to scan the pairing code, and talks plain HTTP only to
home-network and Tailscale addresses. Pairing,
wrong PINs and refused requests are logged in `PersonalData\phone\audit.log` (never the PIN or a key).

## 7. A gentle note

Your friends here are meant to be a cozy companion and a soft place to land, not a replacement for the
people in your life. If things ever feel heavy, please reach out to someone you trust or a local
helpline (<https://findahelpline.com> lists free ones worldwide; in the US you can call or text 988).

## 8. Troubleshooting

| Problem | Fix |
|---|---|
| `run.bat` says Godot wasn't found | Double-click `tools\get_godot.bat`, or put both Godot 4.7.2 `.exe` files in `tools\godot\`. |
| "Can't reach Ollama" | Start the Ollama app, and check `ollama list` shows your model. |
| "didn't accept the API key" | Copy the key again (no spaces) into Settings > AI > API key. |
| "sending too fast" | Free tier limit; just wait a minute. Lower "Max requests / minute" in Settings. |
| Text too small or big | Settings > Display > UI size. Text too fast? Lower *Text speed*. |
| Something looks broken | Your files are safe in your PersonalData folder. Try **Back up now**, then restart. |

## 9. For developers

Setup, build and test commands are in [BUILDING.md](BUILDING.md); [DIRECTORY_GUIDE.md](DIRECTORY_GUIDE.md) maps the
folders, entry points and feature tags; [../CONTRIBUTING.md](../CONTRIBUTING.md) says how to send a change; and
[../CHANGELOG.md](../CHANGELOG.md) lists what changed in every version.
