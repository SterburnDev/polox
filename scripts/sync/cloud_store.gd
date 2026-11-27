extends RefCounted
## [CLOUD_SYNC] [PLATFORM] Where world packages are kept so another device can reach them.
##
## cloud_sync.gd only ever asks a store five things: can you be reached, does this package exist, give
## me a copy of it, replace it with this file, and what packages do you hold. Two stores answer:
##
##   FolderStore     a folder on this computer that the player's own cloud app keeps in step with their
##                   other devices (Google Drive for desktop, OneDrive, Dropbox, Syncthing...), or any
##                   shared or removable folder. Polox only reads and writes files there; signing in,
##                   uploading and downloading are the cloud app's job, so Polox holds no account.
##   DocumentStore   Android: a document the player picked with the system's file picker, which can
##                   live in Google Drive or any other storage app (the Storage Access Framework). A
##                   package's reference is that document's content:// address; Android remembers the
##                   permission. There is no folder to list: each world's document is picked once.
##
## A reference ("ref") is the package's file name in a FolderStore and its content:// address in a
## DocumentStore. Every method that can fail returns "" for success or a sentence for the player.
## Tags: [CLOUD_SYNC] [PLATFORM]

const CloudPackage := preload("res://scripts/sync/cloud_package.gd")
const JsonUtil := preload("res://scripts/core/json_util.gd")

## A file is copied again this many times when the first try fails (a cloud app holding it open for
## a moment is the usual reason), waiting RETRY_WAITS_MS before each new try.
const RETRY_WAITS_MS: Array[int] = [250, 750]
const UPLOADING_SUFFIX := ".uploading"


class FolderStore extends RefCounted:
	var folder := ""

	func _init(folder_path: String = "") -> void:
		folder = folder_path.replace("\\", "/").trim_suffix("/")

	func kind() -> String:
		return "folder"

	## "" when packages can be read and written here; otherwise why not.
	func reachable() -> String:
		if folder == "":
			return "No cloud folder is chosen yet."
		if not DirAccess.dir_exists_absolute(folder):
			return "The cloud folder isn't there right now (%s). Is the drive connected and your cloud app running?" % folder
		return ""

	func path_of(ref: String) -> String:
		return folder.path_join(ref)

	func exists(ref: String) -> bool:
		return ref != "" and FileAccess.file_exists(path_of(ref))

	## Copies the package to `dest` on this device (through dest.part, so a cut-off copy never has
	## the final name).
	func fetch(ref: String, dest: String) -> String:
		if not exists(ref):
			return "That world isn't in the cloud folder."
		JsonUtil.ensure_dir(dest.get_base_dir())
		var part := dest + ".part"
		var copied := false
		for attempt in RETRY_WAITS_MS.size() + 1:
			if attempt > 0:
				OS.delay_msec(RETRY_WAITS_MS[attempt - 1])
			if DirAccess.copy_absolute(path_of(ref), part) == OK:
				copied = true
				break
		if not copied:
			DirAccess.remove_absolute(part)
			return "Couldn't read the cloud copy (another program may be using it). Try again in a moment."
		return _atomic_finish_fetch(part, dest, "Couldn't save the cloud copy on this device (is the disk full?).")

	## Replaces the package with `source`. The new file is copied in beside the old one under another
	## name and takes its place only when the copy is whole and its size matches.
	func publish(ref: String, source: String) -> String:
		var problem := reachable()
		if problem != "":
			return problem
		var uploading := path_of(ref) + UPLOADING_SUFFIX
		var wanted_bytes := _size(source)
		var copied := false
		for attempt in RETRY_WAITS_MS.size() + 1:
			if attempt > 0:
				OS.delay_msec(RETRY_WAITS_MS[attempt - 1])
			if DirAccess.copy_absolute(source, uploading) == OK and _size(uploading) == wanted_bytes:
				copied = true
				break
		if not copied:
			DirAccess.remove_absolute(uploading)
			return "Couldn't write to the cloud folder (is it full, read-only or disconnected?)."
		for attempt in RETRY_WAITS_MS.size() + 1:
			if attempt > 0:
				OS.delay_msec(RETRY_WAITS_MS[attempt - 1])
			if FileAccess.file_exists(path_of(ref)) and DirAccess.remove_absolute(path_of(ref)) != OK:
				continue   # (held open by the cloud app: wait and try again)
			if DirAccess.rename_absolute(uploading, path_of(ref)) == OK:
				return ""
		DirAccess.remove_absolute(uploading)
		return "Couldn't replace the cloud copy (another program may be using it). Try again in a moment."

	## Every package file in the folder, by name.
	func list() -> PackedStringArray:
		var out := PackedStringArray()
		if reachable() != "":
			return out
		for file_name in DirAccess.get_files_at(folder):
			if file_name.get_extension().to_lower() == CloudPackage.EXTENSION:
				out.append(file_name)
		out.sort()
		return out

	func label(ref: String) -> String:
		return path_of(ref)

	static func _size(path: String) -> int:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return -1
		var size := file.get_length()
		file.close()
		return size

	static func _atomic_finish_fetch(part: String, dest: String, disk_full_msg: String) -> String:
		if FileAccess.file_exists(dest):
			DirAccess.remove_absolute(dest)
		if DirAccess.rename_absolute(part, dest) != OK:
			DirAccess.remove_absolute(part)
			return disk_full_msg
		return ""

	static func _is_permanent_cloud_error(error: String) -> bool:
		return error.contains("no longer allowed") or error.contains("Pick it again") \
			or error.contains("Choose it again") or error.contains("wasn't made") \
			or error.contains("isn't in the cloud")


