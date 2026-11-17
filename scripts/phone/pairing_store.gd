extends RefCounted
## [PAIRING] [PERSONAL_DATA] Phone Link's private files under the resolved save root.
## JsonUtil keeps interrupted writes recoverable. Pairing owns the PIN and device rules.

const JsonUtil := preload("res://scripts/core/json_util.gd")
const STATE_PATH := "phone/pairing_state.json"
const DEVICES_PATH := "phone/devices.json"
const AUDIT_PATH := "phone/audit.log"
const AUDIT_MAX_BYTES := 512 * 1024


static func devices_path(save_root: String) -> String:
	return save_root.path_join(DEVICES_PATH)


static func read_devices(save_root: String) -> Array:
	var stored: Variant = JsonUtil.read_json(devices_path(save_root), {})
	if not stored is Dictionary:
		return []
	var devices: Variant = stored.get("devices", [])
	return devices if devices is Array else []


static func write_devices(save_root: String, devices: Array) -> bool:
	return JsonUtil.write_json(devices_path(save_root), {"version": 2, "devices": devices})


static func is_paused(save_root: String) -> bool:
	var state: Variant = JsonUtil.read_json(save_root.path_join(STATE_PATH), {})
	return state is Dictionary and bool(state.get("paused", false))


static func write_paused(save_root: String, paused: bool) -> void:
	JsonUtil.write_json(save_root.path_join(STATE_PATH), {"version": 1, "paused": paused})


static func append_audit(save_root: String, event: String) -> void:
	var path := save_root.path_join(AUDIT_PATH)
	JsonUtil.ensure_dir(path.get_base_dir())
	var existing := FileAccess.open(path, FileAccess.READ)
	if existing != null:
		var rotate := existing.get_length() > AUDIT_MAX_BYTES
		existing.close()  # Windows needs the file closed before rename.
		if rotate:
			DirAccess.rename_absolute(path, path + ".1")
	var log_file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if log_file == null:
		return
	log_file.seek_end()
	log_file.store_line("%s %s" % [Time.get_datetime_string_from_system(), event])
	log_file.close()


static func audit_tail(save_root: String, line_count: int) -> PackedStringArray:
	var path := save_root.path_join(AUDIT_PATH)
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	return lines.slice(maxi(0, lines.size() - line_count))
