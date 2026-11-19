extends RefCounted
## Friend requests: a friend asks for something small you'd enjoy anyway ("Could we see a beach
## sometime?", "Spar with me in the Deep?"). At most two open at once, offered now and then (a
## new one only when there's room), no deadline, no reminder, and letting one go is fine. Doing it
## (counted from the world, from when it was asked) brings a thank-you, a Memory Book page and a
## little closeness.

const Story := preload("res://scripts/variety/story.gd")
const VarietySave := preload("res://scripts/variety/variety_save.gd")

const MAX_OPEN := 2
const KINDS := {
	"join": {"key": "joins", "text": "Could you add a place beside one of ours? I want to see what's past the edge."},
	"dark": {"key": "dark_visits", "text": "Let's peek into the Deep together sometime."},
	"battle": {"key": "battles", "text": "Spar with me? Just for fun!"},
	"spare": {"key": "spared", "text": "I like it when battles end kindly. Spare someone for me?"},
	"place": {"key": "places", "text": "Make a new place? Somewhere you'd like to be."},
	"crystal": {"key": "crystals", "text": "I heard there are crystals down in the Deep. Find one?"},
}


static func open() -> Array:
	var v := VarietySave.data()
	return (v.get("requests", []) as Array).filter(func(r): return r is Dictionary and str(r.get("state", "open")) == "open")


static func _save_list(list: Array) -> void:
	VarietySave.data()["requests"] = list
	VarietySave.save()


## A friend asks (if there's room). Returns the request or {}.
static func offer(giver_id: String, rng: RandomNumberGenerator, counts: Dictionary = {}) -> Dictionary:
	var all: Array = VarietySave.data().get("requests", []) if VarietySave.data().get("requests") is Array else []
	if open().size() >= MAX_OPEN or giver_id == "":
		return {}
	var have := counts if not counts.is_empty() else Story.counts()
	var taken := open().map(func(r): return str(r.kind))
	var choices: Array = KINDS.keys().filter(func(k): return not k in taken)
	if choices.is_empty():
		return {}
	var kind := str(choices[rng.randi() % choices.size()])
	var r := {"id": "r%d_%d" % [Time.get_unix_time_from_system(), rng.randi() % 1000], "giver": giver_id, "kind": kind,
		"text": str(KINDS[kind].text), "base": int(have.get(str(KINDS[kind].key), 0)), "state": "open", "asked": Time.get_datetime_string_from_system()}
	all.append(r)
	_save_list(all)
	return r


static func done_yet(r: Dictionary, counts: Dictionary = {}) -> bool:
	var have := counts if not counts.is_empty() else Story.counts()
	return int(have.get(str(KINDS.get(str(r.kind), {}).get("key", "")), 0)) > int(r.get("base", 0))


## Checks every open request; finished ones are thanked. Returns them.
static func check_all(counts: Dictionary = {}) -> Array:
	var have := counts if not counts.is_empty() else Story.counts()
	var all: Array = VarietySave.data().get("requests", []) if VarietySave.data().get("requests") is Array else []
	var finished: Array = []
	for r in all:
		if r is Dictionary and str(r.get("state", "")) == "open" and done_yet(r, have):
			r["state"] = "done"
			finished.append(r)
			var c := GameState.get_character(str(r.giver))
			if not c.is_empty():
				c["affinity"] = clampf(float(c.get("affinity", 0.0)) + 0.04, -1.0, 1.0)
				GameState.save_character(c)
				GameState.add_moment("%s's request" % str(c.get("name", "")), "\"%s\" You did it, and %s was so happy." % [str(r.text), str(c.get("name", ""))], str(r.giver), "request")
	if not finished.is_empty():
		_save_list(all)
	return finished


## Letting one go: no hard feelings, ever.
static func let_go(id: String) -> void:
	var all: Array = VarietySave.data().get("requests", []) if VarietySave.data().get("requests") is Array else []
	for r in all:
		if r is Dictionary and str(r.get("id", "")) == id:
			r["state"] = "let_go"
	_save_list(all)