class DocumentStore extends RefCounted:
	const AndroidNative := preload("res://scripts/core/android_native.gd")

	var _backend: Variant = null

	func _init(custom_backend: Variant = null) -> void:
		_backend = custom_backend

	func _api() -> Variant:
		return _backend if _backend != null else AndroidNative

	func kind() -> String:
		return "document"

	func reachable() -> String:
		return "" if _api().documents_available() else "This device can't open cloud documents."

	func exists(ref: String) -> bool:
		return ref.begins_with("content://") and bool(_api().document_info(ref).get("exists", false))

	## True when the storage provider created a 0-byte placeholder (e.g. Android ACTION_CREATE_DOCUMENT
	## on Google Drive before the first upload completes).
	func is_empty(ref: String) -> bool:
		if not ref.begins_with("content://"):
			return false
		var info: Dictionary = _api().document_info(ref)
		return bool(info.get("exists", false)) and int(info.get("bytes", -1)) == 0

	func fetch(ref: String, dest: String) -> String:
		if not ref.begins_with("content://"):
			return "Pick a cloud document for this world first."
		JsonUtil.ensure_dir(dest.get_base_dir())
		var part := dest + ".part"
		var error := ""
		for attempt in RETRY_WAITS_MS.size() + 1:
			if attempt > 0:
				OS.delay_msec(RETRY_WAITS_MS[attempt - 1])
			error = str(_api().copy_document_to_file(ref, part))
			if error == "" or FolderStore._is_permanent_cloud_error(error):
				break
		if error != "":
			DirAccess.remove_absolute(part)
			return error
		return FolderStore._atomic_finish_fetch(part, dest, "Couldn't save the cloud copy on this device (is storage full?).")

	func publish(ref: String, source: String) -> String:
		if not ref.begins_with("content://"):
			return "Pick a cloud document for this world first."
		var error := ""
		for attempt in RETRY_WAITS_MS.size() + 1:
			if attempt > 0:
				OS.delay_msec(RETRY_WAITS_MS[attempt - 1])
			error = str(_api().copy_file_to_document(source, ref))
			if error == "" or FolderStore._is_permanent_cloud_error(error):
				break
		return error

	## Android offers no folder to look through: each world's document is picked by the player.
	func list() -> PackedStringArray:
		return PackedStringArray()

	func label(ref: String) -> String:
		if not ref.begins_with("content://"):
			return "the document you picked"
		var name := str(_api().document_info(ref).get("name", ""))
		return name if name != "" else "the document you picked"


