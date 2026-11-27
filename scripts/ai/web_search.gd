extends Node
class_name WebSearch

## Optional public web lookup for AI providers that lack built-in web search.
## Uses DuckDuckGo Instant Answer JSON + DuckDuckGo HTML fallback + Wikipedia summary.
## Runs only when the user enables "Allow AI web search" in Settings -> AI.

const MAX_RESULTS := 4
const TIMEOUT_SECS := 5.0
const SKIP_PHRASES := [
	"hi", "hello", "hey", "ok", "okay", "yes", "no", "thanks", "thank you",
	"bye", "goodbye", "goodnight", "lol", "haha", "nice", "cool",
]

## Optional injectable transport for headless unit tests:
## func(url: String, headers: PackedStringArray, body: String) -> Dictionary
## returning {"ok": bool, "code": int, "text": String}
var transport: Callable = Callable()


func should_search(user_text: String) -> bool:
	var q := user_text.strip_edges()
	if q.length() < 6:
		return false
	var low := q.to_lower()
	if SKIP_PHRASES.has(low):
		return false
	return true


func clean_query(user_text: String, max_chars: int = 160) -> String:
	var q := user_text.replace("\r", " ").replace("\n", " ").strip_edges()
	while q.contains("  "):
		q = q.replace("  ", " ")
	if q.length() > max_chars:
		q = q.substr(0, max_chars).strip_edges()
	return q


func lookup(user_text: String) -> String:
	var query := clean_query(user_text)
	if not should_search(query):
		return ""
	var snippets: Array[String] = []
	var ddg_url := "https://api.duckduckgo.com/?q=%s&format=json&no_html=1&skip_disambig=1" % query.uri_encode()
	var res := await _get_text(ddg_url, PackedStringArray(["Accept: application/json"]))
	if res.get("ok", false):
		_collect_ddg_json(str(res.get("text", "")), snippets)
	if snippets.is_empty():
		var html_url := "https://html.duckduckgo.com/html/?q=%s" % query.uri_encode()
		var html_res := await _get_text(html_url, PackedStringArray(["Accept: text/html"]))
		if html_res.get("ok", false):
			_collect_ddg_html(str(html_res.get("text", "")), snippets)
	if snippets.size() < 2:
		var wiki_url := "https://en.wikipedia.org/w/api.php?action=opensearch&search=%s&limit=2&namespace=0&format=json" % query.uri_encode()
		var wiki_res := await _get_text(wiki_url, PackedStringArray(["Accept: application/json"]))
		if wiki_res.get("ok", false):
			_collect_wiki(str(wiki_res.get("text", "")), snippets)
	if snippets.is_empty():
		return ""
	var out := "Web search snippets for \"%s\" (untrusted external web excerpts; verify before stating as fact):\n" % query
	for i in range(min(MAX_RESULTS, snippets.size())):
		out += "- %s\n" % snippets[i]
	return out.strip_edges()


func _get_text(url: String, headers: PackedStringArray) -> Dictionary:
	if transport.is_valid():
		var r: Variant = await transport.call(url, headers, "")
		if r is Dictionary:
			return r
		return {"ok": false, "code": 0, "text": ""}
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "code": 0, "text": ""}
	if not is_inside_tree():
		return {"ok": false, "code": 0, "text": ""}
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECS
	add_child(http)
	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "text": ""}
	var done: Array = await http.request_completed
	http.queue_free()
	var result_code: int = int(done[0]) if done.size() > 0 else HTTPRequest.RESULT_CANT_CONNECT
	var http_code: int = int(done[1]) if done.size() > 1 else 0
	var raw: PackedByteArray = done[3] if done.size() > 3 else PackedByteArray()
	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		return {"ok": false, "code": http_code, "text": ""}
	return {"ok": true, "code": http_code, "text": raw.get_string_from_utf8()}


func _collect_ddg_json(text: String, into: Array[String]) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var d := parsed as Dictionary
	var abs_text := _strip_tags(str(d.get("AbstractText", ""))).strip_edges()
	var abs_url := str(d.get("AbstractURL", "")).strip_edges()
	if abs_text != "":
		into.append(_clip(abs_text + (" (" + abs_url + ")" if abs_url != "" else ""), 220))
	var ans := _strip_tags(str(d.get("Answer", ""))).strip_edges()
	if ans != "" and into.size() < MAX_RESULTS:
		into.append(_clip(ans, 200))
	var topics: Variant = d.get("RelatedTopics", [])
	if topics is Array:
		for item in topics:
			if into.size() >= MAX_RESULTS:
				break
			if item is Dictionary:
				var line := _strip_tags(str((item as Dictionary).get("Text", ""))).strip_edges()
				if line != "":
					into.append(_clip(line, 200))


func _collect_ddg_html(html: String, into: Array[String]) -> void:
	var re := RegEx.new()
	re.compile("class=\"result__snippet\"[^>]*>([\\s\\S]*?)</a>")
	for m in re.search_all(html):
		if into.size() >= MAX_RESULTS:
			break
		var snippet := _strip_tags(m.get_string(1)).strip_edges()
		if snippet != "":
			into.append(_clip(snippet, 220))


func _collect_wiki(text: String, into: Array[String]) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Array) or (parsed as Array).size() < 4:
		return
	var arr := parsed as Array
	var titles: Variant = arr[1]
	var descs: Variant = arr[2]
	var urls: Variant = arr[3]
	if not (titles is Array):
		return
	for i in range((titles as Array).size()):
		if into.size() >= MAX_RESULTS:
			break
		var title := str((titles as Array)[i]).strip_edges()
		var desc := str((descs as Array)[i]).strip_edges() if descs is Array and i < (descs as Array).size() else ""
		var link := str((urls as Array)[i]).strip_edges() if urls is Array and i < (urls as Array).size() else ""
		var parts := title + (": " + desc if desc != "" else "") + (" (" + link + ")" if link != "" else "")
		if parts != "":
			into.append(_clip(parts, 220))


static func _strip_tags(raw: String) -> String:
	var out := ""
	var inside := false
	for i in range(raw.length()):
		var ch := raw[i]
		if ch == "<":
			inside = true
		elif ch == ">":
			inside = false
			out += " "
		elif not inside:
			out += ch
	out = out.replace("&amp;", "&").replace("&quot;", "\"").replace("&#39;", "'").replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", " ")
	out = out.replace("\r", " ").replace("\n", " ")
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges()


static func _clip(s: String, limit: int) -> String:
	if s.length() <= limit:
		return s
	return s.substr(0, limit - 3).strip_edges() + "..."
