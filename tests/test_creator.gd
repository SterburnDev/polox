extends "res://tests/test_case.gd"
## Character Creator: canvas tools, undo/redo depth, and a full
## create-save-talk round trip done entirely through the Creator.

const PaintCanvas := preload("res://scripts/ui/paint_canvas.gd")
const CharacterCreator := preload("res://scripts/ui/character_creator.gd")
const StarterContent := preload("res://scripts/core/starter_content.gd")
const Conversation := preload("res://scripts/ai/conversation.gd")

const RED := Color(1, 0, 0, 1)


func _canvas(n: int = 16) -> Control:
	var c := PaintCanvas.new()
	tree.root.add_child(c)
	c.size = Vector2(320, 320)
	c.set_image(PaintCanvas._blank(n))
	c.color = RED
	return c


func _click(c: Control, px: Vector2i, release: bool = true) -> void:
	var cell: float = c._cell()
	var pos: Vector2 = c._origin() + (Vector2(px) + Vector2(0.5, 0.5)) * cell
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	c._gui_input(e)
	if release:
		var up := e.duplicate()
		up.pressed = false
		c._gui_input(up)


func _drag(c: Control, a: Vector2i, b: Vector2i) -> void:
	_click(c, a, false)
	var m := InputEventMouseMotion.new()
	m.position = c._origin() + (Vector2(b) + Vector2(0.5, 0.5)) * c._cell()
	c._gui_input(m)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	c._gui_input(up)


func test_pencil_brush_and_eraser() -> void:
	var c := _canvas()
	_click(c, Vector2i(3, 3))
	eq(c.image.get_pixel(3, 3), RED, "pencil paints")
	c.brush = 3
	_click(c, Vector2i(8, 8))
	eq(c.image.get_pixel(7, 7), RED, "3px brush covers neighbours")
	eq(c.image.get_pixel(9, 9), RED)
	c.tool = "eraser"
	c.brush = 1
	_click(c, Vector2i(3, 3))
	eq(c.image.get_pixel(3, 3).a, 0.0, "eraser clears")
	c.queue_free()


func test_drag_draws_continuous_line() -> void:
	var c := _canvas()
	_drag(c, Vector2i(0, 5), Vector2i(10, 5))
	var gaps := 0
	for x in 11:
		if c.image.get_pixel(x, 5) != RED:
			gaps += 1
	eq(gaps, 0, "no gaps in a fast stroke")
	eq(c._undo.size(), 1, "one stroke = one undo step")
	c.queue_free()


func test_mirror_fill_and_picker() -> void:
	var c := _canvas()
	c.mirror = true
	_click(c, Vector2i(2, 4))
	eq(c.image.get_pixel(13, 4), RED, "mirrored pixel painted")
	c.mirror = false
	c.tool = "fill"
	c.color = Color(0, 0, 1, 1)
	_click(c, Vector2i(8, 12))
	eq(c.image.get_pixel(0, 0), Color(0, 0, 1, 1), "fill spreads through empty space")
	eq(c.image.get_pixel(2, 4), RED, "fill stops at other colors")
	c.tool = "picker"
	_click(c, Vector2i(2, 4))
	eq(c.color, RED, "picker grabs color")
	c.queue_free()


## A color the picture keeps as the same 8 bits as the area it fills used to refill the same pixels
## forever: the game froze while memory climbed.
func test_fill_with_a_nearly_identical_color_ends() -> void:
	var c := _canvas(16)
	c.image.fill(Color8(51, 102, 153))
	c.flood_fill(Vector2i(3, 3), Color(0.2015, 0.4, 0.6))
	eq(c.image.get_pixel(15, 15), Color8(51, 102, 153), "the fill ends, and the picture keeps its color")
	c.tool = "fill"
	c.color = Color(0, 0, 1, 1)
	_click(c, Vector2i(0, 0))
	eq(c.image.get_pixel(15, 15), Color(0, 0, 1, 1), "a real change still fills the whole area")
	c.queue_free()


func test_undo_redo_at_least_fifty_steps() -> void:
	var c := _canvas(32)
	for i in 60:
		_click(c, Vector2i(i % 32, int(i / 32.0)))
	check(c._undo.size() >= 50, "keeps >= 50 undo steps (has %d)" % c._undo.size())
	for i in 55:
		c.undo()
	eq(c.image.get_pixel(5, 0).a, 0.0, "undone 55 strokes back")
	eq(c.image.get_pixel(4, 0), RED, "the first 5 strokes remain")
	for i in 55:
		c.redo()
	eq(c.image.get_pixel(27, 1), RED, "redo restores")
	c.queue_free()


