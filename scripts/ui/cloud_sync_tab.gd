extends ScrollContainer
## [CLOUD_SYNC] Settings > Cloud sync. Its parts:
##   The two ways to play the same worlds on another device, side by side, so they aren't confused:
##      Phone Link (the PC is on; the phone plays through it) and the cloud folder (the PC can be off).
##   The cloud folder on this PC: choose it (suggestions for the cloud apps that are installed),
##      whether it can be reached, sync by itself or not. On Android there is no folder: each world's
##      cloud document is picked with the phone's own file picker.
##   Your worlds: for each, "Keep in the cloud" (the choice of what is synced), its state in plain
##      words, Sync now, and, when a sync has a question, the question with its answers. Nothing is
##      changed until a question is answered.
##   Worlds that are in the cloud but not on this device, to bring over.
##   What is sent and what never is.
## Before a folder is chosen the explanation leads; once it is, the worlds lead and the explanation
## moves to the bottom.
## The page only shows and asks; cloud_service.gd runs the syncs and cloud_sync.gd decides.
## Tags: [CLOUD_SYNC] [GLASS_UI]

signal open_page(title: String)   # Settings switches to another category (Phone Link)

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const Slots := preload("res://scripts/core/slots.gd")
const CloudService := preload("res://scripts/sync/cloud_service.gd")
const CloudStore := preload("res://scripts/sync/cloud_store.gd")
const CloudPackage := preload("res://scripts/sync/cloud_package.gd")
const CloudMerge := preload("res://scripts/sync/cloud_merge.gd")
const AndroidNative := preload("res://scripts/core/android_native.gd")

const HEADING_SIZE := 22
const NOTE_SIZE := 16
const SHOWN_CONFLICTS := 4
## Picker purposes (Android): which question a picked document or folder answers.
const PICK_FOR_WORLD := "cloud_world:"
const PICK_RELINK_WORLD := "cloud_relink:"
const PICK_TO_ADD := "cloud_add"
const PICK_TREE := "cloud_tree"

var main: Node                       # the game's Main (owns the open world); null in some tests
var _v: VBoxContainer
var _results := {}                   # slot id -> the last sync() result that asked something
var _message := ""                   # the line under the heading after an action


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_deadzone = UiKit.touch_deadzone()
	_v = UiKit.vbox(12)
	_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_v)
	if CloudService.is_android():
		AndroidNative.connect_document_picked(_on_document_picked)
	refresh()


func _exit_tree() -> void:
	if CloudService.is_android():
		AndroidNative.disconnect_document_picked(_on_document_picked)


func refresh() -> void:
	if _v == null:
		return
	for child in _v.get_children():
		child.queue_free()
	_v.add_child(UiKit.label("The same worlds on your PC and your phone", HEADING_SIZE, ThemeBuilder.YELLOW))
	if _message != "":
		var message := UiKit.para(_message, 18, ThemeBuilder.YELLOW)
		message.name = "CloudMessage"
		_v.add_child(message)
	if not CloudService.supported():
		_two_ways()
		if CloudService.is_android():
			var why := AndroidNative.last_error if AndroidNative.last_error != "" else "cloud picker helper unavailable"
			_v.add_child(UiKit.para("Cloud sync couldn't reach Polox's Android file-picker plugin (%s)." % why, 18, ThemeBuilder.YELLOW))
		else:
			_v.add_child(UiKit.para("Cloud sync isn't part of the browser version: it plays through your PC with Phone Link.", 18))
		return
	if CloudService.is_set_up():
		# Set up already: what the player came to do (their worlds, and any question) comes first,
		# and the explanation moves to the bottom.
		_worlds_card()
		_cloud_only_card()
		if CloudService.is_android():
			_mobile_cloud_card()
		else:
			_folder_card()
		_two_ways()
	else:
		_two_ways()
		_folder_card()   # (Android is always "set up": it never reaches here)
	_what_is_sent()
	UiKit.allow_swipe_over_buttons(self)


