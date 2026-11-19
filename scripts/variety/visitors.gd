extends RefCounted
## Visitor Moments: a wandering stranger with a small story stays in a room
## for the day. You can invite them to move in; otherwise they wander on the
## next day, and nothing is missed: who they were (name, look, story) is kept,
## and Menu > Story > Collection can invite them back any time. Also the
## "found object" Moments: a small keepsake appears as a pickup.

const Defaults := preload("res://scripts/core/defaults.gd")
const Doll := preload("res://scripts/characters/doll.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")
const Items := preload("res://scripts/items/items.gd")
const RoomEditor := preload("res://scripts/world/room_editor.gd")
const Clock := preload("res://scripts/variety/clock.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")

const PASSED_MAX := 40   # travelers remembered after they wander on

const FACES: PackedStringArray = ["neutral", "happy", "sad", "surprised"]


## Makes the visitor of a Moment ({extra: {name, look, about}, room}). Returns its id ("" if it can't).
static func arrive(m: Dictionary, date: String) -> String:
	var ex: Dictionary = m.get("extra", {})
	var vname := str(ex.get("name", "A traveler"))
	var room := str(m.get("room", ""))
	if room == "" or not SaveManager.room_exists(room):
		room = str(GameState.world.get("start_room", "home"))
	var id := SaveManager.unique_id(vname, SaveManager.list_characters())
	var c := Defaults.character(id, vname)
	c["personality"] = str(ex.get("about", "A kind traveler passing through."))
	c["backstory"] = "Just passing through your world today. %s" % str(ex.get("about", ""))
	c["speech_style"] = "warm, a little mysterious, short sentences"
	c["relationship_to_player"] = "a traveler you just met"
	c["home_room"] = room
	c["visitor"] = true
	c["visitor_date"] = date
	c["visitor_look"] = str(ex.get("look", "cozy"))
	c["voice_sound"] = "soft"
	var recipe := Doll.preset(str(ex.get("look", "cozy")))
	var dir := SaveManager.character_dir(id)
	JsonUtil.ensure_dir(dir.path_join("expressions"))
	var faces := {}
	for f in FACES:
		var rel := "expressions/%s.png" % f
		Doll.compose(recipe, f).save_png(dir.path_join(rel))
		faces[f] = rel
	c["expressions"] = faces
	GameState.save_character(c)
	return id


## Visitors from earlier days who weren't invited to stay wander on.
static func farewell_old(today: String) -> PackedStringArray:
	var gone := PackedStringArray()
	for id in GameState.characters.keys():
		var c: Dictionary = GameState.characters[id]
		if bool(c.get("visitor", false)) and str(c.get("visitor_date", "")) != today:
			var about := str(c.get("personality", ""))
			var list := passed()
			list.append({"name": str(c.get("name", "A traveler")), "look": str(c.get("visitor_look", "cozy")), "about": about, "met": str(c.get("visitor_date", ""))})
			while list.size() > PASSED_MAX:
				list.pop_front()
			VarietySave.data()["passed_visitors"] = list
			VarietySave.save()
			GameState.characters.erase(id)
			SaveManager.delete_character(id)
			gone.append(id)
	return gone


## Travelers who wandered on (oldest first): [{name, look, about, met}].
static func passed() -> Array:
	var v: Variant = VarietySave.data().get("passed_visitors", [])
	return (v as Array).duplicate() if v is Array else []


## Invites a traveler who passed through back, to stay, in `room`. Returns their new id ("" if none).
static func invite_back(index: int, room: String) -> String:
	var list := passed()
	if index < 0 or index >= list.size():
		return ""
	var rec: Dictionary = list[index]
	var id := arrive({"extra": {"name": rec.get("name", "A traveler"), "look": rec.get("look", "cozy"), "about": rec.get("about", "")}, "room": room}, Clock.today())
	if id == "" or not invite(id):
		return ""
	list.remove_at(index)
	VarietySave.data()["passed_visitors"] = list
	VarietySave.save()
	return id


## They stay: a new neighbor, a normal resident from now on.
static func invite(id: String) -> bool:
	var c := GameState.get_character(id)
	if c.is_empty() or not bool(c.get("visitor", false)):
		return false
	c["visitor"] = false
	c.erase("visitor_date")
	c["relationship_to_player"] = "a new neighbor who decided to stay"
	GameState.save_character(c)
	return true


## A found-object Moment: a keepsake item (made once) as a pickup on a free cell of its room.
static func place_found(m: Dictionary) -> Dictionary:
	var ex: Dictionary = m.get("extra", {})
	var item_name := str(ex.get("item", "Small treasure"))
	var item_id := ""
	for it in Items.all():
		if str(it.get("name", "")) == item_name and "found" in (it.get("tags", []) as Array):
			item_id = str(it.id)
	if item_id == "":
		var it := Items.defaults("keepsake")
		it["name"] = item_name
		it["flavor"] = "Found on %s. %s" % [Clock.today(), str(m.get("text", ""))]
		it["tags"] = ["found", "keepsake"]
		it["auto_icon"] = {"shape": "gem", "color": str(ex.get("color", "#c9b6ff"))}
		item_id = Items.save_item(it)
	var room_id := str(m.get("room", ""))
	if room_id == "" or not SaveManager.room_exists(room_id):
		return {}
	var room := SaveManager.load_room(room_id)
	var w := int(room.get("size", {}).get("w", 12))
	var d := int(room.get("size", {}).get("d", 10))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(m.get("id", "")) + Clock.today())
	for attempt in 40:
		var x := rng.randi_range(1, w - 2)
		var z := rng.randi_range(1, d - 2)
		if RoomEditor.object_at(room, x, z).is_empty() and RoomEditor.stack_top(room, x, z) == 0.0:
			var o := RoomEditor.add_object(room, x, z, "pickup")
			if o.is_empty():
				continue
			o["item"] = item_id
			o["count"] = 1
			o["respawn"] = "once"
			o["taken"] = ""
			o["moment"] = str(m.get("id", ""))
			SaveManager.save_room(room)
			return o
	return {}
