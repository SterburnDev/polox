extends RefCounted
## Android-only helpers from Polox's Godot Android plugin (native/android, built into
## addons/polox_android/bin/PoloxAndroid.aar by tools/export_android.ps1), reached as
## Engine.get_singleton("PoloxAndroid"). Everywhere else, and in an APK built without the plugin, every
## call answers a safe "no" (0, false) and the game carries on as before.
## Tags: [PLATFORM]

const PLUGIN := "PoloxAndroid"
const NOTIFY_PERMISSION := "android.permission.POST_NOTIFICATIONS"

static var _plugin: Object = null
static var _tried := false
static var last_error := ""        # (the phone's report) why the helpers aren't there, if they aren't


static func available() -> bool:
	return _native() != null


static func recent_crash_exits() -> Array:
	var p := _native()
	if p == null:
		return []
	var parsed: Variant = JSON.parse_string(str(p.call("recentCrashExits")))
	return parsed if parsed is Array else []


## An uncaught Java exception leaves its stack in <user data>/logs/java_crash_<ms>.txt (crash_log.gd).
static func install_crash_recorder() -> bool:
	var p := _native()
	return bool(p.call("installCrashRecorder")) if p else false


## This process's resident memory in kB, 0 where it is unknown. Godot's own file access refuses /proc paths
## on Android, so the plugin reads /proc/self/status (memory_guard.gd, crash_log.gd).
static func resident_kb() -> int:
	var p := _native()
	if p == null:
		return 0
	var value: Variant = p.call("residentKb")
	return maxi(0, int(value)) if value is int or value is float else 0


static func _native() -> Object:
	if _tried:
		return _plugin
	_tried = true
	if not OS.has_feature("android"):
		last_error = "not Android"
		return null
	if not Engine.has_singleton(PLUGIN):
		last_error = "PoloxAndroid plugin missing (APK built without addons/polox_android)"
		return null
	_plugin = Engine.get_singleton(PLUGIN)
	if _plugin.has_signal("memory_warning") and not _plugin.is_connected("memory_warning", _on_memory_warning):
		_plugin.connect("memory_warning", _on_memory_warning)
	return _plugin


## Godot 4's JNISingleton does not override Object.has_method() for @UsedByGodot Java methods;
## it exposes has_java_method() instead.
static func _has_plugin_method(p: Object, method_name: String) -> bool:
	if p == null:
		return false
	if p.has_method("has_java_method"):
		return bool(p.call("has_java_method", method_name))
	return p.has_method(method_name)


