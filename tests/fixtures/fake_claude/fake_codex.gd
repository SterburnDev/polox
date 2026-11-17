extends SceneTree
## Native argv fixture; never contacts a provider or reads credentials. Like `codex exec -`, it reads
## its prompt from stdin (to the end), so a launch whose stdin never ends would hang here too.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if "--help" in args:
		print("--ignore-user-config --ignore-rules --ephemeral --output-schema --output-last-message")
	elif "login" in args:
		print("Logged in using fixture credentials")
	else:
		var stdin := PackedByteArray()
		if args.size() > 0 and args[-1] == "-":
			while true:
				var chunk := OS.read_buffer_from_stdin(65536)
				if chunk.is_empty():
					break
				stdin.append_array(chunk)
		# Like `codex exec --json`: one finished web search event when live search was switched on.
		if "web_search=live" in args:
			print('{"type":"item.completed","item":{"id":"item_1","type":"web_search","query":"fixture"}}')
		var index := args.find("--output-last-message")
		if index >= 0:
			var file := FileAccess.open(args[index + 1], FileAccess.WRITE)
			file.store_string('{"changes":[],"questions":[]}')
			file.close()
		var log_path := OS.get_environment("POLOX_CODEX_ARGV_FIXTURE")
		if log_path != "":
			var log_file := FileAccess.open(log_path, FileAccess.WRITE)
			log_file.store_string(JSON.stringify({"args": Array(args), "stdin": stdin.get_string_from_utf8()}))
	quit()
