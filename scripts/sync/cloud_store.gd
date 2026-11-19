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
		if FileAccess.file_exists(dest):
			DirAccess.remove_absolute(dest)
		if DirAccess.rename_absolute(part, dest) != OK:
			DirAccess.remove_absolute(part)
			return "Couldn't save the cloud copy on this device (is the disk full?)."
		return ""

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


class DocumentStore extends RefCounted:
	const AndroidNative := preload("res://scripts/core/android_native.gd")

	func kind() -> String:
		return "document"

	func reachable() -> String:
		return "" if AndroidNative.available() else "This device can't open cloud documents."

	func exists(ref: String) -> bool:
		return ref != "" and bool(AndroidNative.document_info(ref).get("exists", false))

	func fetch(ref: String, dest: String) -> String:
		JsonUtil.ensure_dir(dest.get_base_dir())
		var part := dest + ".part"
		var error := AndroidNative.copy_document_to_file(ref, part)
		if error != "":
			DirAccess.remove_absolute(part)
			return error
		if FileAccess.file_exists(dest):
			DirAccess.remove_absolute(dest)
		if DirAccess.rename_absolute(part, dest) != OK:
			DirAccess.remove_absolute(part)
			return "Couldn't save the cloud copy on this device (is storage full?)."
		return ""

	func publish(ref: String, source: String) -> String:
		return AndroidNative.copy_file_to_document(source, ref)

	## Android offers no folder to look through: each world's document is picked by the player.
	func list() -> PackedStringArray:
		return PackedStringArray()

	func label(ref: String) -> String:
		var name := str(AndroidNative.document_info(ref).get("name", ""))
		return name if name != "" else "the document you picked"


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
