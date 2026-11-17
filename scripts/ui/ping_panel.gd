extends "res://scripts/ui/screen_panel.gd"
## Settings > Phone Link > Network test: Polox Ping inside the game. Starts the
## tiny test server (on whichever of 8765 / 8080 / 8888 are free: Phone Link
## may be using one), shows what ping_view.gd shows, and stops it on close.

const PingServer := preload("res://scripts/net/ping_server.gd")
const PingView := preload("res://scripts/ui/ping_view.gd")

var ping: Node


func _ready() -> void:
	setup("Network test (Polox Ping)", Vector2(1000, 680))
	ping = PingServer.new()
	ping.name = "PoloxPing"
	add_child(ping)
	var err: String = ping.start(SaveManager.root)
	if err != "":
		body.add_child(UiKit.para(err + " Close other copies of Polox Ping or Polox, then try again.", 18, Color("#ff8a8a")))
		return
	var view := PingView.new()
	view.big_size = 30
	body.add_child(view)
	if DisplayServer.get_name() != "headless":
		DisplayServer.screen_set_keep_on(true)   # an asleep PC can't answer the phone
	view.setup(ping)


func close() -> void:
	if ping:
		ping.stop()
	if DisplayServer.get_name() != "headless":
		DisplayServer.screen_set_keep_on(bool(get_tree().current_scene.get("phone_link") and get_tree().current_scene.phone_link.running and get_tree().current_scene.phone_link.keep_awake))
	super.close()
