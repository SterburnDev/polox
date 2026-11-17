extends RefCounted
## The built-in Daily Moments: small happenings, never chores. Placeholders:
## {character} and {other} (two residents), {room}, {dream} (one of your
## dreams), {you} (your name, or "you"), {celebration}. Each entry:
## [id, kind, weight, text, extra]. Kinds:
##   visitor      a wandering stranger with a small story (may move in)
##   sky          rain, snow, fireflies or an aurora for the day
##   found        something small turns up as a pickup
##   request      a resident asks for something small (a gentle quest)
##   rumor        a bit of friendly gossip from the friendships
##   celebration  a season, a date you entered, or a holiday
##   echo         a snippet of your own past (opt-in, off by default)

const KINDS: PackedStringArray = ["visitor", "sky", "found", "request", "rumor", "celebration", "echo"]
const KIND_NAMES := {"visitor": "Visitor", "sky": "Sky", "found": "Found", "request": "Request", "rumor": "Rumor", "celebration": "Celebration", "echo": "Memory Echo"}

const ENTRIES := [
	# Visitors: [name, look preset, story]
	["v_lantern_keeper", "visitor", 3, "A lantern keeper named Ilo is resting in {room}, polishing a lamp that only lights for kind words.", {"name": "Ilo", "look": "mage", "about": "A wandering lantern keeper whose lamp glows brighter when someone says something kind."}],
	["v_cloud_knitter", "visitor", 3, "Someone called Pim is knitting a scarf out of cloud fluff in {room}. They say it's for the moon.", {"name": "Pim", "look": "sleepy", "about": "Knits scarves out of cloud fluff and gives them away to anyone who looks cold."}],
	["v_map_maker", "visitor", 3, "A map maker, Tove, is sketching {room}. 'Every room is a country if you look closely,' she says.", {"name": "Tove", "look": "gardener", "about": "A traveling map maker who draws tiny countries in every room she visits."}],
	["v_snail_mail", "visitor", 2, "A very slow postal snail, Mr. Bun, arrives in {room} with a letter dated three years from now.", {"name": "Mr. Bun", "look": "cozy", "about": "A patient postal snail who delivers letters from the future, a little late."}],
	["v_star_fisher", "visitor", 2, "Nell the star fisher is casting a silver line from {room} into the sky. Nothing yet, but she's hopeful.", {"name": "Nell", "look": "night", "about": "Fishes for fallen stars and lets them go again."}],
	["v_tea_wanderer", "visitor", 3, "A traveler named Oro is brewing tea that tastes like your favorite memory in {room}.", {"name": "Oro", "look": "cozy", "about": "Brews tea that tastes like whatever memory you need today."}],
	["v_moth_bard", "visitor", 2, "A moth bard named Lumi hums a song about {character} in {room}. {character} pretends not to blush.", {"name": "Lumi", "look": "mage", "about": "A shy moth bard who writes songs about whoever is nearby."}],
	["v_lost_robot", "visitor", 2, "A small robot, Bip, rolled into {room}. It's looking for 'a place that feels like home.'", {"name": "Bip", "look": "night", "about": "A little robot looking for a place that feels like home."}],
	["v_dream_baker", "visitor", 3, "Fen, a dream baker, is selling bread shaped like your dream: {dream}. It's free today.", {"name": "Fen", "look": "gardener", "about": "Bakes bread shaped like people's dreams and never charges for it."}],
	["v_echo_child", "visitor", 2, "A quiet visitor, Wren, sits in {room} drawing everyone they meet. They drew {character} with a crown.", {"name": "Wren", "look": "sleepy", "about": "Draws everyone they meet as the best version of themselves."}],
	# Sky
	["s_soft_rain", "sky", 4, "Soft rain all day. {character} says it's perfect blanket weather.", {"sky": "rain"}],
	["s_first_snow", "sky", 3, "Snow is falling over your world. {character} is trying to catch flakes.", {"sky": "snow"}],
	["s_fireflies", "sky", 4, "Fireflies came out early. {character} counts them and loses track at forty.", {"sky": "fireflies"}],
	["s_aurora", "sky", 2, "An aurora ribbons across the sky tonight. Even {other} stopped to look.", {"sky": "aurora"}],
	["s_petal_wind", "sky", 3, "A warm wind carries petals into {room}.", {"sky": "petals"}],
	["s_leaf_dance", "sky", 3, "Leaves are dancing through the air. {character} keeps one as a bookmark.", {"sky": "leaves"}],
	["s_starfall", "sky", 2, "Tiny stars fall like snow tonight and melt into light on the floor.", {"sky": "aurora"}],
	["s_clear_blue", "sky", 2, "The sky is so clear today you can almost see tomorrow.", {"sky": "clear"}],
	["s_drizzle_song", "sky", 2, "A gentle drizzle taps a rhythm on the roof. {character} hums along.", {"sky": "rain"}],
	["s_snow_hush", "sky", 2, "Snow makes everything quiet. {character} whispers just for fun.", {"sky": "snow"}],
	# Found objects: [item name, icon hint]
	["f_moon_pebble", "found", 3, "A moon-shaped pebble turned up in {room}.", {"item": "Moon pebble", "color": "#c9b6ff"}],
	["f_tiny_key", "found", 3, "A tiny key is lying in {room}. Nobody knows what it opens. Yet.", {"item": "Tiny key", "color": "#ffd166"}],
	["f_paper_crane", "found", 3, "Someone left a paper crane in {room}. It has your name on one wing.", {"item": "Paper crane", "color": "#f3e9d2"}],
	["f_sea_glass", "found", 3, "A piece of sea glass, warm from the sun, is waiting in {room}.", {"item": "Sea glass", "color": "#7ad6b0"}],
	["f_star_seed", "found", 2, "A glowing seed is in {room}. It hums when you hold it near a window.", {"item": "Star seed", "color": "#7af0ff"}],
	["f_old_photo", "found", 2, "An old photo is tucked in {room}: everyone in your world, smiling, from a day that hasn't happened yet.", {"item": "Future photo", "color": "#e8d3b0"}],
	["f_feather", "found", 3, "A shimmering feather drifted into {room}.", {"item": "Shimmer feather", "color": "#ffb3c7"}],
	["f_music_box", "found", 2, "A little music box is in {room}. It plays a song {character} says they know.", {"item": "Music box", "color": "#e86a8a"}],
	["f_ribbon", "found", 3, "A ribbon in your favorite color is tied to something in {room}.", {"item": "Ribbon", "color": "#c58cff"}],
	["f_compass", "found", 2, "A compass that points to 'somewhere nice' turned up in {room}.", {"item": "Kind compass", "color": "#8fd3ff"}],
	# Requests: [ask, quest hint]
	["r_snack", "request", 3, "{character} is a little hungry and wonders if you have a snack to share.", {"quest": "gift", "ask": "a snack"}],
	["r_visit", "request", 3, "{character} would love to see {room} with you today.", {"quest": "visit"}],
	["r_story", "request", 3, "{character} wants to hear about your day. Even the boring parts.", {"quest": "talk", "topic": "day"}],
	["r_flower", "request", 2, "{character} wonders if you could add a flower or a plant somewhere cozy.", {"quest": "build", "tag": "plant"}],
	["r_drawing", "request", 2, "{character} would love a little drawing of anything at all.", {"quest": "create_item"}],
	["r_dream_talk", "request", 2, "{character} wants to hear how {dream} is going. No pressure.", {"quest": "talk", "topic": "dream"}],
	["r_gift_any", "request", 2, "{character} has been feeling a bit low and a small gift might help.", {"quest": "gift", "ask": "anything"}],
	["r_new_tile", "request", 2, "{character} wonders what a brand-new tile would look like if you drew one.", {"quest": "create_tile"}],
	["r_climb", "request", 2, "{character} heard there's a view from the top of a Platform course.", {"quest": "platform_ledge"}],
	["r_shards", "request", 2, "{character} saw a Memory Shard glint somewhere. Could you find it?", {"quest": "platform_shards"}],
	# Rumors (from friendships)
	["g_secret_garden", "rumor", 3, "{character} whispers: {other} has been practicing a song for you.", {}],
	["g_baking", "rumor", 3, "Rumor has it {other} tried to bake a cake and it came out shaped like {character}.", {}],
	["g_stargazing", "rumor", 3, "{character} says {other} was seen stargazing alone. Maybe they'd like company.", {}],
	["g_compliment", "rumor", 3, "{character} heard {other} say something really nice about you.", {}],
	["g_hobby", "rumor", 2, "Apparently {other} has started collecting tiny spoons. {character} is delighted.", {}],
	["g_nap", "rumor", 2, "{character} caught {other} napping in {room} with a book on their face.", {}],
	["g_dance", "rumor", 2, "Word is {other} dances when they think nobody's watching. {character} saw.", {}],
	["g_letter", "rumor", 2, "{character} thinks {other} is writing a letter. To whom? A mystery.", {}],
	["g_plan", "rumor", 2, "{character} and {other} are planning something for {you}. Act surprised.", {}],
	["g_kind", "rumor", 2, "{character} says {other} helped a lost bug find its way home.", {}],
	# Celebrations
	["c_season", "celebration", 3, "It's {celebration}. {character} hung paper stars in {room}.", {}],
	["c_tiny_holiday", "celebration", 2, "{character} declared today Tiny Holiday: a day for small joys.", {}],
	["c_friendship_day", "celebration", 2, "{character} says today is a good day to celebrate friends. Everyone gets a sticker.", {}],
	["c_rest_day", "celebration", 2, "Today is a rest day. {character} insists you take it slow.", {}],
	["c_new_moon", "celebration", 2, "New moon tonight. {character} says it's for fresh starts.", {}],
	["c_full_moon", "celebration", 2, "Full moon! {character} wants to dance under it.", {}],
	["c_first_week", "celebration", 1, "{character} says your world feels more like home every day.", {}],
	["c_tea_party", "celebration", 2, "{character} is hosting a tiny tea party in {room}. You're invited, of course.", {}],
	["c_quiet_day", "celebration", 2, "A quiet day. {character} says those count too.", {}],
	["c_thank_you", "celebration", 2, "{character} wants to say thank you. For nothing in particular. For being here.", {}],
	# Echoes (your own past; only when you opt in)
	["e_journal", "echo", 3, "A memory drifts back: \"{echo}\"", {"source": "journal"}],
	["e_chat", "echo", 3, "{character} remembers something you said: \"{echo}\"", {"source": "chat"}],
	["e_dream", "echo", 2, "You once wrote down a dream: {dream}. It's still here.", {"source": "dream"}],
	# More gentle everyday ones
	["s_rainbow", "sky", 2, "A rainbow after the rain. {character} wants to find where it ends.", {"sky": "clear"}],
	["f_candle", "found", 2, "A candle that smells like your favorite season is in {room}.", {"item": "Seasonal candle", "color": "#ff9f43"}],
	["r_together", "request", 2, "{character} wants to just sit with you for a bit. No talking needed.", {"quest": "talk", "topic": "hello"}],
	["g_garden", "rumor", 2, "{character} heard {other} talking to the plants. The plants seemed happy.", {}],
	["c_cozy", "celebration", 2, "{character} says today is officially Extra Cozy Day.", {}],
	["v_cartographer_cat", "visitor", 2, "A cat in a tiny hat, Miso, is napping in {room}. It may or may not be a famous explorer.", {"name": "Miso", "look": "sleepy", "about": "A cat in a tiny hat who claims to be a famous explorer."}],
]


static func entries() -> Array:
	var out: Array = []
	for e in ENTRIES:
		out.append({"id": e[0], "kind": e[1], "weight": float(e[2]), "text": e[3], "extra": e[4], "builtin": true})
	return out
