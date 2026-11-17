extends RefCounted
## Giving items to friends. Every friend has editable liked and disliked
## tags; an item's tags (plus its type and the words in its name) decide the
## reaction, which shifts mood and closeness by simple, readable rules. The
## last few gifts are remembered and shown to the AI.

const Items := preload("res://scripts/items/items.gd")

const PER_DAY := 3          # gifts per friend per day
const REMEMBERED := 8       # gifts kept in the friend's file for the AI
const MOOD := {"love": 0.15, "like": 0.08, "nice": 0.04, "meh": -0.02}
const AFFINITY := {"love": 6.0, "like": 3.0, "nice": 2.0, "meh": 0.5}
const MOOD_EFFECT := {"small": 0.05, "medium": 0.1, "big": 0.15}
const FEELINGS := {
	"love": "It matches what you love! React with big, genuine delight.",
	"like": "You like it. React warmly.",
	"meh": "It's honestly not your taste, but you're touched by the thought; react kindly and a little awkwardly.",
	"nice": "React with warm thanks.",
}
const HOW_WORDS := {"love": "loved it", "like": "liked it", "nice": "said thanks", "meh": "politely accepted it"}
const STOPWORDS: PackedStringArray = ["the", "and", "with", "your", "you", "for", "from", "that", "this", "very", "little", "some"]


## A friend's liked/disliked tags (stored as an array; a comma string is accepted too).
static func tags(c: Dictionary, key: String) -> PackedStringArray:
	var raw: Variant = c.get(key, [])
	var list: Array = raw if raw is Array else Items.parse_tags(str(raw))
	var out := PackedStringArray()
	for t in list:
		var s := str(t).strip_edges().to_lower()
		if s != "":
			out.append(s)
	return out


## Turns "tea, rainy days and your stories" into ["tea", "rainy days", "stories"]
## (used once to give older friends tags from their Likes/Dislikes text).
static func derive_tags(text: String) -> Array:
	var out: Array = []
	for part in text.to_lower().replace(" and ", ",").replace("&", ",").replace(";", ",").replace(".", ",").split(","):
		var words := PackedStringArray()
		for w in part.strip_edges().split(" ", false):
			if not w in ["your", "the", "a", "an", "my", "their"]:
				words.append(w)
		var s := " ".join(words).strip_edges()
		if s.length() >= 3 and not s in out:
			out.append(s)
	return out.slice(0, 8)


## True if two tags are the same thing ("book" ~ "books", "rainy days" ~ "rainy").
static func tag_match(tag_a: String, tag_b: String) -> bool:
	var a := tag_a.strip_edges().to_lower()
	var b := tag_b.strip_edges().to_lower()
	if a == "" or b == "":
		return false
	if a == b:
		return true
	for wa in a.split(" ", false):
		for wb in b.split(" ", false):
			if wa == wb and wa.length() >= 3:
				return true
			if wa.length() >= 4 and wb.length() >= 4 and (wa.begins_with(wb) or wb.begins_with(wa)):
				return true
	return false


## What a friend can "see" about an item: its tags, its type and its name.
static func item_tags(item: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for t in item.get("tags", []):
		out.append(str(t).to_lower())
	out.append(str(item.get("category", "")))
	if str(item.get("slot", "")) != "":
		out.append(str(item.slot))
	for raw in str(item.get("name", "")).to_lower().split(" ", false):
		var w := raw.strip_edges().trim_suffix("!").trim_suffix(",")
		if w.length() >= 3 and not w in STOPWORDS:
			out.append(w)
	return out


static func _matches(have: PackedStringArray, wanted: PackedStringArray) -> int:
	var n := 0
	for w in wanted:
		for h in have:
			if tag_match(h, w):
				n += 1
				break
	return n


## "love" / "like" / "nice" / "meh".
static func reaction(c: Dictionary, item: Dictionary) -> String:
	var have := item_tags(item)
	var likes := _matches(have, tags(c, "liked_tags"))
	var dislikes := _matches(have, tags(c, "disliked_tags"))
	if dislikes > likes:
		return "meh"
	var rare := Items.rarity_rank(str(item.get("rarity", "common"))) >= 3
	if likes >= 2 or (likes >= 1 and rare):
		return "love"
	if likes == 1:
		return "like"
	return "nice"


static func gifts_today(c: Dictionary) -> int:
	return int(c.get("gifts_today", 0)) if str(c.get("gift_day", "")) == Time.get_date_string_from_system() else 0


static func can_gift(c: Dictionary) -> bool:
	return gifts_today(c) < PER_DAY


static func mood_delta(how: String, item: Dictionary) -> float:
	var d: float = MOOD.get(how, 0.04)
	var e: Dictionary = item.get("effect", {})
	if str(e.get("type", "")) == "mood":
		d += float(MOOD_EFFECT.get(str(e.get("value", "small")), 0.05))
	return d


## Closeness gained: bigger for loved and rarer gifts, halved after the first gift of the day.
static func affinity_delta(how: String, item: Dictionary, nth_today: int) -> float:
	var d: float = AFFINITY.get(how, 1.0) + Items.rarity_rank(str(item.get("rarity", "common"))) * 0.5
	return d if nth_today <= 1 else d * 0.5


## Writes the gift into the friend's file (counters + the remembered list).
static func record(c: Dictionary, item: Dictionary, how: String) -> int:
	var today := Time.get_date_string_from_system()
	var n := gifts_today(c) + 1
	c["gift_day"] = today
	c["gifts_today"] = n
	c["last_gift_day"] = today
	var got: Array = c.get("gifts_received", []) if c.get("gifts_received") is Array else []
	got.append({"item": str(item.get("id", "")), "name": str(item.get("name", "")), "how": how, "day": today})
	while got.size() > REMEMBERED:
		got.pop_front()
	c["gifts_received"] = got
	return n


## The system-prompt hint for the moment of giving.
static func hint(item: Dictionary, how: String) -> String:
	var desc := str(item.get("name", "something"))
	if str(item.get("flavor", "")) != "":
		desc += " (\"%s\")" % str(item.flavor).substr(0, 140)
	return "The player just gave you a gift: %s, a %s %s. %s Mention the gift specifically." % [desc, Items.rarity_name(str(item.get("rarity", "common"))).to_lower(), Items.category_name(str(item.get("category", ""))).to_lower(), FEELINGS.get(how, "")]


## "Gifts from Sam so far: Moon cookie (loved it), ..." for the character's prompt.
static func context_line(c: Dictionary, you: String) -> String:
	var got: Array = c.get("gifts_received", []) if c.get("gifts_received") is Array else []
	if got.is_empty():
		return ""
	var bits := PackedStringArray()
	for g in got.slice(maxi(0, got.size() - 5)):
		if g is Dictionary:
			bits.append("%s (%s)" % [g.get("name", "?"), HOW_WORDS.get(str(g.get("how", "")), "kept it")])
	return "Gifts %s gave you recently: %s." % [you, ", ".join(bits)]