## Android cloud folder picked via ACTION_OPEN_DOCUMENT_TREE (DriveSync, Syncthing, Nextcloud, local/SD).
## Also seamlessly handles worlds whose ref is already a direct content:// document URI (Google Drive).
class TreeStore extends RefCounted:
	const AndroidNative := preload("res://scripts/core/android_native.gd")

	var tree_uri := ""
	var _backend: Variant = null

	func _init(uri: String = "", custom_backend: Variant = null) -> void:
		tree_uri = uri
		_backend = custom_backend

	func _api() -> Variant:
		return _backend if _backend != null else AndroidNative

	func _docs() -> DocumentStore:
		return DocumentStore.new(_backend)

	func kind() -> String:
		return "folder"

	## Returns "" so CloudSync.discover() reads packages into cloud/work via fetch().
	func path_of(_ref: String) -> String:
		return ""

	func reachable() -> String:
		if tree_uri == "":
			return "No cloud folder is chosen yet."
		if not _api().tree_available():
			return "This device can't open cloud folders."
		if not bool(_api().tree_info(tree_uri).get("exists", false)):
			return "The cloud folder can't be reached. Choose it again in Settings > Cloud sync."
		return ""

	func exists(ref: String) -> bool:
		if ref == "":
			return false
		if ref.begins_with("content://"):
			return _docs().exists(ref)
		return tree_uri != "" and bool(_api().tree_document_info(tree_uri, ref).get("exists", false))

	func is_empty(ref: String) -> bool:
		if ref == "":
			return false
		if ref.begins_with("content://"):
			return _docs().is_empty(ref)
		var info: Dictionary = _api().tree_document_info(tree_uri, ref)
		return bool(info.get("exists", false)) and int(info.get("bytes", -1)) == 0

	func fetch(ref: String, dest: String) -> String:
		if ref.begins_with("content://"):
			return _docs().fetch(ref, dest)
		var problem := reachable()
		if problem != "":
			return problem
		JsonUtil.ensure_dir(dest.get_base_dir())
		var part := dest + ".part"
		var error := ""
		for attempt in RETRY_WAITS_MS.size() + 1:
			if attempt > 0:
				OS.delay_msec(RETRY_WAITS_MS[attempt - 1])
			error = str(_api().tree_copy_to_file(tree_uri, ref, part))
			if error == "" or FolderStore._is_permanent_cloud_error(error):
				break
		if error != "":
			DirAccess.remove_absolute(part)
			return error
		return FolderStore._atomic_finish_fetch(part, dest, "Couldn't save the cloud copy on this device (is storage full?).")

	func publish(ref: String, source: String) -> String:
		if ref.begins_with("content://"):
			return _docs().publish(ref, source)
		var problem := reachable()
		if problem != "":
			return problem
		var error := ""
		for attempt in RETRY_WAITS_MS.size() + 1:
			if attempt > 0:
				OS.delay_msec(RETRY_WAITS_MS[attempt - 1])
			error = str(_api().tree_copy_from_file(source, tree_uri, ref))
			if error == "" or FolderStore._is_permanent_cloud_error(error):
				break
		return error

	func list() -> PackedStringArray:
		if reachable() != "":
			return PackedStringArray()
		return _api().tree_list(tree_uri)

	func label(ref: String) -> String:
		if ref.begins_with("content://"):
			return _docs().label(ref)
		var folder_name := str(_api().tree_info(tree_uri).get("name", ""))
		if folder_name == "":
			folder_name = "cloud folder"
		return "%s/%s" % [folder_name, ref]


## Folders on this PC that cloud apps usually keep in step, for the "choose a folder" screen:
## [{name, path}] for the ones that exist. Nothing is created and nothing is read inside them.
static func suggested_folders() -> Array:
	var found: Array = []
	if OS.has_feature("android") or OS.has_feature("web"):
		return found
	var home := OS.get_environment("USERPROFILE") if OS.get_name() == "Windows" else OS.get_environment("HOME")
	var candidates: Array = []
	for variable in ["OneDrive", "OneDriveConsumer", "OneDriveCommercial"]:
		candidates.append(["OneDrive", OS.get_environment(variable)])
	candidates.append(["Dropbox", home.path_join("Dropbox")])
	candidates.append(["Google Drive", home.path_join("Google Drive")])
	candidates.append(["Google Drive", home.path_join("My Drive")])
	candidates.append(["iCloud Drive", home.path_join("iCloudDrive")])
	candidates.append(["Syncthing", home.path_join("Sync")])
	if OS.get_name() == "Windows":
		# Google Drive for desktop mounts a drive letter with "My Drive" at its top.
		for letter in "DEFGHIJKLMNOPQRSTUVWXYZ":
			candidates.append(["Google Drive", "%s:/My Drive" % letter])
	var seen := {}
	for candidate in candidates:
		var path := str(candidate[1]).replace("\\", "/").trim_suffix("/")
		if path == "" or seen.has(path.to_lower()) or not DirAccess.dir_exists_absolute(path):
			continue
		seen[path.to_lower()] = true
		found.append({"name": str(candidate[0]), "path": path.path_join("Polox")})
	return found