func test_resize_and_import() -> void:
	var c := _canvas(16)
	_click(c, Vector2i(1, 1))
	c.resize_grid(32)
	eq(c.grid_size(), 32)
	eq(c.image.get_pixel(2, 2), RED, "nearest upscale keeps pixels crisp")
	c.undo()
	eq(c.grid_size(), 16, "resize is undoable")
	var photo := Image.create(200, 100, false, Image.FORMAT_RGBA8)
	photo.fill(Color(0, 1, 0, 1))
	c.import_image(photo)
	eq(c.grid_size(), 16, "import keeps grid size")
	eq(c.image.get_pixel(8, 8).g, 1.0, "imported content")
	eq(c.image.get_pixel(8, 0).a, 0.0, "padded to square, not stretched")
	c.queue_free()


func test_create_character_with_three_faces_and_talk() -> void:
	fresh_save_root()
	StarterContent.create_world("Test World", "Sam")
	GameState.load_world()
	AIClient.configure({"preset": "mock"})
	var cc := CharacterCreator.new()
	cc.new_character()
	tree.root.add_child(cc)
	await frames(2)
	cc.canvas.size = Vector2(320, 320)
	cc.card.name_edit.text = "Pip Squeak"
	cc.card.fields["personality"].text = "Bouncy and brave."
	for face in ["neutral", "happy", "sad"]:
		cc.select_slot(face)
		_click(cc.canvas, Vector2i(10, 10))
		_click(cc.canvas, Vector2i(12, 14))
	check(cc.save(), "saved")
	var id: String = cc.char_id
	eq(id, "pip_squeak")
	var c := SaveManager.load_character(id)
	eq(c.name, "Pip Squeak")
	eq(c.personality, "Bouncy and brave.")
	eq(c.expressions.size(), 3, "only painted faces saved")
	for face in ["neutral", "happy", "sad"]:
		check(FileAccess.file_exists(SaveManager.expression_path(c, face)), "%s.png written" % face)
	eq(c.home_room, GameState.current_room_id, "moves into the current room")
	cc.queue_free()
	var reply: Dictionary = await Conversation.new().player_says(id, "hi Pip!")
	check(not reply.failed, "can talk to the new friend")
	check(str(reply.segments[0].emotion) in ["neutral", "happy", "sad"], "uses one of its 3 faces")
	eq(ChatLog.read_all(id).size(), 2)


func test_creator_refuses_without_neutral() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "")
	GameState.load_world()
	var cc := CharacterCreator.new()
	cc.new_character()
	tree.root.add_child(cc)
	await frames(1)
	check(not cc.save(), "can't save a blank character")
	eq(SaveManager.list_characters().size(), 0)
	cc.queue_free()


func test_custom_expression_slot() -> void:
	fresh_save_root()
	StarterContent.create_world("T", "")
	var id := StarterContent.create_mochi()
	GameState.load_world()
	var cc := CharacterCreator.new()
	cc.edit_character(id)
	tree.root.add_child(cc)
	await frames(1)
	cc.add_slot("Smug")
	eq(cc.current, "smug", "new slot selected")
	check(not cc.slots["smug"].is_invisible(), "starts as a copy of neutral")
	check(cc.save(), "saved")
	check(SaveManager.load_character(id).expressions.has("smug"), "custom face saved")
	cc.queue_free()


func test_avatar_mode_paints_a_player_form() -> void:
	const PlayerLook := preload("res://scripts/characters/player_look.gd")
	await frames(2)
	var orphans_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	fresh_save_root()
	StarterContent.create_world("T", "Sam")
	GameState.load_world()
	var cc := CharacterCreator.new()
	cc.edit_player_form("dark")
	tree.root.add_child(cc)
	await frames(1)
	check(cc.card == null, "an avatar does not allocate an unowned personality panel")
	eq(cc.order.size(), 8, "all eight faces, like a friend")
	check(not cc.slots["neutral"].is_invisible(), "starts from the form's current (doll) faces")
	cc.canvas.size = Vector2(320, 320)
	cc.canvas.color = RED
	_click(cc.canvas, Vector2i(0, 0))
	check(cc.save(), "saved")
	eq(PlayerLook.form_data("dark").mode, "custom", "the form is now hand-drawn")
	var img := Image.load_from_file(SaveManager.abs_path(PlayerLook.face_rel("dark", "neutral")))
	eq(img.get_pixel(0, 0), RED, "new look written to player/dark/")
	eq(PlayerLook.form_data("real").mode, "doll", "the other form is untouched")
	cc.queue_free()
	await frames(2)
	eq(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), orphans_before, "closing the avatar editor leaves no orphan controls")


