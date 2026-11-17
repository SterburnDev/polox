extends RefCounted
## The battle HUD's look. Built in: Polox's own procedural HUD. Optional: your own pictures in
## PersonalData\skins\battle_hud\ (for example ones from a game you own): fight.png, act.png,
## item.png, spare.png, defend.png (the command buttons), heart.png (your heart), box.png (the
## battle box border, stretched), tp.png (the TP bar) and background.png. Each file is used if it's
## there and skipped if not. They stay on this PC: never included in Polox, never downloaded,
## committed, synced to a phone or put in an export (the skins folder sits outside every world).

const FILES: PackedStringArray = ["fight", "act", "magic", "item", "spare", "defend", "heart", "box", "tp", "background"]

var textures: Dictionary = {}   # name -> Texture2D
var folder := ""


static func folder_path(save_root: String) -> String:
	return save_root.path_join("skins").path_join("battle_hud")


static func load_from(save_root: String) -> RefCounted:
	var s: RefCounted = load("res://scripts/battle/battle_skin.gd").new()
	s.folder = folder_path(save_root)
	for n in FILES:
		var p: String = s.folder.path_join(n + ".png")
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img and not img.is_empty() and img.get_width() <= 2048 and img.get_height() <= 2048:
				s.textures[n] = ImageTexture.create_from_image(img)
	return s


func has(n: String) -> bool:
	return textures.has(n)


func get_tex(n: String) -> Texture2D:
	return textures.get(n)


func count() -> int:
	return textures.size()
