extends RefCounted
## Long-term memory for chats: when you say something, the friend remembers the earlier moments that
## were about the same things (beyond the last messages, the facts list and the running summary).
## Each of your past lines and the friend's answer to it make one moment; moments are scored by the
## rare words they share with what you just said (a word that comes up all the time counts little),
## and a little by how recent they are. The best few go into the prompt with their date.
## Local and quick: no AI call, nothing leaves the device. Scans the last MAX_SCAN messages, so a phone
## stays quick with a very long friendship.

const STOPWORDS: PackedStringArray = ["that", "this", "with", "have", "they", "their", "them", "your", "about", "really", "very",
	"just", "what", "when", "were", "been", "being", "into", "some", "also", "said", "says", "there", "then", "than", "would",
	"could", "should", "because", "today", "yeah", "okay", "know", "think", "like", "want", "going", "gonna", "maybe", "well",
	"here", "where", "which", "while", "will", "from", "does", "didn", "don't", "it's", "i'm", "you're", "that's", "what's"]
const MAX_SCAN := 3000
const MOMENT_CHARS := 220


## Up to `k` earlier moments about what `said` is about, as prompt lines ("(Oct 3) They said: ...
## You said: ..."). The last `skip_recent` messages are left out (they're in the prompt already).
static func recall(entries: Array, said: String, skip_recent: int = 12, k: int = 3, player: String = "They") -> PackedStringArray:
	var out := PackedStringArray()
	var query := words(said)
	if query.is_empty():
		return out
	var convo: Array = entries.filter(func(e): return e is Dictionary and str(e.get("role", "")) in ["user", "ai"] and not bool(e.get("failed", false)))
	if convo.size() <= skip_recent:
		return out
	var older: Array = convo.slice(maxi(0, convo.size() - skip_recent - MAX_SCAN), convo.size() - skip_recent)
	# Moments: a line of yours and the answer that followed.
	var moments: Array = []
	var i := 0
	while i < older.size():
		var e: Dictionary = older[i]
		if str(e.role) == "user":
			var reply: Dictionary = older[i + 1] if i + 1 < older.size() and str(older[i + 1].role) == "ai" else {}
			moments.append({"you": str(e.get("text", "")), "them": str(reply.get("text", "")), "t": str(e.get("ts", "")), "at": i})
			i += 2 if not reply.is_empty() else 1
		else:
			i += 1
	if moments.is_empty():
		return out
	# How rare each word is across the moments (rare words say more about what a moment was about).
	var df := {}
	var bags: Array = []
	for m in moments:
		var bag := words(str(m.you) + " " + str(m.them))
		bags.append(bag)
		for w in bag:
			df[w] = int(df.get(w, 0)) + 1
	var n := float(moments.size())
	var scored: Array = []
	for j in moments.size():
		var score := 0.0
		for w in query:
			if (bags[j] as Dictionary).has(w):
				score += log(1.0 + n / float(df[w]))
		if score <= 0.0:
			continue
		score += 0.15 * float(j) / n   # a little for being recent
		scored.append([score, j])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	for pair in scored.slice(0, k):
		var m: Dictionary = moments[pair[1]]
		var when := _date(str(m.t))
		var line := "%s%s said: \"%s\"" % [("(%s) " % when) if when != "" else "", player, _cap(str(m.you))]
		if str(m.them) != "":
			line += " You said: \"%s\"" % _cap(str(m.them))
		out.append(line)
	return out


## Content words of a text (lower case, 4+ letters, no stopwords), as a set.
static func words(text: String) -> Dictionary:
	var out := {}
	var w := ""
	for ch in (text.to_lower() + " "):
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "'":
			w += ch
		else:
			var clean := w.trim_prefix("'").trim_suffix("'")
			if clean.length() >= 4 and not clean in STOPWORDS:
				out[clean] = true
			w = ""
	return out


static func _cap(text: String) -> String:
	var t := text.strip_edges().replace("\n", " ")
	return t if t.length() <= MOMENT_CHARS else t.substr(0, MOMENT_CHARS).strip_edges() + "…"


## "2026-10-03T..." -> "Oct 3"; "" when there's no date.
static func _date(iso: String) -> String:
	if iso.length() < 10 or iso[4] != "-":
		return ""
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var mo := iso.substr(5, 2).to_int()
	var d := iso.substr(8, 2).to_int()
	return "%s %d" % [months[clampi(mo - 1, 0, 11)], d] if mo >= 1 and d >= 1 else ""