## Android is short of memory (Godot doesn't pass this on by itself): the whole scene tree hears it as
## NOTIFICATION_OS_MEMORY_WARNING, the same notification iOS sends.
static func _on_memory_warning(_level: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.propagate_notification(Node.NOTIFICATION_OS_MEMORY_WARNING)


## Asks the display for its fastest mode (cap 0) or the slowest one at or above the cap. Returns the
## refresh rate asked for (Hz), 0 when nothing was asked.
static func request_refresh_rate(cap: float) -> float:
	var p := _native()
	return float(p.call("requestRefreshRate", cap)) if p else 0.0


static func current_refresh_rate() -> float:
	var p := _native()
	return float(p.call("currentRefreshRate")) if p else 0.0


static func max_refresh_rate() -> float:
	var p := _native()
	return float(p.call("maxRefreshRate")) if p else 0.0


static func notifications_allowed() -> bool:
	var p := _native()
	return bool(p.call("notificationsAllowed")) if p else false


## Android 13+ asks the player (the system's own dialog). Earlier versions allow it already.
static func ask_notification_permission() -> void:
	if available() and not notifications_allowed():
		OS.request_permission(NOTIFY_PERMISSION)


static func schedule(id: int, at_unix: float, title: String, text: String) -> bool:
	var p := _native()
	return bool(p.call("schedule", id, int(at_unix * 1000.0), title, text)) if p else false


static func cancel(id: int) -> bool:
	var p := _native()
	return bool(p.call("cancel", id)) if p else false


static func notify_now(id: int, title: String, text: String) -> bool:
	var p := _native()
	return bool(p.call("notifyNow", id, title, text)) if p else false


## Copies one of Polox's own files (an absolute path in its private storage) into the phone's Downloads:
## "Download/Polox/<name>" on Android 10 and later. Returns where it went, "" when it couldn't.
static func save_to_downloads(source_path: String, display_name: String, mime: String) -> String:
	var p := _native()
	return str(p.call("saveToDownloads", source_path, display_name, mime)) if p else ""


# --- Cloud documents [CLOUD_SYNC]: files in other apps' storage, through Android's own picker ----------
# (Google Drive, OneDrive, the phone's Files app: the Storage Access Framework. The player picks a
# document once; Android remembers that Polox may read and write that one document. cloud_store.gd's
# DocumentStore is the only caller.)

const NO_DOCUMENTS := "This copy of Polox can't open cloud documents (it needs the Android app)."

## True when this build can show the picker (the Android app with a plugin new enough to have it).
static func documents_available() -> bool:
	return _has_plugin_method(_native(), "pickDocumentToCreate")


## `handler` is called with (purpose: String, uri: String) when the player finishes with the picker:
## `uri` is the document's content:// address, or "" when they backed out. `purpose` is the word the
## pick_ call was given, so a screen can tell its own questions apart. Connect before picking, and
## disconnect when the screen goes away.
static func connect_document_picked(handler: Callable) -> bool:
	var p := _native()
	if p == null or not p.has_signal("document_picked"):
		return false
	if not p.is_connected("document_picked", handler):
		p.connect("document_picked", handler)
	return true


static func disconnect_document_picked(handler: Callable) -> void:
	var p := _native()
	if p != null and p.has_signal("document_picked") and p.is_connected("document_picked", handler):
		p.disconnect("document_picked", handler)


## Opens the picker to make a new document called `suggested_name`.
static func pick_document_to_create(purpose: String, suggested_name: String) -> bool:
	if not documents_available():
		return false
	_native().call("pickDocumentToCreate", purpose, suggested_name)
	return true


## Opens the picker to choose a document that already exists (a world another device put there).
static func pick_document_to_open(purpose: String) -> bool:
	if not documents_available():
		return false
	_native().call("pickDocumentToOpen", purpose)
	return true


## {exists, name, bytes, modified_ms} for a picked document ({exists: false} when it is gone or the
## permission was taken away).
static func document_info(uri: String) -> Dictionary:
	if not documents_available():
		return {"exists": false}
	var parsed: Variant = JSON.parse_string(str(_native().call("documentInfo", uri)))
	return parsed if parsed is Dictionary else {"exists": false}


## Copies a picked document into one of Polox's own files. "" when it worked, else why it didn't.
static func copy_document_to_file(uri: String, dest_path: String) -> String:
	if not documents_available():
		return NO_DOCUMENTS
	return str(_native().call("copyDocumentToFile", uri, dest_path))


## Replaces a picked document's contents with one of Polox's own files. "" when it worked.
static func copy_file_to_document(source_path: String, uri: String) -> String:
	if not documents_available():
		return NO_DOCUMENTS
	return str(_native().call("copyFileToDocument", source_path, uri))


## Gives back the permission for a document or folder Polox no longer needs.
static func release_document(uri: String) -> void:
	if documents_available():
		_native().call("releaseDocument", uri)


## True when this build can pick and sync a whole cloud folder (ACTION_OPEN_DOCUMENT_TREE).
static func tree_available() -> bool:
	return _has_plugin_method(_native(), "pickTree")


## Opens Android's folder picker (DriveSync, Syncthing, Nextcloud, local/SD); answer arrives via
## "document_picked" with the given `purpose`.
static func pick_tree(purpose: String) -> bool:
	if not tree_available():
		return false
	_native().call("pickTree", purpose)
	return true


## {exists, name} for a picked folder ({exists: false} if gone or permission revoked).
static func tree_info(tree_uri: String) -> Dictionary:
	if not tree_available():
		return {"exists": false}
	var parsed: Variant = JSON.parse_string(str(_native().call("treeInfo", tree_uri)))
	return parsed if parsed is Dictionary else {"exists": false}


## Sorted ".poloxsync" file names directly inside the picked cloud folder.
static func tree_list(tree_uri: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not tree_available():
		return out
	var parsed: Variant = JSON.parse_string(str(_native().call("treeList", tree_uri)))
	if parsed is Array:
		for item in parsed:
			var name := str(item)
			if name != "":
				out.append(name)
	return out


## {exists, name, bytes, modified_ms} for a named file inside the picked cloud folder.
static func tree_document_info(tree_uri: String, file_name: String) -> Dictionary:
	if not tree_available():
		return {"exists": false}
	var parsed: Variant = JSON.parse_string(str(_native().call("treeDocumentInfo", tree_uri, file_name)))
	return parsed if parsed is Dictionary else {"exists": false}


## Copies a named file from the picked cloud folder into one of Polox's own files. "" on success.
static func tree_copy_to_file(tree_uri: String, file_name: String, dest_path: String) -> String:
	if not tree_available():
		return NO_DOCUMENTS
	return str(_native().call("treeCopyToFile", tree_uri, file_name, dest_path))


## Creates or replaces a named file inside the picked cloud folder from one of Polox's own files.
static func tree_copy_from_file(source_path: String, tree_uri: String, file_name: String) -> String:
	if not tree_available():
		return NO_DOCUMENTS
	return str(_native().call("treeCopyFromFile", source_path, tree_uri, file_name))


## Gives back the persistent grant for a picked cloud folder.
static func release_tree(tree_uri: String) -> void:
	release_document(tree_uri)
