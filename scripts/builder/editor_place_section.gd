extends VBoxContainer
## Build mode > Place, the top of the tab: what kind of place this is (indoors, outdoors, somewhere
## strange), its sky, and "Add a place" on any side (a new place just like this one, joined there).
## Advanced (one click): which walls stand, the ground, and up to three background layers.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Places := preload("res://scripts/world/places.gd")

const ARROWS := {"north": "↑ North", "east": "East →", "south": "↓ South", "west": "← West"}

var build: Node
var advanced := false
var _loading := false


func bind(build_mode: Node) -> void:
	build = build_mode
	add_theme_constant_override("separation", 6)
	refresh()


func _data() -> Dictionary:
	return build.world.room.data


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	_loading = true
	var data := _data()
	add_child(UiKit.label("Place", 18, ThemeBuilder.MUTED))
	var kinds := UiKit.option(Array(Places.KINDS).map(func(k): return str(Places.KIND_LABELS[k])), maxi(0, Places.KINDS.find(Places.kind(data))))
	kinds.custom_minimum_size.x = 0
	kinds.tooltip_text = "Indoors has walls; outdoors the ground goes on to the horizon; somewhere strange floats"
	kinds.item_selected.connect(func(i):
		if not _loading:
			set_kind(Places.KINDS[i]))
	add_child(kinds)
	var bg := Places.background(data)
	var skies := UiKit.option(Array(Places.SKIES).map(func(s): return "Sky: " + str(Places.SKY_LABELS[s])), maxi(0, Places.SKIES.find(str(bg.sky))))
	skies.custom_minimum_size.x = 0
	skies.item_selected.connect(func(i):
		if not _loading:
			set_background("sky", Places.SKIES[i]))
	add_child(skies)
	add_child(UiKit.label("Add a place", 16, ThemeBuilder.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for side in ["north", "east", "south", "west"]:
		var taken := Places.edge(data, side)
		var b := UiKit.button(ARROWS[side] if taken == "" else "%s: %s" % [ARROWS[side], taken], func(): add_place(side), 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = taken != ""
		b.tooltip_text = "A new place just like this one, joined on this side (walk off the edge to get there)" if taken == "" else "Already joined to %s" % taken
		grid.add_child(b)
	add_child(grid)
	var more := UiKit.button(("▼ " if advanced else "▶ ") + "Walls, ground, background", func():
		advanced = not advanced
		refresh(), 0)
	add_child(more)
	if advanced:
		_advanced(data, bg)
	_loading = false


func _advanced(data: Dictionary, bg: Dictionary) -> void:
	var walls := Places.walls(data)
	var wrow := UiKit.flow_row(6)
	for side in Places.SIDES:
		var cb := CheckBox.new()
		cb.text = side.capitalize()
		cb.button_pressed = bool(walls[side])
		cb.disabled = Places.edge(data, side) != ""   # a join has no wall
		cb.toggled.connect(func(on):
			if not _loading:
				build.edit_room(func(d):
					var w := Places.walls(d)
					w[side] = on
					d["walls"] = w))
		wrow.add_child(cb)
	add_child(UiKit.label("Walls", 16, ThemeBuilder.MUTED))
	add_child(wrow)
	var ground := CheckBox.new()
	ground.text = "Ground to the horizon"
	ground.button_pressed = bool(bg.ground)
	ground.toggled.connect(func(on):
		if not _loading:
			set_background("ground", on))
	add_child(ground)
	add_child(UiKit.label("Background layers (far to near)", 16, ThemeBuilder.MUTED))
	var layers: Array = bg.layers
	for i in layers.size():
		var l: Dictionary = layers[i]
		var row := UiKit.hbox(4)
		var kind := UiKit.option(Array(Places.SILHOUETTES).map(func(s): return str(s).capitalize()), maxi(0, Places.SILHOUETTES.find(str(l.kind))))
		kind.custom_minimum_size.x = 0
		kind.item_selected.connect(func(k): _edit_layer(i, "kind", Places.SILHOUETTES[k]))
		row.add_child(kind)
		var color := ColorPickerButton.new()
		color.color = Color.from_string(str(l.color), Color("#4f7a5c"))
		color.custom_minimum_size = Vector2(44, 40)
		color.color_changed.connect(func(c): _edit_layer(i, "color", "#" + c.to_html(false)))
		row.add_child(color)
		var dist := UiKit.option(["Near", "Middle", "Far"], int(l.distance) - 1)
		dist.custom_minimum_size.x = 0
		dist.item_selected.connect(func(k): _edit_layer(i, "distance", k + 1))
		row.add_child(dist)
		row.add_child(UiKit.button("✕", func(): _remove_layer(i), 40))
		add_child(row)
	if layers.size() < Places.MAX_LAYERS:
		add_child(UiKit.button("+ Layer", func(): _add_layer(), 0))


func set_kind(k: String) -> void:
	build.edit_room(func(d):
		d["kind"] = k
		var w := Places.default_walls(k)
		for side in Places.edges(d):
			w[side] = false
		d["walls"] = w
		d["background"] = Places.default_background(k))
	refresh()


func set_background(key: String, value: Variant) -> void:
	build.edit_room(func(d):
		var b := Places.background(d)
		b[key] = value
		d["background"] = b)


func _edit_layer(i: int, key: String, value: Variant) -> void:
	build.edit_room(func(d):
		var b := Places.background(d)
		if i < (b.layers as Array).size():
			b.layers[i][key] = value
		d["background"] = b)


func _add_layer() -> void:
	build.edit_room(func(d):
		var b := Places.background(d)
		(b.layers as Array).append({"kind": "hills", "color": "#4f7a5c", "distance": 3, "seed": randi() % 1000})
		d["background"] = b)
	refresh()


func _remove_layer(i: int) -> void:
	build.edit_room(func(d):
		var b := Places.background(d)
		if i < (b.layers as Array).size():
			(b.layers as Array).remove_at(i)
		d["background"] = b)
	refresh()


## "Add a place to the east": made, joined both ways, saved; this place shows the join at once.
func add_place(side: String) -> void:
	var data := _data()
	if Places.edge(data, side) != "":
		return
	var copy := data.duplicate(true)
	var fresh := Places.add_beside(copy, side, SaveManager.list_rooms())
	if fresh.is_empty():
		return
	SaveManager.save_room(fresh)
	build.edit_room(func(d):
		d["edges"] = Places.edges(copy)
		d["walls"] = Places.walls(copy))
	GameState.notify("Made %s, joined on the %s side: walk off that edge to visit it." % [str(fresh.name), side])
	refresh()
