extends "res://tests/test_case.gd"

class Recorder extends Node:
	var pending: Array = [{"phase": "cross_transform"}]
	func as_report(crash: Dictionary) -> Dictionary:
		return {"page": "crash report", "env": crash}
	func mark_sent(crash: Dictionary) -> void:
		pending.erase(crash)

class Host extends Node:
	var crash_log: Node
	func flush_all() -> void:
		pass

class Client extends Node:
	var sync_ok := true
	var report_ok := false
	var posts := 0
	func sync() -> Dictionary:
		return {"ok": sync_ok}
	func request(_method: String, _path: String, _body: PackedByteArray) -> Dictionary:
		posts += 1
		await get_tree().process_frame
		return {"ok": report_ok}

func test_successful_sync_retries_failed_crash_upload_once() -> void:
	# Successful sync also sends pending exports. Count only this fixture's report.
	fresh_save_root()
	var host := Host.new()
	host.crash_log = Recorder.new()
	host.add_child(host.crash_log)
	var client := Client.new()
	tree.root.add_child(client)
	var phone := preload("res://scripts/phone/phone_mode.gd").new()
	phone.main = host
	phone.client = client
	phone.origin = "http://127.0.0.1:8765"
	phone.token = "a".repeat(64)
	await phone.send_crash_reports()
	eq(host.crash_log.pending.size(), 1, "failed upload remains queued")
	client.report_ok = true
	client.sync_ok = false
	await phone.sync_now()
	eq(client.posts, 1, "failed sync leaves report queued")
	client.sync_ok = true
	await phone.sync_now()
	eq(client.posts, 2, "successful manual sync retries upload")
	eq(host.crash_log.pending.size(), 0, "accepted report removed")
	await phone.sync_now()
	eq(client.posts, 2, "accepted report not duplicated")
	phone.free()
	client.free()
	host.free()

func test_native_exit_report_survives_restart_without_resending() -> void:
	var root := fresh_save_root()
	var dir := root.path_join("logs")
	DirAccess.make_dir_recursive_absolute(dir)
	var recorder := preload("res://scripts/core/crash_log.gd").new(dir)
	var exit_info := {"timestamp_ms": 1793310000000, "reason": 5, "status": 11, "pss_kb": 204800, "description": "native signal"}
	recorder.store_native_exits([exit_info])
	recorder._read_previous()
	eq(recorder.pending.size(), 1, "OS exit is queued even without script heartbeat")
	var report: Dictionary = recorder.as_report(recorder.pending[0])
	eq(report.env.native_exit.status, 11, "native signal reaches report")
	eq(report.env.memory_mb, 200.0, "native PSS converted to MB")
	recorder.mark_sent(recorder.pending[0])
	recorder.store_native_exits([exit_info])
	recorder._read_previous()
	eq(recorder.pending.size(), 0, "same OS history does not resend accepted report")
	recorder.free()


func test_an_older_builds_crash_is_not_blamed_on_this_one() -> void:
	var root := fresh_save_root()
	var dir := root.path_join("logs")
	DirAccess.make_dir_recursive_absolute(dir)
	var recorder := preload("res://scripts/core/crash_log.gd").new(dir)
	var current := str(ProjectSettings.get_setting("application/config/version", ""))
	var installed := 1793400000000
	recorder.store_native_exits([
		{"timestamp_ms": 1793300000000, "reason": 5, "status": 11, "installed_ms": installed},
		{"timestamp_ms": 1793410000000, "reason": 5, "status": 11, "installed_ms": installed},
		{"timestamp_ms": 1793420000000, "reason": 5, "status": 11, "installed_ms": installed, "version": "1.27.12"}])
	recorder._read_previous()
	var named := {}
	for crash in recorder.pending:
		named[int(crash.native_exit.timestamp_ms)] = str(recorder.as_report(crash).env.version)
	eq(named.get(1793300000000), "older than " + current, "a crash from before this install names an older build")
	eq(named.get(1793410000000), current, "an untagged crash after this install is this build's")
	eq(named.get(1793420000000), "1.27.12", "a tagged exit names the build that crashed")
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	eq(str(recorder.pending[0].beat), Time.get_datetime_string_from_unix_time(1793300000 + bias), "its time is local, like the session's own")
	recorder.free()


