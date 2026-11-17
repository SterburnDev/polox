extends "res://scripts/ui/screen_panel.gd"
## Advanced per-cell memory/event editor.

const TileLayers := preload("res://scripts/world/tile_layers.gd")

var build: Node
var layer_id := ""
var cell := Vector2i.ZERO


func _ready() -> void:
	setup("Tile event", Vector2(720, 500))
	var layer := TileLayers.find(build.world.room.data, layer_id)
	var value := TileLayers.get_cell(layer, cell.x, cell.y)
	var old: Dictionary = value.get("event", {}) if value.get("event") is Dictionary else {}
	var trigger := UiKit.option(["When stepped on", "When clicked"], 0 if str(old.get("trigger", "step")) == "step" else 1)
	trigger.tooltip_text = "Choose whether this fires when the player steps on the tile or interacts with it"
	body.add_child(UiKit.field_row("Trigger", trigger, 100))
	var actions := ["Show a message", "Play a sound", "Teleport to room", "Change lighting", "Show / hide a layer"]
	var action_ids := ["text", "sound", "teleport", "lighting", "layer"]
	var action := UiKit.option(actions, maxi(0, action_ids.find(str(old.get("action", "text")))))
	action.tooltip_text = "The small action this tile performs"
	body.add_child(UiKit.field_row("Action", action, 100))
	var content := UiKit.line_edit("Message, sound, room id, colour or layer|show")
	content.text = str(old.get("value", ""))
	body.add_child(UiKit.field_row("Value", content, 100))
	var once := CheckBox.new()
	once.text = "Only once (saved with the room)"
	once.tooltip_text = "One-time memories stay done after leaving and returning"
	once.button_pressed = bool(old.get("once", true))
	body.add_child(once)
	body.add_child(UiKit.para("Examples: text: “This was where I first tried painting.” · teleport: garden · lighting: #ffd166 · layer: fog|hide", 16, ThemeBuilder.MUTED))
	body.add_child(UiKit.button("Save event", func():
		var ev := {"trigger": "step" if trigger.selected == 0 else "interact",
			"action": action_ids[action.selected], "value": content.text.substr(0, 300), "once": once.button_pressed}
		build.edit_room(func(data):
			var l := TileLayers.find(data, layer_id)
			var c := TileLayers.get_cell(l, cell.x, cell.y)
			if not c.is_empty():
				c["event"] = ev
				c.erase("event_done")
				TileLayers.put(l, cell.x, cell.y, c))
		close(), 150))
	body.add_child(UiKit.button("Remove event", func():
		build.edit_room(func(data):
			var l := TileLayers.find(data, layer_id)
			var c := TileLayers.get_cell(l, cell.x, cell.y)
			c.erase("event")
			c.erase("event_done")
			if not c.is_empty():
				TileLayers.put(l, cell.x, cell.y, c))
		close(), 130))
