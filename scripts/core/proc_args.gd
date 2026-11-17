extends RefCounted
## Arguments for another program (OS.execute, OS.execute_with_pipe), made to arrive exactly as written.
## On Windows, Godot builds one command line: it puts quotes round an argument that has a space (or one
## of & ( ) [ ] { } ^ = ; ! ' + , ` ~) but doesn't escape the quotes inside it, and an empty argument
## disappears. So a JSON argument reached Claude Code with every " stripped ("--json-schema is not
## valid JSON") and the question lost its quotes too. Here each argument is escaped the way Windows
## programs read their command line: a quote becomes \" (any backslashes just before it doubled), the
## backslashes at the end are doubled when Godot will add the closing quote, a tab becomes spaces (a
## tab would split it) and an empty argument is passed as "". Elsewhere arguments go through untouched.

## The characters that make Godot quote an argument (os_windows.cpp, _quote_command_line_argument).
const QUOTED_FOR := " &()[]{}^=;!'+,`~"


static func for_os(args: PackedStringArray, windows: bool = OS.has_feature("windows")) -> PackedStringArray:
	if not windows:
		return args
	var out := PackedStringArray()
	for a in args:
		out.append(win_arg(a))
	return out


static func win_arg(text: String) -> String:
	var s := text.replace("\t", "    ")
	if s == "":
		return "\"\""
	var quoted := false
	for c in QUOTED_FOR:
		if s.contains(c):
			quoted = true
			break
	var out := ""
	var slashes := 0
	for ch in s:
		if ch == "\\":
			slashes += 1
			continue
		if ch == "\"":
			out += "\\".repeat(slashes * 2 + 1) + "\""
		else:
			out += "\\".repeat(slashes) + ch
		slashes = 0
	out += "\\".repeat(slashes * 2 if quoted else slashes)
	return out
