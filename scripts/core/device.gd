extends RefCounted
## Which kind of Polox this is. Three builds share one project:
##   the PC game (Windows), the phone browser version (Web) and Polox for Android (the app).
## The phone browser version and the app are both "phone builds": they keep a copy of the
## worlds, sync it with the PC and talk to friends through the PC. Only the app works offline.
##
## For testing on a PC: --app-mode pretends to be the Android app.
## Tags: [PLATFORM]


## Polox for Android (or a PC run pretending to be it).
static func is_app() -> bool:
	return OS.has_feature("android") or "--app-mode" in OS.get_cmdline_user_args()


## The phone browser version.
static func is_web() -> bool:
	return OS.has_feature("web")


## A phone build: the browser version or the app (no Phone Link server, a synced copy of the worlds).
static func is_phone_build() -> bool:
	return is_web() or is_app()


## Runs on a phone or tablet for real (not a PC pretending).
static func is_handheld() -> bool:
	return OS.has_feature("web") or OS.has_feature("android")
