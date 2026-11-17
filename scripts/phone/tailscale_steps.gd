extends RefCounted
## Tailscale as the sure path, in three steps (Settings > Phone Link):
##   1. Install Tailscale on this PC and the phone, sign in with the same account
##   2. Press Enable (Polox's own Serve mapping: https://<pc>.<tailnet>.ts.net:8765)
##   3. Open the https address on the phone (Tailscale on)
## Through Serve the phone reaches Tailscale, which talks to Polox on 127.0.0.1,
## so Windows Firewall and Wi-Fi "client isolation" don't matter. Same Wi-Fi
## keeps working alongside. Never Funnel. steps() is pure: it says what each
## step's state is and what the one button there does.

const PhoneServer := preload("res://scripts/phone/phone_server.gd")

const DOWNLOAD := "https://tailscale.com/download"
const ADMIN_DNS := "https://login.tailscale.com/admin/dns"


## ts: Tailscale.parse_status(); serve: the server's serve_result; mode: the mode
## running now ("" if off); url: the https address ("" if none yet).
## Returns [{n, title, state: "done"|"todo"|"problem"|"waiting", lines: [], button: {label, kind, arg}}].
static func steps(ts: Dictionary, serve: Dictionary, mode: String, url: String) -> Array:
	var out: Array = []
	# 1. Installed, signed in, a phone on the tailnet.
	var s1 := {"n": 1, "title": "Install Tailscale on this PC and on your phone, and sign in with the same account", "state": "todo", "lines": [], "button": {}}
	var phones: Array = (ts.get("peers", []) as Array).filter(func(p): return str(p.get("os", "")).to_lower() in ["android", "ios"])
	if not bool(ts.get("installed", false)):
		s1.lines.append("Not installed on this PC yet (free for personal use).")
		s1.button = {"label": "Get Tailscale", "kind": "url", "arg": DOWNLOAD}
	elif not bool(ts.get("running", false)):
		s1.lines.append("Installed, but not signed in or not connected (%s). Open Tailscale from the Start menu and sign in." % str(ts.get("backend", "stopped")))
		s1.state = "problem"
	else:
		s1.lines.append("This PC is signed in as %s." % (str(ts.get("login", "")) if str(ts.get("login", "")) != "" else "you"))
		if phones.is_empty():
			s1.lines.append("No phone on your tailnet yet: install Tailscale on the phone and sign in as %s." % (str(ts.get("login", "")) if str(ts.get("login", "")) != "" else "the same account"))
			s1.button = {"label": "Get Tailscale for the phone", "kind": "url", "arg": DOWNLOAD}
		else:
			s1.state = "done"
			phones.sort_custom(func(a, b): return bool(a.get("online", false)) and not bool(b.get("online", false)))
			for p in phones:   # (the address tells apart two devices with the same name, e.g. an old entry)
				s1.lines.append("%s%s is on your tailnet: %s." % [str(p.get("name", "Your phone")), (" (" + str(p.ip) + ")") if str(p.get("ip", "")) != "" else "", "online now" if bool(p.get("online", false)) else "offline right now (open Tailscale on the phone and switch it on)"])
	out.append(s1)
	# 2. Enable: Polox's own Serve mapping.
	var s2 := {"n": 2, "title": "Press Enable", "state": "waiting", "lines": [], "button": {}}
	if s1.state != "done":
		s2.lines.append("Finish step 1 first.")
	else:
		var why := PhoneServer.serve_blocker(ts)
		if why != "":
			s2.state = "problem"
			s2.lines.append(why)
			s2.button = {"label": "Open the Tailscale admin page", "kind": "url", "arg": ADMIN_DNS}
		elif str(serve.get("consent_url", "")) != "":
			s2.state = "problem"
			s2.lines.append("Tailscale wants your OK once before it serves Polox: open this page, allow it, then press Enable again.")
			s2.button = {"label": "Open Tailscale's consent page", "kind": "url", "arg": str(serve.consent_url)}
		elif mode == "tailscale_serve" and bool(serve.get("ok", false)):
			s2.state = "done"
			s2.lines.append("On: Tailscale serves Polox on your tailnet only (never the public internet).")
		elif mode == "tailscale_serve" and str(serve.get("error", "")) != "":
			s2.state = "problem"
			s2.lines.append("Tailscale couldn't serve Polox: %s" % str(serve.error))
			s2.button = {"label": "Try again", "kind": "enable", "arg": ""}
		else:
			s2.state = "todo"
			s2.lines.append("Polox asks Tailscale to serve it at a private https address (Same Wi-Fi keeps working too).")
			s2.button = {"label": "Enable", "kind": "enable", "arg": ""}
	out.append(s2)
	# 3. Open it on the phone.
	var s3 := {"n": 3, "title": "On the phone (Tailscale on), open the address", "state": "waiting", "lines": [], "button": {}}
	if s2.state == "done" and url != "":
		s3.state = "done"
		s3.lines.append(url)
		s3["qr"] = url
	else:
		s3.lines.append("The https address appears here after step 2.")
	out.append(s3)
	return out