func _card(border: Color = Color(ThemeBuilder.CREAM, 0.35)) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ThemeBuilder.box(ThemeBuilder.PANEL_LIGHT, border, 2, 12, 14))
	var column := UiKit.vbox(6)
	panel.add_child(column)
	_v.add_child(panel)
	return column


# --- The two ways ------------------------------------------------------------------------------------

func _two_ways() -> void:
	var columns := UiKit.columns(12)
	_v.add_child(columns)
	var link := _way(columns, "📱 Phone Link", "Your PC is on",
		"Your phone plays through this PC, live, on your Wi-Fi or with Tailscale away from home. Nothing leaves your own devices.")
	link.name = "WayPhoneLink"
	if main != null and main.get("phone") != null and bool(main.phone.get("app")):
		link.add_child(UiKit.button("Connect to your PC", func(): main.open_app_connect(false, false), 0))
	elif not OS.has_feature("web"):
		var go := UiKit.button("Open Phone Link", func(): open_page.emit("Phone Link"), 0)
		go.name = "OpenPhoneLink"
		link.add_child(go)
	var cloud := _way(columns, "☁ Cloud folder", "Your PC can be off",
		"Each world you choose is kept as one file in a folder that your own cloud app (Google Drive, OneDrive, Dropbox...) copies between your devices. Polox never signs in anywhere.")
	cloud.name = "WayCloud"


func _way(parent: Container, title: String, when: String, text: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ThemeBuilder.box(ThemeBuilder.PANEL_LIGHT, Color(ThemeBuilder.CREAM, 0.35), 2, 12, 14))
	var column := UiKit.vbox(6)
	panel.add_child(column)
	column.add_child(UiKit.label(title, 20))
	column.add_child(UiKit.label(when, NOTE_SIZE, ThemeBuilder.YELLOW))
	column.add_child(UiKit.para(text, NOTE_SIZE))
	parent.add_child(panel)
	return column


# --- The folder (PCs) --------------------------------------------------------------------------------

func _folder_card() -> void:
	var card := _card()
	card.name = "FolderCard"
	card.add_child(UiKit.label("Cloud folder on this PC", 20))
	var chosen := CloudService.folder()
	if chosen == "":
		card.add_child(UiKit.para("Choose a folder inside the one your cloud app keeps in step. Polox makes a \"Polox\" folder there and puts one file per world in it.", NOTE_SIZE))
		var suggestions := UiKit.flow_row(8)
		for suggestion in CloudStore.suggested_folders():
			var pick := UiKit.button("%s  ›  Polox" % suggestion.name, func(): _use_folder(str(suggestion.path)), 0)
			pick.tooltip_text = str(suggestion.path)
			suggestions.add_child(pick)
		var other := UiKit.button("Choose a folder…", _browse, 0)
		other.name = "ChooseFolder"
		suggestions.add_child(other)
		card.add_child(suggestions)
		return
	var path := UiKit.para(chosen, 18)
	path.name = "FolderPath"
	card.add_child(path)
	var problem := str(CloudService.store().reachable())
	var status := UiKit.para("✓ Ready" if problem == "" else "⚠ " + problem, NOTE_SIZE, ThemeBuilder.CREAM if problem == "" else ThemeBuilder.YELLOW)
	status.name = "FolderStatus"
	card.add_child(status)
	var row := UiKit.flow_row(8)
	row.add_child(UiKit.button("Open folder", func(): OS.shell_open(chosen), 0))
	row.add_child(UiKit.button("Change folder…", _browse, 0))
	var stop := UiKit.button("Stop using a cloud folder", _forget_folder, 0)
	stop.name = "ForgetFolder"
	row.add_child(stop)
	card.add_child(row)
	_auto_sync_checkbox(card)


func _auto_sync_checkbox(card: VBoxContainer) -> void:
	var auto := CheckBox.new()
	auto.name = "AutoSync"
	auto.text = "Sync by itself when Polox starts and when I leave a world"
	auto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # (a long label must wrap on a phone, not widen the page)
	auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto.button_pressed = CloudService.automatic()
	auto.toggled.connect(func(on): CloudService.set_automatic(on))
	card.add_child(auto)


