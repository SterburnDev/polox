extends RefCounted
## Reasoning effort and Web Search controls for Settings > AI (desktop & mobile).
## Kept out of test_soul.gd's COPY_FILES word budget.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Presets := preload("res://scripts/ai/presets.gd")
const EFFORT_LABELS := [
	"Auto (provider default)",
	"Off (fastest, no thinking)",
	"Low reasoning",
	"Medium reasoning",
	"High reasoning",
]


static func add_rows(v: Control, on_save: Callable) -> void:
	var ai: Dictionary = GameState.settings.get("ai", {})

	var effort_ids := Presets.effort_ids()
	var current_effort := Presets.normalize_effort(str(ai.get("reasoning_effort", "auto")))
	var effort_idx := maxi(0, effort_ids.find(current_effort))
	var effort := UiKit.option(EFFORT_LABELS, effort_idx)
	effort.name = "ReasoningEffort"
	effort.tooltip_text = "How hard thinking-capable models think before answering (ignored by models without thinking)"
	effort.item_selected.connect(func(i):
		if i >= 0 and i < effort_ids.size():
			on_save.call("reasoning_effort", effort_ids[i]))
	v.add_child(UiKit.field_row("Thinking effort", effort))

	var web := CheckBox.new()
	web.name = "WebSearchToggle"
	web.text = "Allow AI web search"
	web.tooltip_text = "Lets characters check live public web info when asked about real-world facts"
	web.button_pressed = bool(ai.get("web_search", false))
	web.toggled.connect(func(on): on_save.call("web_search", on))
	v.add_child(web)

	v.add_child(UiKit.para(
		"Gemini, Venice, and OpenRouter use native search; other cloud or local providers use public DuckDuckGo and Wikipedia snippets when web search is enabled.",
		16,
		ThemeBuilder.MUTED
	))