func test_native_stack_supplements_sent_reason_and_survives_receiver() -> void:
	var root := fresh_save_root()
	var dir := root.path_join("logs")
	DirAccess.make_dir_recursive_absolute(dir)
	var recorder := preload("res://scripts/core/crash_log.gd").new(dir)
	var info := {"timestamp_ms": 1793402627316, "reason": 5, "status": 11}
	recorder.store_native_exits([info])
	recorder._read_previous()
	recorder.mark_sent(recorder.pending[0])
	info.trace_base64 = Marshalls.raw_to_base64("stack data".repeat(12000).to_utf8_buffer())
	recorder.store_native_exits([info])
	recorder._read_previous()
	eq(recorder.pending.size(), 1, "new trace supplements the sent exit reason")
	var report: Dictionary = recorder.as_report(recorder.pending[0])
	var sink := preload("res://scripts/net/report_sink.gd").new(root)
	eq(sink.accept("192.168.1.26", JSON.stringify(report).to_utf8_buffer(), "post", "host")[0], 200)
	eq(sink.recent()[0].env.native_exit.trace_base64, info.trace_base64, "native stack is not shortened to 300 characters")
	recorder.mark_sent(recorder.pending[0])
	recorder.store_native_exits([info])
	recorder._read_previous()
	eq(recorder.pending.size(), 0, "same trace sends once")
	recorder.free()


func test_decoded_native_stack_and_java_crash_reach_the_pc_whole() -> void:
	var root := fresh_save_root()
	var dir := root.path_join("logs")
	DirAccess.make_dir_recursive_absolute(dir)
	var recorder := preload("res://scripts/core/crash_log.gd").new(dir)
	var stack := "signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x10\nthread 5038 \"GLThread 23\" (2 frames):\n  #00 pc 00000000001a2b3c  /vendor/lib64/egl/libGLESv2_adreno.so (glDrawElements+44)\n  #01 pc 0000000000005566  libgodot_android.so" + String.chr(7)
	var info := {"timestamp_ms": 1793402627316, "reason": 5, "status": 11}
	recorder.store_native_exits([info])
	recorder._read_previous()
	recorder.mark_sent(recorder.pending[0])
	info.trace_text = "signal 11 (SIGSEGV)"   # a summary with no frames does not count as a stack
	recorder.store_native_exits([info])
	recorder._read_previous()
	eq(recorder.pending.size(), 0, "a stackless summary does not resend the reason")
	info.trace_text = stack
	recorder.store_native_exits([info])
	var java := FileAccess.open(dir.path_join("java_crash_1793402000000.txt"), FileAccess.WRITE)
	java.store_string("thread \"main\"\njava.lang.IllegalStateException: boom\n\tat org.godotengine.godot.Godot.onPause(Godot.kt:1)\n")
	java.close()
	recorder.store_java_crashes()
	check(not FileAccess.file_exists(dir.path_join("java_crash_1793402000000.txt")), "the Java stack file becomes a report")
	recorder._read_previous()
	eq(recorder.pending.size(), 2, "the decoded native stack and the Java stack are both queued")
	var sink := preload("res://scripts/net/report_sink.gd").new(root)
	for crash in recorder.pending:
		eq(sink.accept("192.168.1.26", JSON.stringify(recorder.as_report(crash)).to_utf8_buffer(), "post", "host")[0], 200)
	var native_rep: Dictionary = sink.recent().filter(func(r): return r.env.native_exit.has("trace_text"))[0]
	var lines: PackedStringArray = str(native_rep.env.native_exit.trace_text).split("\n")
	eq(lines.size(), 4, "every frame keeps its own line")
	check(lines[2].contains("libGLESv2_adreno.so (glDrawElements+44)"), "frames arrive whole, not cut to 300 characters")
	check(not str(native_rep.env.native_exit.trace_text).contains(String.chr(7)), "control characters are stripped")
	var java_rep: Dictionary = sink.recent().filter(func(r): return r.env.native_exit.has("java_stack"))[0]
	check(str(java_rep.env.native_exit.java_stack).contains("IllegalStateException: boom"), "the Java exception arrives")
	check(preload("res://scripts/net/report_sink.gd").text(native_rep).contains("stack:   #00 pc"), "the Doctor's text shows the stack")
	recorder.free()
