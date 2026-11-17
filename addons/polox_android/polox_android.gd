@tool
extends EditorPlugin
## Puts Polox's Godot Android plugin into Android exports: bin/PoloxAndroid.aar, which tools/export_android.ps1
## builds from native/android before every export. The game reaches it as Engine.get_singleton("PoloxAndroid")
## (scripts/core/android_native.gd). Editor-only: export_presets.cfg keeps this folder out of every game build.

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = AndroidLibrary.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class AndroidLibrary extends EditorExportPlugin:
	func _get_name() -> String:
		return "PoloxAndroid"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["polox_android/bin/PoloxAndroid.aar"])   # (relative to res://addons)