func _mobile_cloud_card() -> void:
	var card := _card()
	card.name = "MobileCloudCard"
	card.add_child(UiKit.label("Google Drive & cloud storage on Android", 20))
	if CloudService.uses_tree():
		var info := AndroidNative.tree_info(CloudService.tree_uri())
		var folder_name := str(info.get("name", "Cloud folder"))
		if folder_name == "":
			folder_name = "Cloud folder"
		var name_label := UiKit.para(folder_name, 18)
		name_label.name = "FolderPath"
		card.add_child(name_label)
		var problem := str(CloudService.store().reachable())
		var status := UiKit.para("✓ Ready" if problem == "" else "⚠ " + problem, NOTE_SIZE, ThemeBuilder.CREAM if problem == "" else ThemeBuilder.YELLOW)
		status.name = "FolderStatus"
		card.add_child(status)
		var row := UiKit.flow_row(8)
		var change := UiKit.button("Change folder…", _pick_tree_folder, 0)
		change.name = "ChooseTreeFolder"
		row.add_child(change)
		var switch_docs := UiKit.button("Switch to Google Drive files", _forget_tree_folder, 0)
		switch_docs.name = "ForgetTreeFolder"
		row.add_child(switch_docs)
		card.add_child(row)
	else:
		card.add_child(UiKit.para("Google Drive works directly: switch on \"Keep in the cloud\" on a world to save it into Google Drive (for example My Drive › Polox), or add a .poloxsync world from Google Drive above. Polox never asks for your Google password.", NOTE_SIZE))
		if AndroidNative.tree_available():
			var row := UiKit.flow_row(8)
			var pick_tree := UiKit.button("Choose a cloud folder…", _pick_tree_folder, 0)
			pick_tree.name = "ChooseTreeFolder"
			row.add_child(pick_tree)
			row.add_child(UiKit.para("Optional: for DriveSync, Syncthing, Nextcloud, or a local folder.", NOTE_SIZE, ThemeBuilder.MUTED))
			card.add_child(row)
	_auto_sync_checkbox(card)


func _pick_tree_folder() -> void:
	if not AndroidNative.pick_tree(PICK_TREE):
		_say("This phone can't open the folder picker.")


func _forget_tree_folder() -> void:
	var old_uri := CloudService.tree_uri()
	if old_uri != "":
		AndroidNative.release_tree(old_uri)
	CloudService.set_tree_uri("")
	_say("Using Google Drive / picked files now. Existing links keep working.")


func _browse() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.title = "Choose your cloud folder"
	dialog.dir_selected.connect(func(path):
		_use_folder(str(path))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(900, 600))


func _use_folder(path: String) -> void:
	if DirAccess.make_dir_recursive_absolute(path) != OK and not DirAccess.dir_exists_absolute(path):
		_say("Couldn't make that folder. Choose another one.")
		return
	CloudService.set_folder(path)
	_say("Cloud folder set. Switch on \"Keep in the cloud\" for the worlds you want there.")


func _forget_folder() -> void:
	CloudService.set_folder("")
	_say("No cloud folder now. Your worlds and the files in the folder are all still there.")


# --- Your worlds -------------------------------------------------------------------------------------

