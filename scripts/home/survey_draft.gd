extends RefCounted
## Local-only wizard state. This filename is outside the home sync allowlist.
const JsonUtil := preload("res://scripts/core/json_util.gd")
const HomeStore := preload("res://scripts/home/home_store.gd")
const SurveyData := preload("res://scripts/home/survey_data.gd")
const FILE := "survey_draft.json"


static func read() -> Dictionary:
	var raw: Variant = JsonUtil.read_json(HomeStore.path(FILE), {})
	if not raw is Dictionary or int(raw.get("version", 0)) != 1 or not raw.get("answers") is Dictionary:
		return {}
	var step := int(raw.get("step", 0))
	if step < 0 or step >= SurveyData.STEPS.size():
		return {}
	var history: Array = []
	if raw.get("history") is Array:
		for index in raw.history:
			if (index is int or index is float) and int(index) >= 0 and int(index) < step and not int(index) in history:
				history.append(int(index))
	return {"answers": raw.answers.duplicate(true), "step": step, "history": history,
		"helper": str(raw.get("helper", "none")), "text": raw.get("text", {}) if raw.get("text") is Dictionary else {}}


static func write(answers: Dictionary, step: int, history: Array, helper: String, text: Dictionary) -> bool:
	return JsonUtil.write_json(HomeStore.path(FILE), {"version": 1, "answers": answers, "step": step,
		"history": history, "helper": helper, "text": text})


static func clear() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var p := HomeStore.path(FILE + suffix)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
