extends "res://tests/test_case.gd"
## Polox Public Beta 1.0 feature & regression checks:
## - Version label ("Polox Public Beta 1.0") & title-screen Toby Fox secrets
## - Redesigned reddish bathtub-like Dream Gate & 3-poke rubber duck secret
## - Settings > Music HTML-tab scroll runway + `aero` / `frutiger` / `code` / `rot` secret vault
## - Google Maps integration (Gemini Maps Grounding, Places API, offline URL parser, privacy/key scrubbing)
## - Custom 3D .obj/.glb model importer, 6 sculpted 3D props, procedural PBR normal maps & styles
## - Rotating multi-inspect furniture humor & practice battle idle quips

const Addons := preload("res://scripts/core/addons.gd")
const SecretPictures := preload("res://scripts/ui/secret_pictures.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
const TitleScreen := preload("res://scripts/ui/title_screen.gd")
const FountainNode := preload("res://scripts/world/fountain_node.gd")
const GoogleMaps := preload("res://scripts/home/google_maps.gd")
const Osm := preload("res://scripts/home/osm.gd")
const KeyFormat := preload("res://scripts/ai/key_format.gd")
const CustomModels := preload("res://scripts/world/custom_models.gd")
const Furniture := preload("res://scripts/world/furniture.gd")
const BlockFactory := preload("res://scripts/world/block_factory.gd")
const SurfaceDetail := preload("res://scripts/world/surface_detail.gd")
const Whimsy := preload("res://scripts/variety/whimsy.gd")
const SparringCatalog := preload("res://scripts/battle/sparring_catalog.gd")


func test_version_label_and_title_secrets() -> void:
	fresh_save_root()
	eq(str(ProjectSettings.get_setting("application/config/release_label", "")), "Polox Public Beta 1.0", "release_label is Polox Public Beta 1.0")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(3)
	var ver := main.screen.find_child("VersionLabel", true, false) as Label
	check(ver != null and ver.text == "Polox Public Beta 1.0", "title screen shows Polox Public Beta 1.0")
	eq(main.screen.feed_title_secret("mochi"), "mochi", "typing mochi triggers title secret")
	eq(main.screen.feed_title_secret("bramin"), "bramin", "typing bramin triggers title secret")
	eq(Whimsy.version_quip(1), "Polox Public Beta 1.0 — freshly baked.", "first version click quip")
	eq(Whimsy.version_quip(5).contains("sparkle"), true, "fifth click grants complimentary sparkle")
	main.queue_free()
	await frames(2)


func test_dream_gate_is_reddish_bathtub_with_duck_secret() -> void:
	fresh_save_root()
	var gate: Node3D = FountainNode.make({"type": "dark_fountain", "id": "tub1", "state": "open"})
	tree.root.add_child(gate)
	await frames(2)
	var basin := gate.find_child("Basin", true, false) as MeshInstance3D
	check(basin != null, "has sculpted basin")
	var basin_mat := basin.material_override as StandardMaterial3D
	check(basin_mat != null and basin_mat.albedo_color.r > 0.55 and basin_mat.albedo_color.r > basin_mat.albedo_color.g * 1.8 and basin_mat.albedo_color.r > basin_mat.albedo_color.b * 1.8, "basin glaze is clearly reddish")
	check(basin.scale.x > basin.scale.z, "basin is elongated like a bathtub")
	check(gate.find_child("Backrest", true, false) != null, "has curved bathtub backrest")
	check(gate.find_child("Faucet", true, false) != null, "has brass bathtub faucet")
	check(gate.find_child("Clawfoot", true, false) != null, "stands on brass clawfeet")
	check(gate.find_child("Rim", true, false) != null, "has glazed rolled rim")
	check(not gate.has_rubber_duck(), "no duck before 3 pokes")
	gate.poke()
	gate.poke()
	check(not gate.has_rubber_duck(), "still no duck at 2 pokes")
	gate.poke()
	check(gate.has_rubber_duck(), "3rd poke invites a tiny floating rubber duck")
	gate.queue_free()
	await frames(1)


func test_music_secret_html_scroll_and_vault_keywords() -> void:
	fresh_save_root()
	TitleScreen.eyes = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(main)
	await frames(3)
	var settings: Control = SettingsScreen.new()
	settings.main = main
	settings.start_on = "Music"
	main.open_panel(settings)
	await frames(3)
	var page := settings.tabs.get_tab_control(settings.tabs.current_tab) as ScrollContainer
	check(page.find_child("HtmlScrollRunway", true, false) != null, "HTML-tab bottom scroll runway exists")
	# Check all four secret vault keywords arm properly.
	for word in ["aero", "frutiger", "code", "rot"]:
		eq(page.feed_secret_text(word), word, "typing %s arms the vault" % word)
		eq(page.secret_keyword_armed(), word, "armed keyword is %s" % word)
	# Public vault SVG fallback check (when no private pack is active).
	Addons.builtin_override = ""
	for word in ["aero", "frutiger", "code", "rot"]:
		var pub_tex := SecretPictures.pick_for_secret(word)
		check(pub_tex != null and pub_tex.resource_path.ends_with("vault_%s.svg" % word), "public vault fallback for %s" % word)
	# Private pack check (simulating built-in local secret images from Downloads/secret).
	Addons.builtin_override = "res://tests/fixtures/secret_pack"
	var priv_tex := SecretPictures.pick_for_secret("frutiger")
	check(priv_tex != null and priv_tex.resource_path.ends_with("dot.svg"), "keyword pulls built-in secret pack image")
	var normal_tex := SecretPictures.pick_for_secret("")
	check(normal_tex != null and normal_tex.resource_path.contains("yam_"), "clicking yams without keyword shows classic yam")
	Addons.builtin_override = null

	# Scroll all the way down, arm 'aero', click yams -> shows full-screen picture + VaultCaption.
	page.scroll_vertical = ceili(page.get_v_scroll_bar().max_value)
	check(page.secret_shown(), "scrolling to bottom reveals yams👀")
	page.feed_secret_text("aero")
	var yams := page.find_child("Yams", true, false) as Button
	yams.pressed.emit()
	await frames(2)
	var layer := main.get_node_or_null("Secret") as CanvasLayer
	check(layer != null, "secret layer appeared")
	if layer:
		check(layer.find_child("VaultCaption", true, false) != null, "vault caption displayed for typed keyword")
		layer.queue_free()
	TitleScreen.eyes = false
	main.queue_free()
	await frames(2)


func test_google_maps_integration_links_grounding_and_privacy() -> void:
	fresh_save_root()
	# Offline Google Maps URL coordinate parsing.
	var c1 := GoogleMaps.parse_link("https://www.google.com/maps/@37.422012,-122.084095,17z")
	check(absf(float(c1.get("lat", 0.0)) - 37.422012) < 0.0001 and absf(float(c1.get("lon", 0.0)) + 122.084095) < 0.0001, "parses @lat,lon URL")
	var c2 := GoogleMaps.parse_link("https://www.google.com/maps/place/Park/@35.0,139.0,16z/data=!3m1!4b1!4m6!3m5!1s0x0!8m2!3d35.658581!4d139.745433")
	check(absf(float(c2.get("lat", 0.0)) - 35.658581) < 0.0001 and absf(float(c2.get("lon", 0.0)) - 139.745433) < 0.0001, "prefers exact !3d!4d pin coordinates")
	var c3 := Osm.parse_coords("https://maps.google.com/?q=40.7128,-74.0060")
	check(absf(float(c3.get("lat", 0.0)) - 40.7128) < 0.0001 and absf(float(c3.get("lon", 0.0)) + 74.0060) < 0.0001, "Osm.parse_coords accepts Google Maps URLs")

	# Gemini Maps Grounding request payload & response parser.
	var req := GoogleMaps.build_grounding_body("Find parks", 37.422, -122.084, true)
	eq(req.tools.size(), 2, "includes google_maps + google_search tools")
	check(req.tools[0].has("google_maps") and req.has("toolConfig"), "passes retrievalConfig latLng")
	var mock_reply := {
		"candidates": [{
			"content": {"parts": [{"text": "{\"atmosphere\": \"Leafy and sunny\", \"places\": [{\"name\": \"Maple Park\", \"kind\": \"park\", \"lat\": 37.4225, \"lon\": -122.0845, \"note\": \"Quiet benches\"}]}"}]},
			"groundingMetadata": {
				"groundingChunks": [
					{"maps": {"title": "Maple Park", "uri": "https://maps.google.com/?cid=12345", "placeId": "ChIJ_TestPlace123"}}
				]
			}
		}]
	}
	var parsed := GoogleMaps.parse_gemini_places(mock_reply, 37.422, -122.084, 300)
	check(bool(parsed.grounded), "marked grounded when Maps chunks exist")
	eq(str(parsed.atmosphere), "Leafy and sunny", "keeps neighbourhood atmosphere")
	eq((parsed.places as Array).size(), 1, "one grounded public place")
	eq(str(parsed.places[0].maps_uri), "https://maps.google.com/?cid=12345", "attaches verified Maps URI")

	# Merging into OSM extract preserves existing OSM data, deduplicates, and adds Google Maps credit.
	var base_extract := {"format": 2, "center": {"lat": 37.422, "lon": -122.084}, "radius": 300, "credit": Osm.CREDIT, "features": []}
	var merged := GoogleMaps.merge_into_extract(base_extract, parsed.places)
	eq((merged.features as Array).size(), 1, "merged Google Maps POI")
	check(str(merged.credit).contains("Google Maps"), "includes Google Maps attribution")
	var merged_again := GoogleMaps.merge_into_extract(merged, parsed.places)
	eq((merged_again.features as Array).size(), 1, "deduplicates repeated places")

	# Mock live fetch with Gemini Maps Grounding + key scrubbing check.
	var fake_key := "AIza" + "SyTestOnlyPlaceholderKey1234567890"
	GameState.settings["light_world"] = {
		"google_maps_enabled": true,
		"google_maps_mode": "gemini_grounding",
		"google_maps_api_key": fake_key,
	}
	var stored := KeyFormat.stored(GameState.settings)
	check(fake_key in stored, "Google Maps key is registered for log scrubbing")
	var gm := GoogleMaps.new()
	tree.root.add_child(gm)
	gm.transport = func(_url, _hdrs, _method, _body):
		return [HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(mock_reply).to_utf8_buffer()]
	var live := await gm.fetch_nearby(37.422, -122.084, 300)
	check(bool(live.ok) and (live.places as Array).size() == 1, "fetch_nearby works with mock transport")
	check(not GoogleMaps.load_cached().is_empty(), "cached locally for offline use")
	gm.queue_free()
	await frames(1)


func test_custom_3d_models_sculpted_props_and_pbr_textures() -> void:
	fresh_save_root()
	# Pure-GDScript Wavefront OBJ parser + importer + BlockFactory prop integration.
	var obj_text := "v 0 0 0\nv 2 0 0\nv 2 2 0\nv 0 2 0\nf 1 2 3 4\n"
	var parsed_mesh := CustomModels.parse_obj_text(obj_text)
	check(parsed_mesh != null and parsed_mesh.get_surface_count() == 1, "parses quad OBJ into ArrayMesh")

	var tmp_obj := SaveManager.global_path("tmp_pyramid.obj")
	var f := FileAccess.open(tmp_obj, FileAccess.WRITE)
	f.store_string("v -1 0 -1\nv 1 0 -1\nv 1 0 1\nv -1 0 1\nv 0 2 0\nf 1 2 5\nf 2 3 5\nf 3 4 5\nf 4 1 5\n")
	f.close()
	var imported := CustomModels.import_model(tmp_obj)
	check(imported.ends_with(".obj"), "imports .obj into models/")
	check(imported in CustomModels.list_models(), "lists imported model")
	var inst := CustomModels.instantiate(imported, "#7fdcf0")
	check(inst != null, "instantiates custom 3D model")
	if inst:
		inst.free()
	var prop_node := BlockFactory.make_object({"id": "p1", "type": "prop", "custom_model": imported, "color": "#ffd166"})
	check(prop_node.find_child("CustomModel", true, false) != null, "BlockFactory builds custom 3D model on prop")
	prop_node.free()

	# Pure-GDScript binary GLB 2.0 parser (zero dependency on stripped engine modules).
	var glb_bin := PackedByteArray()
	glb_bin.resize(36)   # 3 vec3 vertices (float32)
	var verts := [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
	for vi in verts.size():
		glb_bin.encode_float(vi * 4, float(verts[vi]))
	var glb_json_str := JSON.stringify({
		"asset": {"version": "2.0"},
		"buffers": [{"byteLength": 36}],
		"bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36}],
		"accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"}],
		"meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
		"nodes": [{"mesh": 0, "name": "Tri"}],
	})
	var glb_json := glb_json_str.to_utf8_buffer()
	while glb_json.size() % 4 != 0:
		glb_json.append(0x20)
	var glb := PackedByteArray()
	var total := 12 + 8 + glb_json.size() + 8 + glb_bin.size()
	glb.resize(12)
	glb.encode_u32(0, CustomModels.GLB_MAGIC)
	glb.encode_u32(4, 2)
	glb.encode_u32(8, total)
	var hdr_j := PackedByteArray()
	hdr_j.resize(8)
	hdr_j.encode_u32(0, glb_json.size())
	hdr_j.encode_u32(4, CustomModels.GLB_CHUNK_JSON)
	glb.append_array(hdr_j)
	glb.append_array(glb_json)
	var hdr_b := PackedByteArray()
	hdr_b.resize(8)
	hdr_b.encode_u32(0, glb_bin.size())
	hdr_b.encode_u32(4, CustomModels.GLB_CHUNK_BIN)
	glb.append_array(hdr_b)
	glb.append_array(glb_bin)
	var glb_node := CustomModels.parse_glb_bytes(glb)
	check(glb_node != null and glb_node.find_children("*", "MeshInstance3D", true, false).size() == 1, "parses binary GLB 2.0 in pure GDScript")
	if glb_node:
		glb_node.free()
	CustomModels.clear_cache()

	# All 6 new sculpted 3D furniture pieces build cleanly.
	for model_id in ["lava_lamp", "arcade_cabinet", "crystal_cluster", "yam_plush", "aquarium_orb", "crt_tv"]:
		check(Furniture.exists(model_id), model_id + " in furniture catalog")
		var piece := Furniture.build({"id": "t_" + model_id, "type": "furniture", "model": model_id, "pos": [0, 0, 0], "rot": 0})
		check(piece != null and piece.find_children("*", "MeshInstance3D", true, false).size() >= 3, model_id + " builds multi-part 3D geometry")
		piece.free()

	# Procedural PBR normal maps & new stylized surface textures.
	for style in ["floor", "wall", "block", "aero_tile", "dream_brick", "checkered", "tatami"]:
		var alb := SurfaceDetail.texture(style)
		var nrm := SurfaceDetail.normal_texture(style)
		check(alb != null and nrm != null, "albedo + normal map generated for " + style)
	SurfaceDetail.clear_cache()


func test_whimsy_rotating_inspects_and_battle_quips() -> void:
	Whimsy.reset_session()
	var first := Whimsy.inspect_furniture("mirror", "m1", "Mirror.")
	var second := Whimsy.inspect_furniture("mirror", "m1", "Mirror.")
	check(first != second and first.contains("still you"), "mirror rotates witty inspect lines")
	var yam_line := Whimsy.inspect_furniture("yam_plush", "y1", "Yam.")
	check(yam_line.contains("👀"), "suspicious yam plush has playful inspect line")
	var encounter := SparringCatalog.raw("tide_parcel")
	var idle: Array = encounter.enemies[0].lines.idle
	check(idle.size() >= 2, "practice battles include humorous idle commentary")
