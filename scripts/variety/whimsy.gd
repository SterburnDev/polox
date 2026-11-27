extends RefCounted
## Cozy, deadpan, Toby Fox-inspired humor, multi-inspect furniture lines, and playful secrets.
## Keeps Polox feeling hand-crafted and warmly absurd without getting in the way of quiet moments.
## Tags: [EASTER_EGG]

## Keywords that arm the Music tab's secret image vault before clicking `yams👀`.
const SECRET_VAULT_WORDS: PackedStringArray = ["aero", "frutiger", "code", "rot"]

## Title-screen playful secret words (typed outside text boxes).
const TITLE_SECRET_WORDS: PackedStringArray = ["mochi", "bramin", "yams", "tub"]

## Multi-inspect rotating lines for Light World & Dream World furniture.
## The first line stays grounded and cozy; inspecting again reveals dry, playful surprises.
const FURNITURE_INSPECTS := {
	"mirror": [
		"Despite everything, it's still you.",
		"You strike a heroic pose. Your reflection is 0.02 seconds late. Probably fine.",
		"Still you. Your silhouette looks remarkably aerodynamic today.",
	],
	"fridge": [
		"It hums. There's something to snack on.",
		"You open the fridge, stare into the glowing void, close it, and immediately forget what was in there.",
		"A single suspiciously composed yam sits on the middle shelf. You respect its privacy.",
	],
	"toilet": [
		"...",
		"...Still a toilet. You admire its quiet professionalism.",
		"You briefly check whether there is a tiny Dream Gate inside. There isn't. Probably.",
	],
	"computer": [
		"The screen glows, patient.",
		"Forty-seven tabs are open. Nine of them are playing music and none have a speaker icon.",
		"There is a half-finished game project open. A comment reads: '# TODO: add more yams'.",
	],
	"bathtub": [
		"A long bath sounds nice.",
		"An ordinary bathtub. Unlike the Dream Gate, stepping inside mostly just gets your socks wet.",
		"No Bramins in the drain today. All clear.",
	],
	"bed": [
		"Your bed. It looks soft.",
		"It radiates an alarming amount of gravitational pull.",
		"Ten out of ten pillows recommend lying down immediately.",
	],
	"double_bed": [
		"A big bed, neatly made.",
		"Plenty of room to starfish diagonally like a victorious Bramin.",
	],
	"bookshelf": [
		"Books you've read, books you mean to.",
		"One spine just says 'HOW TO EXPLAIN YOUR DREAM WORLD TO GUESTS (VOL. 4)'.",
		"Behind a paperback sits a bookmark from a library that only exists on Tuesdays.",
	],
	"tv": [
		"Nothing on right now.",
		"Just a cozy test pattern and a tiny announcer whispering about weather in the Dream World.",
		"You tap the side. It hums a single C-major chord and goes back to sleep.",
	],
	"crt_tv": [
		"A chunky retro CRT. The glass crackles softly with nostalgic static.",
		"If you press your ear close, you can almost hear an extras menu theme from 2002.",
		"Its rabbit-ear antennas are tuned directly to the Bramin Public Broadcast Network.",
	],
	"lava_lamp": [
		"Glossy blobs drift upward in slow motion, utterly unbothered by deadlines.",
		"You watch two blobs almost merge, change their minds, and drift apart. Riveting drama.",
		"Peak Frutiger Aero serenity in glass form.",
	],
	"arcade_cabinet": [
		"The screen says 'INSERT 1 (ONE) IMAGINARY COIN'.",
		"High score #1: YAM — 999,990. High score #2: MOCHI — 999,989.",
		"The buttons feel wonderfully clicky even when it's unplugged.",
	],
	"crystal_cluster": [
		"A cluster of Dream World crystals, humming with polite magenta light.",
		"It feels warm, like a pocket pebble that sat in a sunbeam.",
		"Listening closely, you hear faint elevator music coming from inside the facet.",
	],
	"yam_plush": [
		"A suspiciously glossy yam perched on a tiny velvet cushion. It seems to be watching you. 👀",
		"You pat the yam. It does not squeak, yet somehow you feel judged in a friendly way.",
		"Legend says if you type the right word in Settings > Music and scroll all the way down...",
	],
	"aquarium_orb": [
		"A glossy glass orb swirling with crystal-clear water and microscopic bubbles.",
		"It smells faintly of 2007 wallpaper meadows and fresh mint.",
		"A tiny holographic dolphin definitely did NOT just backflip in there. You blinked.",
	],
	"wall_clock": [
		"Ten past ten. It always looks like it's smiling.",
		"Time moves politely here. It knocks before entering.",
	],
	"fish_tank": [
		"Three fish, one bubble at a time. They seem to know you.",
		"One of the fish taps the glass in Morse code. It spells: 'S-N-A-C-K'.",
	],
	"bean_bag": [
		"It sighs as you sink in. Five more minutes.",
		"Getting into the bean bag is free. Getting back out requires a small quest.",
	],
	"coffee_table": [
		"A mug ring nobody mentions.",
		"The coaster is sitting two inches to the left of the mug ring, doing its best.",
	],
	"piano": [
		"A few keys, gently.",
		"You play three notes. Somewhere in the walls, a tiny cricket applauds.",
	],
	"mailbox": [
		"Nothing today. Maybe tomorrow.",
		"Just a coupon for 100% off one (1) complimentary daydream. No expiration date.",
	],
	"birdbath": [
		"A tiny ripple. Someone was here a moment ago.",
		"A sparrow definitely reviewed this establishment five stars on FeatherMaps.",
	],
	"record_player": [
		"A little crackle before the music.",
		"The needle waits patiently like a tiny brass woodpecker.",
	],
}

