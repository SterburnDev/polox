extends "res://tests/test_case.gd"
## Leaving cleanly: work on other threads is told to stop and is joined, a lookup that was stopped
## says nothing more, calls put off to the end of the frame survive their node being freed, loops
## that wait for something end by themselves, the caches scripts keep are let go when the game
## closes, and the tests' own servers get ports nobody else has.

const BackgroundJob := preload("res://scripts/core/background_job.gd")
const MemoryRelief := preload("res://scripts/core/memory_relief.gd")
const AudioExit := preload("res://scripts/core/audio_exit.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const HttpServer := preload("res://scripts/phone/http_server.gd")
const Research := preload("res://scripts/home/research.gd")
const SyncClient := preload("res://scripts/phone/sync_client.gd")
const PhoneServer := preload("res://scripts/phone/phone_server.gd")
const PingServer := preload("res://scripts/net/ping_server.gd")
const Osm := preload("res://scripts/home/osm.gd")
const Actor := preload("res://scripts/characters/actor.gd")
const LifeDirector := preload("res://scripts/characters/life_director.gd")
const PhoneExports := preload("res://scripts/phone/phone_exports.gd")
const MissYou := preload("res://scripts/variety/miss_you.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

const RECORDED := "res://tests/fixtures/home_research_madeup.json"


## A PC that takes one byte of every part it is sent: without a limit, sending would go on for as
## many rounds as the file has bytes.
class CrawlingPc extends Node:
	var asked := 0

	func request(_method: String, path: String, _body: PackedByteArray = PackedByteArray()) -> Dictionary:
		asked += 1
		var offset := int(path.get_slice("offset=", 1).get_slice("&", 0))
		return {"ok": true, "code": 200, "json": {"have": offset + 1}, "body": PackedByteArray(), "error": ""}


func _ms_since(t0: int) -> int:
	return Time.get_ticks_msec() - t0


# --- Ports ----------------------------------------------------------------------------------------

func test_free_ports_are_free_and_never_given_twice() -> void:
	var a := free_port()
	var b := free_port()
	check(a > 0 and b > 0 and a != b, "two ports, not the same one: %d, %d" % [a, b])
	var first := TCPServer.new()
	eq(first.listen(a, "127.0.0.1"), OK, "the port can be listened on")
	var second := TCPServer.new()
	check(second.listen(a, "127.0.0.1") != OK, "and only once (a second server on it is refused)")
	first.stop()
	var u := free_udp_port()
	var udp := PacketPeerUDP.new()
	eq(udp.bind(u, "127.0.0.1"), OK, "a UDP port too")
	udp.close()
	var run := free_port_run(2)
	check(run > 0, "two in a row")
	for k in 2:
		var s := TCPServer.new()
		eq(s.listen(run + k, "127.0.0.1"), OK, "port %d of the run" % k)
		s.stop()


func test_a_taken_port_means_the_next_one_not_a_failure() -> void:
	var tried: Array = []
	var server := TCPServer.new()
	var start := func(p: int) -> String:
		tried.append(p)
		if tried.size() < 3:
			return "Port %d is already in use." % p   # (taken in the meantime, twice)
		return "" if server.listen(p, "127.0.0.1") == OK else "refused"
	var before := failures.size()
	var port := listen_on_free_port(start, "the stand-in")
	eq(tried.size(), 3, "it went on to a third port")
	eq(port, int(tried[2]), "and says which one it got")
	eq(server.get_local_port(), port, "the server really listens there")
	eq(failures.size(), before, "no failure noted")
	server.stop()
	# Every port refused: a failure, after a bounded number of tries.
	var asked := [0]
	var never := func(_p: int) -> String:
		asked[0] += 1
		return "no"
	eq(listen_on_free_port(never, "the stand-in"), 0, "nothing listens")
	eq(int(asked[0]), LISTEN_TRIES, "it stopped trying")
	eq(failures.size(), before + 1, "and the test is told")
	failures.resize(before)   # (that failure was the point)


# --- Work on other threads --------------------------------------------------------------------------

func test_background_work_is_told_to_stop_when_the_game_closes() -> void:
	var state := {"stop": false, "rounds": 0}
	var work := func() -> String:
		while not bool(state["stop"]) and int(state["rounds"]) < 3000:   # (30 s, were it never told)
			OS.delay_msec(10)
			state["rounds"] = int(state["rounds"]) + 1
		return "told to stop" if bool(state["stop"]) else "ran to the end"
	var stop := func() -> void:
		state["stop"] = true
	var box := BackgroundJob.run(work, stop)
	await frames(3)   # the keeper joins the tree a moment after it's made
	var keeper: Node = BackgroundJob._keeper
	check(keeper != null and keeper.is_inside_tree(), "the keeper is in the tree")
	check(not bool(box.done), "(the work is still going)")
	var t0 := Time.get_ticks_msec()
	keeper._finish_all()   # what leaving the tree does
	check(_ms_since(t0) < 5000, "closing did not wait for the work to run out: %d ms" % _ms_since(t0))
	check(bool(box.done), "the thread was joined")
	eq(str(box.result), "told to stop", "because the work was told to stop first")
	check((keeper._jobs as Array).is_empty(), "nothing left to join")
	# Work without a stop hook is simply waited for.
	var quick := BackgroundJob.run(func() -> int: return 7)
	keeper._finish_all()
	eq(quick.result, 7, "short work ends by itself")


func test_a_keeper_made_in_the_last_frame_is_joined_and_freed() -> void:
	await frames(2)
	var usual: Node = BackgroundJob._keeper
	BackgroundJob._keeper = null
	var box := BackgroundJob.run(func() -> String:
		OS.delay_msec(30)
		return "done")
	var late: Node = BackgroundJob._keeper
	check(late != null and late != usual and late.get_parent() == null, "a new keeper that has not reached the tree yet")
	var late_id := late.get_instance_id()
	BackgroundJob.shutdown()
	check(bool(box.done) and str(box.result) == "done", "its thread was joined")
	check(instance_from_id(late_id) == null, "and it was freed")
	check(BackgroundJob._keeper == null, "nothing is kept")
	await frames(2)   # the call that would have put it in the tree finds it gone, and says nothing
	BackgroundJob._keeper = usual
	BackgroundJob.shutdown()   # a keeper that is in the tree is left to the tree
	check(usual == null or is_instance_valid(usual), "the usual keeper is untouched")


func test_the_qr_reader_hands_its_task_back() -> void:
	var scanner: Control = load("res://scripts/ui/qr_scanner.gd").new()
	tree.root.add_child(scanner)
	var seen: Array = []
	scanner.found.connect(func(text: String) -> void: seen.append(text))
	scanner.scanning = true
	scanner._busy = true
	scanner._job = {"done": true, "text": "a code"}
	scanner._task = WorkerThreadPool.add_task(func() -> void: pass)
	scanner._collect()
	eq(seen, ["a code"], "a finished reading is reported")
	eq(int(scanner._task), -1, "and its task handed back to the pool")
	check(not bool(scanner._busy), "the next picture may be read")
	# Closed while a picture is being read: waited for (a moment), not left with the pool.
	scanner._job = {"done": false, "text": ""}
	scanner._task = WorkerThreadPool.add_task(func() -> void: OS.delay_msec(60))
	tree.root.remove_child(scanner)
	eq(int(scanner._task), -1, "leaving the tree hands the task back too")
	eq(seen.size(), 1, "and reports nothing more")
	scanner.free()


# --- Lookups ----------------------------------------------------------------------------------------

func test_a_stopped_lookup_says_nothing_and_the_next_one_answers_once() -> void:
	var r: Node = Research.new()
	tree.root.add_child(r)
	var answers: Array = []
	r.finished.connect(func(res: Dictionary) -> void: answers.append(res))
	r.start_recorded(RECORDED, 0.4)    # would answer in about 0.8 s
	await frames(3)
	r.cancel()
	check(not bool(r.running), "stopped")
	r.start_recorded(RECORDED, 0.05)   # the next one, started at once
	var until := Time.get_ticks_msec() + 5000
	while answers.is_empty() and Time.get_ticks_msec() < until:
		await frames(1)
	await tree.create_timer(1.2).timeout   # past the moment the first one would have answered
	eq(answers.size(), 1, "one answer: the stopped lookup said nothing")
	check(not answers.is_empty() and bool(answers[0].get("ok", false)), "and it is the second one's")
	# The screen that asked closes mid-lookup: nothing more is said, nothing goes on waiting.
	r.start_recorded(RECORDED, 0.3)
	await frames(2)
	tree.root.remove_child(r)
	check(not bool(r.running), "leaving the tree stops it")
	await tree.create_timer(0.9).timeout
	eq(answers.size(), 1, "no answer after it left")
	r.free()


func test_a_request_in_flight_ends_when_the_lookup_is_stopped() -> void:
	var silent := TCPServer.new()   # takes the connection and never answers
	var port := listen_on_free_port(func(p: int) -> int: return silent.listen(p, "127.0.0.1"), "the silent server")
	var r: Node = Research.new()
	tree.root.add_child(r)
	var http := HTTPRequest.new()
	http.timeout = 30.0
	r.add_child(http)
	eq(http.request("http://127.0.0.1:%d/" % port), OK, "(the request starts)")
	var box := {"res": null}
	var go := func() -> void:
		box["res"] = await r._answer(http, int(r._run))
	go.call()
	await frames(6)
	check(box.res == null, "(still waiting for the silent server)")
	var t0 := Time.get_ticks_msec()
	r.cancel()
	await frames(3)
	check(box.res is Array and int(box.res[0]) == HTTPRequest.RESULT_REQUEST_FAILED, "the wait ended at once, as a failed request")
	check(_ms_since(t0) < 2000, "long before the request's own 30 s")
	eq(http.get_http_client_status(), HTTPClient.STATUS_DISCONNECTED, "and the connection was closed")
	r.queue_free()
	silent.stop()
	await frames(2)


# --- Calls put off to the end of the frame ----------------------------------------------------------

func test_put_off_calls_survive_a_freed_control() -> void:
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(200, 120)
	tree.root.add_child(scroll)
	var rows := VBoxContainer.new()
	scroll.add_child(rows)
	for i in 30:
		var row := Label.new()
		row.text = "row %d" % i
		row.custom_minimum_size = Vector2(180, 30)
		rows.add_child(row)
	await frames(3)
	# The usual case first: it scrolls, it focuses.
	var last := rows.get_child(29) as Control
	UiKit.show_later(scroll, last)
	await frames(3)
	check(scroll.scroll_vertical > 0, "the row is scrolled into view: %d" % scroll.scroll_vertical)
	var button := Button.new()
	rows.add_child(button)
	UiKit.focus_later(button)
	await frames(2)
	check(tree.root.gui_get_focus_owner() == button, "the button has the focus")
	# Freed before the frame ends: nothing happens (and nothing is printed as an error).
	var gone := Label.new()
	rows.add_child(gone)
	UiKit.show_later(scroll, gone)
	gone.free()
	var gone_button := Button.new()
	rows.add_child(gone_button)
	UiKit.focus_later(gone_button)
	gone_button.free()
	UiKit.show_later(scroll, null)
	UiKit.show_later(null, last)
	UiKit.focus_later(null)
	# Out of the tree, or not inside that scroll area: nothing either.
	var elsewhere := Label.new()
	tree.root.add_child(elsewhere)
	UiKit.show_later(scroll, elsewhere)
	var loose := Button.new()
	UiKit.focus_later(loose)
	# The whole scroll area freed with a call waiting.
	UiKit.show_later(scroll, last)
	scroll.free()
	await frames(3)
	check(not is_instance_valid(last), "(the rows went with it)")
	elsewhere.free()
	loose.free()
	# A game that closed before its put-off question: not asked.
	var main := Node.new()
	var main_id := main.get_instance_id()
	main.free()
	MissYou.maybe_ask_later(main_id, "nobody")
	check(true, "a freed game is simply not asked")


# --- Loops that wait --------------------------------------------------------------------------------

func test_a_moment_out_of_the_tree_does_not_hold_the_game() -> void:
	var moment: Control = load("res://scripts/ui/moment.gd").new()   # in no tree: its wait() returns at once
	var fall: Control = load("res://scripts/ui/fall_overlay.gd").new()
	var t0 := Time.get_ticks_msec()
	var skipped: bool = await fall.play(moment, 3.0)
	check(_ms_since(t0) < 500, "the fall ends at once instead of spinning for its 3 s: %d ms" % _ms_since(t0))
	check(not skipped, "(not skipped: over)")
	eq(float(fall.progress), 1.0, "at its end state")
	moment.free()
	fall.free()


func test_sending_a_file_gives_up_after_a_fixed_number_of_rounds() -> void:
	var root := fresh_save_root()
	JsonUtil.ensure_dir(root.path_join("exports"))
	var path := root.path_join("exports").path_join("crawl.polox")
	var bytes := PackedByteArray()
	bytes.resize(4000)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var pc := CrawlingPc.new()
	tree.root.add_child(pc)
	var usual: int = PhoneExports.chunk_bytes
	PhoneExports.chunk_bytes = 1000
	var r: Dictionary = await PhoneExports.send_to_pc(pc, root, path)
	PhoneExports.chunk_bytes = usual
	check(not bool(r.ok), "a PC that takes a byte at a time is given up on")
	eq(pc.asked, (4000 / 1000 + 1) * PhoneExports.SEND_ROUNDS_FACTOR + 8, "after the rounds a file this size may take, not 4000 of them")
	check(str(r.error) != "", "and the reason is said: " + str(r.error))
	# A client that is gone (the phone screen closed): no round at all.
	pc.asked = 0
	tree.root.remove_child(pc)
	r = await PhoneExports.send_to_pc(pc, root, path)
	check(not bool(r.ok) and pc.asked == 0, "nothing is sent through a client that left the tree")
	pc.free()


func test_a_server_whose_thread_keeps_dying_gives_up() -> void:
	var s: Node = HttpServer.new()
	tree.root.add_child(s)
	listen_on_free_port(func(p: int) -> String: return s.start(p, "127.0.0.1"), "the engine")
	check(bool(s.running), "(running)")
	var gave_up := [0]
	s.gave_up.connect(func() -> void: gave_up[0] += 1)
	# Just restarted, and stopped again: not restarted every frame, the wait comes first.
	s._restart_run = 1
	s._restart_at = Time.get_ticks_msec()
	s._revive()
	eq(s.thread_restarts(), 0, "no restart inside the wait after the last one")
	check(bool(s.running), "still on")
	# The limit reached: off, and it says so once.
	s._restart_run = HttpServer.MAX_RESTARTS
	s._restart_at = Time.get_ticks_msec()
	s._thread_died = true
	s._revive()
	check(not bool(s.running), "the server is off")
	eq(int(gave_up[0]), 1, "and said so")
	eq(s.thread_restarts(), 0, "without one more restart")
	s._process(0.0)
	eq(int(gave_up[0]), 1, "only once")
	# Started again by hand: the count starts over.
	listen_on_free_port(func(p: int) -> String: return s.start(p, "127.0.0.1"), "the engine")
	eq(int(s._restart_run), 0, "a fresh start forgets the old restarts")
	s.stop()
	s.queue_free()
	await frames(1)


# --- What is let go when the game closes --------------------------------------------------------------

func test_every_cache_named_for_closing_exists() -> void:
	for entry in MemoryRelief.AT_EXIT:
		var path := str(entry[0])
		check(FileAccess.file_exists(path), "%s exists" % path)
		var source := FileAccess.get_file_as_string(path)
		var script := load(path) as Script
		for name in entry[1]:
			var declared := RegEx.create_from_string("(?m)^static var %s\\b" % str(name))
			check(declared.search(source) != null, "%s has a static variable %s" % [path.get_file(), name])
			var held: Variant = script.get(str(name))
			check(held == null or held is Dictionary or held is Array or held is Object, "%s.%s is something that can be emptied" % [path.get_file(), name])


func test_closing_lets_go_of_what_scripts_kept() -> void:
	# Something in a cache of each kind: a dictionary, and a single kept object.
	var item_art := load("res://scripts/items/item_art.gd") as Script
	(item_art.get("_cache") as Dictionary)["(test)"] = ImageTexture.new()
	var soul := load("res://scripts/ui/soul.gd") as Script
	soul.set("_tex", ImageTexture.new())
	var emptied := MemoryRelief.release_at_exit()
	check(emptied >= 2, "variables were emptied: %d" % emptied)
	check((item_art.get("_cache") as Dictionary).is_empty(), "the dictionary is empty")
	check(soul.get("_tex") == null, "the kept picture is let go")
	# And what was emptied is made again when it is next wanted.
	var icon: Variant = load("res://scripts/ui/vector_icons.gd")
	check(icon != null, "(scripts stay loaded: only what they kept is gone)")


func test_a_sound_is_stopped_and_dropped_as_its_player_leaves() -> void:
	AudioExit.settle()   # (start from nothing pending)
	var player := AudioStreamPlayer.new()
	tree.root.add_child(player)
	check(not AudioExit.release(player), "a player with no song: nothing to let go")
	check(not AudioExit.pending(), "and nothing to wait for")
	player.stream = AudioStreamGenerator.new()
	player.play()
	check(AudioExit.release(player), "a player with a song lets it go")
	check(player.stream == null and not player.playing, "stopped, and the song dropped")
	check(AudioExit.pending(), "the audio thread is owed its passes")
	var let_go_usec := Time.get_ticks_usec()
	var t0 := Time.get_ticks_msec()
	var passes := AudioExit.settle()
	eq(passes, AudioExit.MIX_PASSES, "settle() waits for the audio thread's passes, however long they take")
	var last_pass_usec := Time.get_ticks_usec() - int(AudioServer.get_time_since_last_mix() * 1000000.0)
	check(last_pass_usec > let_go_usec, "passes that began after the song was let go")
	check(_ms_since(t0) <= AudioExit.SETTLE_MAX_MS + 50, "and never past its limit: %d ms" % _ms_since(t0))
	check(not AudioExit.pending(), "once")
	t0 = Time.get_ticks_msec()
	eq(AudioExit.settle(), 0, "not again when nothing was let go")
	check(_ms_since(t0) < 10, "(that returns at once)")
	check(not AudioExit.release(null), "no player at all is fine too")
	check(not AudioExit.release(tree.root), "so is a node that is no player")
	# The game's own music player does this for both of its players when it leaves the tree.
	var music: Node = load("res://scripts/world/music_player.gd").new()
	tree.root.add_child(music)
	await frames(1)
	var held: Array = []
	for c in music.get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stream = AudioStreamGenerator.new()
			held.append(c)
	tree.root.remove_child(music)
	for c in held:
		check((c as AudioStreamPlayer).stream == null, "the music player dropped a song as it left")
	check(not AudioExit.pending(), "and gave the audio thread its pass")
	music.free()
	player.free()


# --- Async cancellation, tree exit & ephemeral ports ------------------------------------------------

class FakeNav extends RefCounted:
	func best_neighbor(target: Vector2i, _from: Vector2i) -> Vector2i:
		return target + Vector2i(1, 0)
	func path(from: Vector2i, dest: Vector2i) -> Array[Vector2i]:
		return [from, dest]

class FakeRoom extends Node:
	var nav := FakeNav.new()
	func cell_center(c: Vector2i) -> Vector3:
		return Vector3(float(c.x), 0.0, float(c.y))

class FakeWorld extends Node:
	var _transitioning := true
	var actors: Dictionary = {}
	var room: Node
	func _init() -> void:
		room = FakeRoom.new()
		add_child(room)


func test_sync_client_cancel_and_exit_tree() -> void:
	var silent := TCPServer.new()
	var port := listen_on_free_port(func(p: int) -> int: return silent.listen(p, "127.0.0.1"), "the silent sync server")
	var client := SyncClient.new()
	tree.root.add_child(client)
	client.base_url = "http://127.0.0.1:%d" % port
	client.token = "t"
	client.local_root = fresh_save_root("sync_cancel")
	var out := {"res": null}
	var go_sync := func() -> void:
		out["res"] = await client.sync()
	go_sync.call()
	await frames(4)
	check(client.busy, "sync starts busy")
	var t0 := Time.get_ticks_msec()
	client.cancel()
	await frames(4)
	check(_ms_since(t0) < 2000, "cancel unblocks sync at once")
	check(not client.busy, "busy clears on cancel")
	check(out.res is Dictionary and not bool(out.res.ok), "cancelled sync returns failure")
	# Leaving the tree while a direct request is in flight unblocks too.
	out["res"] = null
	var go_req := func() -> void:
		out["res"] = await client.request("GET", "/api/manifest")
	go_req.call()
	await frames(4)
	t0 = Time.get_ticks_msec()
	tree.root.remove_child(client)
	await frames(4)
	check(_ms_since(t0) < 2000, "removing SyncClient from tree unblocks pending request")
	check(out.res is Dictionary and str(out.res.get("error", "")) == "cancelled", "returns cancelled error")
	client.free()
	silent.stop()
	await frames(2)


func test_osm_exit_tree_and_concurrent_restart() -> void:
	var silent := TCPServer.new()
	var port := listen_on_free_port(func(p: int) -> int: return silent.listen(p, "127.0.0.1"), "the silent osm server")
	var osm := Osm.new()
	tree.root.add_child(osm)
	Osm._next_request_at = 0
	var out := {"res": null}
	var ticket := int(osm._generation)
	var go := func() -> void:
		out["res"] = await osm._request("http://127.0.0.1:%d/api/interpreter" % port, PackedStringArray(), HTTPClient.METHOD_GET, "", ticket)
	go.call()
	await frames(5)
	check(out.res == null, "osm request waits on silent socket")
	var t0 := Time.get_ticks_msec()
	tree.root.remove_child(osm)
	await frames(4)
	check(_ms_since(t0) < 2000, "leaving tree unblocks osm._request at once")
	check(out.res is Dictionary and str(out.res.get("code", "")) == "cancelled", "osm reports cancelled on exit")
	osm.free()
	silent.stop()
	await frames(2)


func test_research_concurrent_restart_and_cancel() -> void:
	var r: Node = Research.new()
	tree.root.add_child(r)
	var answers: Array = []
	r.finished.connect(func(res: Dictionary) -> void: answers.append(res))
	r.start_recorded(RECORDED, 0.5)
	await frames(2)
	r.start_recorded(RECORDED, 0.05)   # overlaps without explicit cancel(): prior run must abort cleanly
	var until := Time.get_ticks_msec() + 5000
	while answers.is_empty() and Time.get_ticks_msec() < until:
		await frames(1)
	await tree.create_timer(1.1).timeout
	eq(answers.size(), 1, "overlapping start_recorded suppresses the first answer")
	check(not bool(r.running), "not running once completed")
	r.cancel()
	r.queue_free()
	await frames(2)


func test_ai_client_list_models_cancel() -> void:
	var silent := TCPServer.new()
	var port := listen_on_free_port(func(p: int) -> int: return silent.listen(p, "127.0.0.1"), "the silent AI models server")
	AIClient.configure({"preset": "custom", "base_url": "http://127.0.0.1:%d/v1" % port, "model": "x", "api_key": "", "timeout_s": 10})
	var box := {"models": null}
	var go := func() -> void:
		box["models"] = await AIClient.list_models()
	go.call()
	await frames(5)
	check(box.models == null, "list_models waits on silent socket")
	var t0 := Time.get_ticks_msec()
	AIClient.cancel()
	await frames(4)
	check(_ms_since(t0) < 2000, "AIClient.cancel() unblocks list_models at once")
	check(box.models is PackedStringArray and (box.models as PackedStringArray).is_empty(), "returns empty model list when cancelled")
	AIClient.configure({"preset": "mock"})
	silent.stop()
	await frames(2)


func test_life_director_approach_exits_when_actor_stops() -> void:
	var world := FakeWorld.new()
	tree.root.add_child(world)
	var actor := Actor.new()
	world.add_child(actor)
	actor.setup("npc", "Mochi", null)
	world.actors["npc"] = actor
	var life := LifeDirector.new()
	world.add_child(life)
	life.setup(world)
	var done := {"arrived": null}
	var go := func() -> void:
		done["arrived"] = await life.approach("npc", Vector2i(4, 4), 2.0)
	go.call()
	await frames(3)
	check(done.arrived == null and actor.is_moving(), "actor is walking during approach")
	var t0 := Time.get_ticks_msec()
	actor.stop()
	await frames(4)
	check(_ms_since(t0) < 2000, "stopping actor unblocks approach without hanging")
	eq(done.arrived, false, "approach returns false when stopped")
	world.queue_free()
	await frames(2)


func test_ephemeral_port_zero_and_retry_helpers() -> void:
	var root := fresh_save_root("ephemeral")
	var http: Node = HttpServer.new()
	tree.root.add_child(http)
	eq(http.start(0, "127.0.0.1"), "", "HttpServer accepts port 0")
	check(int(http.port) > 0, "HttpServer records actual ephemeral port: %d" % int(http.port))
	http.stop()
	http.queue_free()
	var ping: Node = PingServer.new()
	tree.root.add_child(ping)
	eq(ping.start(root, [0], "127.0.0.1"), "", "PingServer accepts port 0")
	check(ping.ports_open.size() == 1 and int(ping.ports_open[0]) > 0, "PingServer records bound ephemeral port")
	ping.stop()
	ping.queue_free()
	var srv: Node = PhoneServer.new()
	tree.root.add_child(srv)
	srv.setup(root, root.path_join("no_web"))
	srv.engine_choice = "built-in"
	eq(srv.start(0, "127.0.0.1"), "", "PhoneServer accepts port 0")
	check(int(srv.port) > 0, "PhoneServer syncs actual ephemeral port: %d" % int(srv.port))
	srv.stop()
	srv.queue_free()
	var udp := PacketPeerUDP.new()
	var tries := [0]
	var up := listen_udp_on_free_port(func(p: int) -> int:
		tries[0] += 1
		return ERR_ALREADY_IN_USE if int(tries[0]) < 2 else udp.bind(p, "127.0.0.1"), "UDP retry")
	check(up > 0 and int(tries[0]) == 2, "listen_udp_on_free_port retries busy ports cleanly")
	udp.close()
	var rt := [0]
	var servers: Array[TCPServer] = []
	var rp := listen_on_free_port_run(2, func(p: int) -> String:
		rt[0] += 1
		if int(rt[0]) < 2:
			return "in use"
		var s0 := TCPServer.new()
		var s1 := TCPServer.new()
		if s0.listen(p, "127.0.0.1") == OK and s1.listen(p + 1, "127.0.0.1") == OK:
			servers = [s0, s1]
			return ""
		s0.stop()
		s1.stop()
		return "in use", "port run retry")
	check(rp > 0 and int(rt[0]) == 2, "listen_on_free_port_run retries busy runs cleanly")
	for s in servers:
		s.stop()
	await frames(2)
