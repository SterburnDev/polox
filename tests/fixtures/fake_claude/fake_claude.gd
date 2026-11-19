extends SceneTree
## A stand-in for Claude Code in the tests (never the real program, never the network). Polox starts it
## the way it starts Claude Code, so the arguments cross the same command line. It checks they arrived
## whole (the answer format still valid JSON, the question's quotes intact), writes what it got to
## FAKE_CLAUDE_LOG, and answers in Claude Code's stream-json format.
##   FAKE_CLAUDE=ok|signed_out|expired|old_model   FAKE_CLAUDE_ANSWER=<recorded answer .json>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := OS.get_environment("FAKE_CLAUDE")
	var log_path := OS.get_environment("FAKE_CLAUDE_LOG")
	if args.size() >= 2 and args[0] == "auth" and args[1] == "status":
		print(JSON.stringify({"loggedIn": mode != "signed_out", "authMethod": "none" if mode == "signed_out" else "claude.ai", "apiProvider": "firstParty"}))
		quit()
		return
	var got := {}
	var i := 0
	while i < args.size():
		var a := args[i]
		if a.begins_with("-") and i + 1 < args.size() and not a in ["--verbose", "--no-session-persistence", "--strict-mcp-config"]:
			got[a] = args[i + 1]
			i += 2
		else:
			got[a] = true
			i += 1
	var schema: Variant = JSON.parse_string(str(got.get("--json-schema", "")))
	var problems: Array = []
	if not schema is Dictionary or str(schema.get("type", "")) != "object":
		problems.append("--json-schema is not valid JSON")
	var prompt := str(got.get("-p", ""))
	if not prompt.contains("\"") or not prompt.contains("\n"):
		problems.append("the question lost its quotes or lines")
	if not got.has("--tools") or not got.has("--allowedTools"):
		problems.append("the tools went missing")
	if log_path != "":
		var f := FileAccess.open(log_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"args": args, "problems": problems}))
			f.close()
	print(JSON.stringify({"type": "system", "subtype": "init", "tools": Array(str(got.get("--tools", "")).split(",", false)) + ["StructuredOutput"], "model": str(got.get("--model", ""))}))
	if not problems.is_empty():
		printerr("Error: " + str(problems[0]))
		quit(1)
		return
	if mode == "expired":
		print(JSON.stringify({"type": "result", "subtype": "success", "is_error": true, "result": "Failed to authenticate: OAuth session expired and could not be refreshed", "total_cost_usd": 0}))
		quit()
		return
	if mode == "old_model" and str(got.get("--model", "")) != "opus":
		print(JSON.stringify({"type": "result", "subtype": "success", "is_error": true, "result": "API Error: 404 model: %s not found" % str(got.get("--model", "")), "total_cost_usd": 0}))
		quit()
		return
	if str(got.get("--tools", "")).contains("WebSearch"):
		print(JSON.stringify({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "name": "WebSearch", "input": {"query": "county assessor parcel record"}}]}}))
	var answer: Variant = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("FAKE_CLAUDE_ANSWER")))
	# The last line comes without its newline, as a program that's cut off might leave it.
	printraw(JSON.stringify({"type": "result", "subtype": "success", "is_error": false, "result": "", "structured_output": answer, "total_cost_usd": 0.01}))
	quit()