## Deadpan reactions when clicking the title screen's version label ("Polox Public Beta 1.02").
const VERSION_CLICKS: PackedStringArray = [
	"Polox Public Beta 1.02 — freshly baked.",
	"Yes, it really is Public Beta 1.02.",
	"Clicking it won't make Public Beta 2.0 come out faster.",
	"Still Public Beta 1.02. Very stubborn version number.",
	"Okay fine. Here is one (1) complimentary sparkle. ✦",
	"You are extraordinarily persistent. The Bramins respect that.",
	"The version label blushes and pretends to be a normal piece of UI.",
]

## Playful corner captions when the Music tab's secret vault triggers via a typed keyword.
const VAULT_CAPTIONS := {
	"aero": "yams.exe // aero glass protocol engaged 👀",
	"frutiger": "frutiger_yam_2007.html // maximum gloss achieved 👀",
	"code": "0xYAM // compiling secret tubers... OK 👀",
	"rot": "certified yam rot detected // do not adjust your monitor 👀",
}

## Extra Toby Fox-style idle flavor lines for practice battles (sparring_catalog.gd).
const BATTLE_IDLE_QUIPS := {
	"tide_parcel": [
		"* The Tide Parcel smells faintly of sea salt and overly polite bureaucracy.",
		"* A tiny stamp on the corner says 'HANDLE WITH WHIMSY'.",
	],
	"pebble_lift": [
		"* The Pebble Lift hums an elevator song that never quite resolves.",
		"* Floor 2: Snacks. Floor 3: More snacks. Floor 4: Unexplained yams.",
	],
	"copper_vane": [
		"* The Copper Vane spins dramatically just to show off its patina.",
		"* Forecast: 80% chance of cozy breezes and mild silliness.",
	],
	"seed_post": [
		"* The Seed Post rattles like a maraca full of future houseplants.",
		"* One packet is labeled 'Mystery Tuber — Do Not Feed After Midnight'.",
	],
	"stillwater_lantern": [
		"* The Stillwater Lantern flickers in the rhythm of a sleepy heartbeat.",
		"* Tiny moths are attending a very formal meeting nearby.",
	],
	"ribbon_turntable": [
		"* The Ribbon Turntable spins at 33.3 RPM of pure unbothered confidence.",
		"* It is playing a secret B-side nobody has ever heard before.",
	],
}

## Session counter per furniture id/model so repeated inspections cycle cleanly.
static var _inspect_counts: Dictionary = {}


static func reset_session() -> void:
	_inspect_counts.clear()


## Returns the next rotating inspection line for a furniture piece (or `fallback` if none listed).
static func inspect_furniture(model: String, instance_key: String, fallback: String) -> String:
	var lines: Array = FURNITURE_INSPECTS.get(model, [])
	if lines.is_empty():
		return fallback
	var key := instance_key if instance_key != "" else model
	var count := int(_inspect_counts.get(key, 0))
	_inspect_counts[key] = count + 1
	return str(lines[count % lines.size()])


## Checks whether `buffer` (lowercase letters) ends with one of `words`; returns the match or "".
static func match_suffix(buffer: String, words: PackedStringArray) -> String:
	var clean := buffer.to_lower()
	for word in words:
		if clean.ends_with(word):
			return word
	return ""


## Appends printable ASCII letters from a key press into a rolling 16-char buffer.
static func push_letter(buffer: String, unicode_char: int) -> String:
	if unicode_char >= 65 and unicode_char <= 90:
		unicode_char += 32   # A-Z -> a-z
	if unicode_char < 97 or unicode_char > 122:
		return buffer
	var next := buffer + char(unicode_char)
	return next.right(16) if next.length() > 16 else next


static func version_quip(click_count: int) -> String:
	if click_count <= 0:
		return ""
	return str(VERSION_CLICKS[mini(click_count - 1, VERSION_CLICKS.size() - 1)])


static func secret_vault_caption(keyword: String) -> String:
	return str(VAULT_CAPTIONS.get(keyword.to_lower(), "yams👀"))


static func title_secret_message(word: String) -> String:
	match word.to_lower():
		"mochi":
			return "* (Mochi appreciates the shoutout!)"
		"bramin":
			return "* Somewhere in the Dream World, a Bramin sneezes."
		"yams":
			return "* (Try scrolling all the way down in Settings > Music... 👀)"
		"tub":
			return "* It's a reddish bathtub-like Dream Gate. No ducks allowed. (...Maybe one.)"
	return ""
