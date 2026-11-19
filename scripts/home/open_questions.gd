extends RefCounted
## "Things Polox isn't sure about": a calm list of open questions about your home, from the research
## ("Is the half bath next to the kitchen?") and from the house itself ("What colour are the kitchen
## walls?"). You answer any, skip any, or dismiss them; answering one changes the house right away. No
## counts, no badges, nothing asks you unprompted (a gentle line when you're home only if you turn
## reminders on in Settings > Light World).
##
## Question: {"id", "text", "kind": "free" | "color" | "floor" | "yesno" | "view", "room": "<id>", "level": int,
##            "room_name": "", "state": "open" | "answered" | "dismissed", "answer": "", "source": "research" | "house"}

const HomeStore := preload("res://scripts/home/home_store.gd")
const HomeEdit := preload("res://scripts/home/home_edit.gd")
const TellPolox := preload("res://scripts/home/tell_polox.gd")
const LayoutBuilder := preload("res://scripts/home/layout_builder.gd")

const VIEWS := [["street", "The street"], ["yard", "A yard"], ["trees", "Trees"], ["house", "Another house"], ["sky", "Only sky"]]


## Questions the house itself raises (added once each; research questions come from home_model.make).
static func generate(home: Dictionary) -> Array:
	var qs: Array = home.get("open_questions", []) if home.get("open_questions") is Array else []
	var have := {}
	for q in qs:
		have[str(q.get("id", ""))] = true
	var plan: Dictionary = home.get("plan", {})
	var answers: Dictionary = home.get("answers", {}) if home.get("answers") is Dictionary else {}
	var edits: Array = home.get("edits", []) if home.get("edits") is Array else []
	var mine: Dictionary = answers.get("my_room", {}) if answers.get("my_room") is Dictionary else {}
	if not mine.has("view") and not have.has("h_view"):
		qs.append({"id": "h_view", "text": "What do you see from your bedroom window?", "kind": "view", "state": "open", "source": "house"})
	for f in plan.get("floors", []):
		for r in f.get("rooms", []):
			var k := str(r.kind)
			var painted := edits.any(func(e): return str(e.get("type", "")) == "wall" and str(e.get("room", "")) == str(r.id))
			if k in ["kitchen", "living"] and not painted and not have.has("h_wall_" + str(r.id)):
				qs.append({"id": "h_wall_" + str(r.id), "text": "What colour are the walls in the %s?" % str(r.name).to_lower(), "kind": "color",
					"room": str(r.id), "level": int(f.level), "room_name": str(r.name), "state": "open", "source": "house"})
	var ground: Dictionary = HomeEdit.floor_of(plan, 0)
	var back_door := (ground.get("edges", []) as Array).any(func(e): return bool(e.get("door", false)) and bool(e.get("outer", false)) and int(e.get("z", -1)) == 0 and str(e.get("dir", "")) == "h")
	if not ground.is_empty() and not back_door and not have.has("h_back_door"):
		qs.append({"id": "h_back_door", "text": "Is there a back door?", "kind": "yesno", "state": "open", "source": "house"})
	home["open_questions"] = qs
	return qs


static func open_list(home: Dictionary) -> Array:
	return (home.get("open_questions", []) as Array).filter(func(q): return str(q.get("state", "open")) == "open")


static func _find(home: Dictionary, id: String) -> Dictionary:
	for q in home.get("open_questions", []):
		if str(q.get("id", "")) == id:
			return q
	return {}


## Answers a question: the house changes right away (one batch on the timeline), the question goes.
## Returns the commit result ({} when the answer changed nothing in the house, e.g. a view or a "no").
static func answer(id: String, value: Variant) -> Dictionary:
	var home := HomeStore.load_home()
	var q := _find(home, id)
	if q.is_empty() or str(q.get("state", "open")) != "open":
		return {}
	var edits: Array = []
	var plan: Dictionary = home.get("plan", {})
	match str(q.get("kind", "")):
		"color":
			edits.append({"type": "wall", "level": int(q.get("level", 0)), "room": str(q.get("room", "")), "room_name": str(q.get("room_name", "")), "color": str(value)})
		"floor":
			edits.append({"type": "floor", "level": int(q.get("level", 0)), "room": str(q.get("room", "")), "room_name": str(q.get("room_name", "")), "floor": str(value)})
		"yesno":
			if str(q.id) == "h_back_door" and bool(value):
				var e := _back_wall(plan)
				if not e.is_empty():
					edits.append({"type": "edge", "level": 0, "x": int(e.x), "z": int(e.z), "dir": "h", "to": "door"})
		"view":
			var a: Dictionary = home.get("answers", {})
			var mr: Dictionary = a.get("my_room", {}) if a.get("my_room") is Dictionary else {}
			mr["view"] = str(value)
			a["my_room"] = mr
			home["answers"] = a
		_:
			# Free words: read like "Tell Polox about home"; anything it can't place is kept as a note.
			var proposal := TellPolox.read(str(value), plan)
			edits = proposal.changes
			if edits.is_empty():
				edits.append({"type": "note", "level": 0, "room": "", "room_name": "", "text": "%s %s" % [str(q.text), str(value)]})
	q["state"] = "answered"
	q["answer"] = str(value)
	q["answered"] = Time.get_datetime_string_from_system(false, false)
	HomeStore.save_home(home)
	if edits.is_empty():
		return {}
	for e in edits:
		e["source"] = "answer"
	return HomeEdit.commit(edits, "answer")


static func dismiss(id: String) -> void:
	var home := HomeStore.load_home()
	var q := _find(home, id)
	if q.is_empty():
		return
	q["state"] = "dismissed"
	HomeStore.save_home(home)


## The middle of the back wall of the kitchen (else any back room) on the ground floor.
static func _back_wall(plan: Dictionary) -> Dictionary:
	var ground := HomeEdit.floor_of(plan, 0)
	var best := {}
	for e in ground.get("edges", []):
		if bool(e.get("outer", false)) and str(e.get("dir", "")) == "h" and int(e.get("z", -1)) == 0 and not bool(e.get("window", false)):
			var r := int(e.get("b", -1))
			if r >= 0 and str(ground.rooms[r].kind) == "kitchen":
				return e
			if best.is_empty():
				best = e
	return best