func _worlds_card() -> void:
	var card := _card()
	card.name = "WorldsCard"
	var top := UiKit.flow_row(8)   # (wraps on a narrow screen)
	var title := UiKit.label("Your worlds", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var sync_all := UiKit.button("Sync all now", _sync_all, 0)
	sync_all.name = "SyncAll"
	top.add_child(sync_all)
	card.add_child(top)
	var engine := CloudService.engine()
	var look_now := not CloudService.is_android()   # (Android cloud reads may use the network: check on Sync now)
	for world in Slots.list():
		var slot_id := str(world.id)
		var wstate := engine.world_state(slot_id)
		var is_synced := not wstate.is_empty()
		var row := UiKit.flow_row(8)
		row.name = "World_" + slot_id
		var name_label := UiKit.label("%s %s" % [str(world.get("emoji", "")), str(world.get("name", slot_id))], 18)
		name_label.custom_minimum_size.x = 160 if UiKit.upright_phone() else 220
		row.add_child(name_label)
		var keep := CheckButton.new()
		keep.name = "Keep"
		keep.text = "Keep in the cloud"
		keep.button_pressed = is_synced
		keep.toggled.connect(func(on): _set_synced(slot_id, on))
		row.add_child(keep)
		if is_synced:
			var state := str(engine.check(slot_id).state) if look_now else ""
			var fallback_state := "Google Drive / Cloud file · Tap Sync now" if str(wstate.get("ref", "")).begins_with("content://") else "In cloud folder · Tap Sync now"
			var state_label := UiKit.label(CloudService.state_text(state) if state != "" else fallback_state, NOTE_SIZE, ThemeBuilder.MUTED)
			state_label.name = "State"
			row.add_child(state_label)
			var now := UiKit.button("Sync now", func(): _sync(slot_id), 0)
			now.name = "SyncNow"
			row.add_child(now)
		card.add_child(row)
		if _results.has(slot_id):
			_question(card, slot_id, _results[slot_id])


## A sync that needs an answer: what happened, in words, and one button per answer.
func _question(card: VBoxContainer, slot_id: String, result: Dictionary) -> void:
	var box := UiKit.vbox(6)
	box.name = "Question_" + slot_id
	var answers := UiKit.flow_row(8)
	var state := str(result.get("state", ""))
	match state:
		"both_changed":
			box.add_child(UiKit.para("This world changed on this device and on another one, in the same places. Nothing has been changed yet:", NOTE_SIZE, ThemeBuilder.YELLOW))
			var conflicts: Array = result.get("conflicts", [])
			for conflict in conflicts.slice(0, SHOWN_CONFLICTS):
				box.add_child(UiKit.para("• %s: %s" % [str(conflict.what), str(conflict.why)], NOTE_SIZE))
			if conflicts.size() > SHOWN_CONFLICTS:
				box.add_child(UiKit.para("• and %d more" % (conflicts.size() - SHOWN_CONFLICTS), NOTE_SIZE))
			_answer(answers, "Keep both (safest)", "KeepBoth", slot_id, "keep_both")
			_answer(answers, "Use this device's", "UseThisDevice", slot_id, "use_this_device")
			_answer(answers, "Use the cloud's", "UseCloud", slot_id, "use_cloud")
			box.add_child(answers)
			box.add_child(UiKit.para("Keep both: this device's version stays this world, and the other one arrives as a second world. Either way, the version that isn't chosen is kept (this world's Backups, or the cloud folder's kept copies).", NOTE_SIZE, ThemeBuilder.MUTED))
		"cloud_missing":
			box.add_child(UiKit.para("This world's file is gone from the cloud. If you removed it on purpose, switch \"Keep in the cloud\" off. If not:", NOTE_SIZE, ThemeBuilder.YELLOW))
			_answer(answers, "Send this device's copy again", "Upload", slot_id, "upload")
			_add_relink_button(answers, slot_id)
			box.add_child(answers)
		"cloud_damaged":
			box.add_child(UiKit.para(str(result.get("error", "")) + " It may still be uploading from the other device: wait a little and sync again. If it stays like this:", NOTE_SIZE, ThemeBuilder.YELLOW))
			_answer(answers, "Replace it with this device's copy", "Upload", slot_id, "upload")
			box.add_child(answers)
		_:
			box.add_child(UiKit.para(str(result.get("error", "")), NOTE_SIZE, ThemeBuilder.YELLOW))
			if CloudService.is_android() and state in ["unreachable", "wrong_world"]:
				_add_relink_button(answers, slot_id)
				box.add_child(answers)
	card.add_child(box)


func _add_relink_button(row: Container, slot_id: String) -> void:
	if not CloudService.is_android() or not AndroidNative.documents_available():
		return
	var relink := UiKit.button("Relink file…", func():
		if not AndroidNative.pick_document_to_open(PICK_RELINK_WORLD + slot_id):
			_say("This phone can't open the file picker."), 0)
	relink.name = "Relink"
	row.add_child(relink)


func _answer(row: Container, text: String, node_name: String, slot_id: String, choice: String) -> void:
	var button := UiKit.button(text, func(): _sync(slot_id, choice), 0)
	button.name = node_name
	row.add_child(button)


func _set_synced(slot_id: String, on: bool) -> void:
	var engine := CloudService.engine()
	if not on:
		var old_ref := str(engine.world_state(slot_id).get("ref", ""))
		if old_ref.begins_with("content://"):
			AndroidNative.release_document(old_ref)   # (hand the grant back)
		engine.disable(slot_id)
		_results.erase(slot_id)
		_say("That world stays on this device only. Its file in the cloud is left where it is.")
		return
	if CloudService.uses_documents():
		# Android: the player says where the world's cloud document goes; _on_document_picked finishes.
		var suggested := CloudPackage.file_name(str(Slots.meta(slot_id).get("name", "World")), str(Slots.meta(slot_id).get("id", slot_id)))
		if not AndroidNative.pick_document_to_create(PICK_FOR_WORLD + slot_id, suggested):
			_say("This phone can't open the file picker.")
		return
	var enabled := engine.enable(slot_id)
	if not enabled.ok:
		_say(str(enabled.error))
		return
	_sync(slot_id)


func _on_document_picked(purpose: String, uri: String) -> void:
	if uri == "":
		refresh()   # (backed out: the switch goes back)
		return
	if purpose == PICK_TREE:
		var old_tree := CloudService.tree_uri()
		if old_tree != "" and old_tree != uri:
			AndroidNative.release_tree(old_tree)
		CloudService.set_tree_uri(uri)
		_say("Cloud folder set. Switch on \"Keep in the cloud\" for the worlds you want there.")
	elif purpose == PICK_TO_ADD:
		var added := CloudService.engine().add_from_cloud(uri)
		_say("%s is on this phone now (Worlds)." % str(Slots.meta(str(added.slot_id)).get("name", "It")) if added.ok else str(added.error))
	elif purpose.begins_with(PICK_RELINK_WORLD):
		var slot_id := purpose.trim_prefix(PICK_RELINK_WORLD)
		var engine := CloudService.engine()
		var old_ref := str(engine.world_state(slot_id).get("ref", ""))
		if old_ref.begins_with("content://") and old_ref != uri:
			AndroidNative.release_document(old_ref)
		var relinked := engine.relink(slot_id, uri)
		if relinked.ok:
			_sync(slot_id)
		else:
			_say(str(relinked.error))
	elif purpose.begins_with(PICK_FOR_WORLD):
		var slot_id := purpose.trim_prefix(PICK_FOR_WORLD)
		var enabled := CloudService.engine().enable(slot_id, uri)
		if enabled.ok:
			_sync(slot_id)
		else:
			_say(str(enabled.error))


func _sync(slot_id: String, choice: String = "") -> void:
	_say("Syncing…")
	await get_tree().process_frame   # (so "Syncing…" is on screen while the files are compared)
	var result := CloudService.sync_world(main, slot_id, choice)
	_results.erase(slot_id)
	if str(result.action) == "ask":
		_results[slot_id] = result
		_say("That world needs your answer below.")
		return
	_say(_outcome(result))


func _sync_all() -> void:
	_say("Syncing…")
	await get_tree().process_frame
	_results.clear()
	var engine := CloudService.engine()
	var waiting := 0
	var problem := ""
	for slot_id in engine.synced_slots():
		if not Slots.exists(slot_id):
			continue
		var result := CloudService.sync_world(main, slot_id)
		if str(result.action) == "ask":
			_results[slot_id] = result
			waiting += 1
		elif not result.ok:
			problem = str(result.error)
	if waiting > 0:
		_say("%d world%s need%s your answer below." % [waiting, "" if waiting == 1 else "s", "s" if waiting == 1 else ""])
	else:
		_say(problem if problem != "" else "Everything is in step.")


static func _outcome(result: Dictionary) -> String:
	if not result.ok:
		return str(result.error)
	var skipped: Array = result.get("skipped", [])
	var too_big := "" if skipped.is_empty() else " (%d file%s too big to sync stayed on this device.)" % [skipped.size(), "" if skipped.size() == 1 else "s"]
	match str(result.action):
		"pushed":
			return ("Sent to the cloud, and the other version arrived as a second world." if str(result.new_slot) != "" else "Sent to the cloud.") + too_big
		"pulled":
			return "Updated from the cloud. (This device's earlier version is in the world's Backups.)"
		"merged":
			return "Both devices' changes were combined and sent." + too_big
	return "Already in step." + too_big


func _say(text: String) -> void:
	_message = text
	refresh()


# --- In the cloud, not here --------------------------------------------------------------------------

func _cloud_only_card() -> void:
	if CloudService.uses_documents():
		_add_from_cloud_card("Bring a world from Google Drive / Cloud",
			"Pick a .poloxsync file in Google Drive, OneDrive, Dropbox, or Files (for example My Drive › Polox from your PC).",
			"Add a world from Google Drive / Cloud…")
		return
	var elsewhere: Array = CloudService.engine().discover().filter(func(entry): return str(entry.slot_id) == "" or bool(entry.duplicate))
	if not elsewhere.is_empty():
		var found := _card()
		found.name = "CloudOnlyCard"
		found.add_child(UiKit.label("In the cloud folder, not on this device", 20))
		for entry in elsewhere:
			var row := UiKit.flow_row(8)
			var from := " · from %s" % str(entry.device_name) if str(entry.device_name) != "" else ""
			var when := " · %s" % str(entry.saved_at).left(10) if str(entry.saved_at) != "" else ""
			if bool(entry.duplicate):
				row.add_child(UiKit.para("A second file for \"%s\"%s%s. Your cloud app kept two versions (%s)." % [str(entry.world_name), from, when, str(entry.ref)], NOTE_SIZE))
				row.add_child(UiKit.button("Bring it here as a separate world", func(): _add(str(entry.ref), true), 0))
			else:
				row.add_child(UiKit.label("%s%s%s" % [str(entry.world_name), from, when], 18))
				var bring := UiKit.button("Bring it here", func(): _add(str(entry.ref), false), 0)
				bring.name = "Bring"
				row.add_child(bring)
			found.add_child(row)
	if CloudService.is_android():
		_add_from_cloud_card("Single file from Google Drive",
			"You can also pick an individual .poloxsync file from Google Drive or Files.",
			"Add a file from Google Drive…")


func _add_from_cloud_card(heading: String, copy: String, button_text: String) -> void:
	var card := _card()
	card.add_child(UiKit.label(heading, 20))
	card.add_child(UiKit.para(copy, NOTE_SIZE))
	var add := UiKit.button(button_text, func():
		if not AndroidNative.pick_document_to_open(PICK_TO_ADD):
			_say("This phone can't open the file picker."), 0)
	add.name = "AddFromCloud"
	card.add_child(add)


func _add(ref: String, as_copy: bool) -> void:
	var engine := CloudService.engine()
	var added := engine.add_copy_from_cloud(ref) if as_copy else engine.add_from_cloud(ref)
	_say("%s is on this device now (Worlds)." % str(Slots.meta(str(added.slot_id)).get("name", "It")) if added.ok else str(added.error))


# --- What is sent ------------------------------------------------------------------------------------

func _what_is_sent() -> void:
	_v.add_child(UiKit.label("What is sent", HEADING_SIZE, ThemeBuilder.YELLOW))
	var sent := UiKit.para("For each world you switch on: its places, friends, chats, items, your character and its pictures.", NOTE_SIZE)
	sent.name = "WhatIsSent"
	_v.add_child(sent)
	var never := UiKit.para("Never sent: your settings and AI keys, Phone Link pairing, add-ons, backups, photos, your Light World home, and every world you leave switched off.", NOTE_SIZE)
	never.name = "NeverSent"
	_v.add_child(never)
	_v.add_child(UiKit.para("Before another device's changes come in, this device's world is zipped first (the world's Backups). Playing never needs the cloud: without it, each device simply keeps its own copy until the next sync.", NOTE_SIZE, ThemeBuilder.MUTED))
