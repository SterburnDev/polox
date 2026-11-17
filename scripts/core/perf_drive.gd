extends RefCounted
## Dev only (--drive=perf_scenes): the made-up house, its detailed street and the Dream World home,
## measured the way the caller's window and renderer draw them (run it with --rendering-driver
## opengl3 --touch-ui at a phone size to see the phone's costs). For each scene: frames per second
## with vsync and the frame cap off, average and worst frame time, CPU process/physics time, GPU and
## CPU render time, draw calls, triangles, objects drawn, nodes and video memory. One
## "[perf] {json}" line per scene; --perf-out=<file.json> also writes them all.
## Fixtures only (a made-up house and town), never anyone's real home.

const HomeMapper := preload("res://scripts/home/home_mapper.gd")
const HomeModel := preload("res://scripts/home/home_model.gd")
const HomePlaces := preload("res://scripts/home/home_places.gd")
const Osm := preload("res://scripts/home/osm.gd")

var main: Node
var seconds := 4.0
var shots := ""


func run(main_node: Node) -> void:
	main = main_node
	seed(1741)
	var out_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perf-out="):
			out_path = a.trim_prefix("--perf-out=")
		elif a.begins_with("--perf-seconds="):
			seconds = maxf(1.0, a.trim_prefix("--perf-seconds=").to_float())
		elif a.begins_with("--perf-shots="):
			shots = a.trim_prefix("--perf-shots=")
		elif a.begins_with("--perf-detail="):
			GameState.settings["pc_detail"] = a.trim_prefix("--perf-detail=")
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	GameState.settings["reduce_motion"] = false   # (the title's lake and bubbles moving: their real cost)
	main.apply_display_settings()
	var results: Array = []
	main.show_title()
	await _wait(1.0)
	for a in OS.get_cmdline_user_args():   # (--perf-title-hide=AeroScene,TitleCard: what a title layer costs)
		if a.begins_with("--perf-title-hide="):
			for n in a.trim_prefix("--perf-title-hide=").split(","):
				var node: Node = (main.screen if n == "ALL" else main.screen.find_child(n, true, false)) if main.screen else null
				if node is CanvasItem:
					(node as CanvasItem).visible = false
	results.append(await _measure("title"))
	GameState.settings["reduce_motion"] = true
	main.begin_new_world()
	await _wait(0.8)
	var g: Node = main.game
	g.daylight.hour_override = 11.0
	g.daylight.apply()
	for n in main.ui.find_children("*", "", true, false):   # the start-up cards
		var sc: Script = n.get_script()
		if sc and (str(sc.resource_path).ends_with("today_card.gd") or str(sc.resource_path).ends_with("recap_card.gd")):
			n.queue_free()
	var answers := {"address": "12 Example Lane, Testville", "address_level": "full", "home_type": "house", "floors": 2,
		"rooms": {"bedroom": 3, "bathroom": 2, "kitchen": 1, "living": 1, "dining": 1, "office": 0, "laundry": 1, "garage": 0},
		"entry_room": "hall", "my_room": {"floor": 1, "where": "front", "wall": "#a9c4dc", "floor_kind": "carpet", "bed": "single", "desk": true},
		"floor_kinds": {"kitchen": "tile", "living": "wood"}, "memory": "Pancakes every Sunday"}
	var research: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/home_research_madeup.json"))
	HomeMapper.build_home(answers, HomeModel.clean_research(research), "claude_code")
	var town: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/osm_madeup_town_detail.json"))
	answers["radius"] = 250
	HomeMapper.build_streets(Osm.clean(town, 10.0, 10.0, 250), answers)
	results.append(await _measure("dark_home"))
	g.load_room("garden")
	await _wait(1.2)
	results.append(await _measure("dark_garden"))
	g.load_room("home")
	GameState.settings["reduce_motion"] = true
	await g.dark.go_light()
	g.daylight.apply()
	await _wait(1.0)
	results.append(await _measure("light_room"))
	g.load_room("lw_floor_0")
	await _wait(1.2)
	results.append(await _measure("house_ground"))
	var gid := HomePlaces.place_id(0)
	var street := ""
	for o in SaveManager.load_room(gid).get("objects", []):
		if bool(o.get("street_gate", false)):
			street = str(o.door_target)
	if street != "":
		g.load_room(street, gid)
		await _wait(1.5)
		results.append(await _measure("street"))
		g.cam.distance = g.cam.ZOOM_MAX
		g.cam.snap_to_target()
		await _wait(0.6)
		results.append(await _measure("street_wide"))
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(results, "\t"))
			f.close()


