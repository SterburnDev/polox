extends RefCounted
## A small buzz under your finger on a phone: a tap, placing something, confirming. Off in Settings >
## Settings > Controls ("Vibration"), and never on a PC. Counts every buzz (tests read `count` and `last`).
## Tags: [PLATFORM]

const TAP_MS := 8
const PLACE_MS := 18
const CONFIRM_MS := 28

static var count := 0
static var last := ""


static func enabled() -> bool:
	if not bool(GameState.settings.get("haptics", true)):
		return false
	return preload("res://scripts/ui/touch_gestures.gd").phone_layout()


static func _buzz(kind: String, ms: int) -> void:
	if not enabled():
		return
	count += 1
	last = kind
	if OS.has_feature("android") or OS.has_feature("web") or OS.has_feature("ios"):
		Input.vibrate_handheld(ms)


static func tap() -> void:
	_buzz("tap", TAP_MS)


static func place() -> void:
	_buzz("place", PLACE_MS)


static func confirm() -> void:
	_buzz("confirm", CONFIRM_MS)