func _measure(scene: String) -> Dictionary:
	var vp := main.get_viewport()
	var rid := vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var vsync := DisplayServer.window_get_vsync_mode()
	var cap := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _wait(0.6)
	var frames := 0
	var sums := {"process_ms": 0.0, "physics_ms": 0.0, "gpu_ms": 0.0, "render_cpu_ms": 0.0, "draw_calls": 0.0, "triangles": 0.0, "objects": 0.0}
	var worst := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < int(seconds * 1000000.0):
		await main.get_tree().process_frame
		var now := Time.get_ticks_usec()
		if frames > 0:
			worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		sums.process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		sums.physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		sums.gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		sums.render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		sums.draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		sums.triangles += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		sums.objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var secs := (Time.get_ticks_usec() - t0) / 1000000.0
	DisplayServer.window_set_vsync_mode(vsync)
	Engine.max_fps = cap
	RenderingServer.viewport_set_measure_render_time(rid, false)
	var r := {"scene": scene, "room": GameState.current_room_id, "fps": snappedf(frames / secs, 0.1),
		"frame_ms": snappedf(secs * 1000.0 / maxf(1, frames), 0.01), "worst_ms": snappedf(worst, 0.1),
		"window": str(DisplayServer.window_get_size()), "renderer": RenderingServer.get_current_rendering_method(),
		"frame_cap_setting": cap, "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"shadows": main.game.sun.shadow_enabled if main.game and main.game.sun else false}
	for k in sums:
		r[k] = snappedf(sums[k] / maxf(1, frames), 0.01)
	r["top_meshes"] = top_meshes(main.game if main.game else main, 8)
	if shots != "":
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(shots.path_join(scene + ".png"))
	print("[perf] ", JSON.stringify(r))
	return r


## The visible geometry with the most triangles (multimeshes count every instance): where a scene's
## triangle budget goes.
static func top_meshes(root: Node, n: int) -> Array:
	var rows: Array = []
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := node as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var tris := 0
		var what := ""
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			tris = mesh_triangles((gi as MeshInstance3D).mesh)
			what = (gi as MeshInstance3D).mesh.get_class()
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh and (gi as MultiMeshInstance3D).multimesh.mesh:
			var mm := (gi as MultiMeshInstance3D).multimesh
			var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			tris = mesh_triangles(mm.mesh) * count
			what = "MultiMesh x%d" % count
		elif gi is GPUParticles3D:
			var gp := gi as GPUParticles3D
			var pm: Mesh = gp.draw_pass_1
			tris = (mesh_triangles(pm) if pm else 0) * gp.amount
			what = "GPUParticles x%d of %s(%d tris)" % [gp.amount, pm.get_class() if pm else "none", mesh_triangles(pm) if pm else 0]
		elif gi is CPUParticles3D:
			var cp := gi as CPUParticles3D
			tris = (mesh_triangles(cp.mesh) if cp.mesh else 0) * cp.amount
			what = "CPUParticles x%d of %s(%d tris)" % [cp.amount, cp.mesh.get_class() if cp.mesh else "none", mesh_triangles(cp.mesh) if cp.mesh else 0]
		if tris > 0 or what.ends_with("Particles3D"):
			rows.append({"node": str(gi.get_path()).right(70), "tris": tris, "what": what})
	rows.sort_custom(func(a, b): return int(a.tris) > int(b.tris))
	return rows.slice(0, n)


static func mesh_triangles(mesh: Mesh) -> int:
	var t := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			t += (idx as PackedInt32Array).size() / 3
		elif arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			t += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


func _wait(s: float) -> void:
	await main.get_tree().create_timer(s).timeout
