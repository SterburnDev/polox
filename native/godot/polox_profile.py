# Polox's engine: the parts of Godot 4.7.2 the game uses, for every export (Android, web and Windows).
# tools/build_engine.py hands this file to SCons (profile=...). Everything below is switched off because the
# game never uses it: tools/build_engine.py writes native/godot/removed_classes.txt from these switches and
# refuses to build while the game names one of those classes, and tests/test_engine_profile.gd checks the
# same on every test run, so new game code can't come to depend on a missing part.

# Scene features the game doesn't use.
module_csg_enabled = "no"  # CSG shapes
module_gridmap_enabled = "no"  # GridMap and MeshLibrary
module_visual_shader_enabled = "no"  # visual shaders (the game's shaders are text)
module_theora_enabled = "no"  # Theora video
module_interactive_music_enabled = "no"  # interactive, playlist and synchronized music streams

# Loading models at run time: furniture and buildings are imported by the editor.
module_gltf_enabled = "no"
module_fbx_enabled = "no"

# Text: the advanced text server draws every label; MSDF fonts aren't used.
module_text_server_fb_enabled = "no"
module_msdfgen_enabled = "no"

# Physics: the project runs Godot Physics (project.godot sets no other engine).
module_jolt_physics_enabled = "no"

# XR and navigation meshes (grid_nav.gd is the game's own path finder).
disable_xr = "yes"
module_openxr_enabled = "no"
module_mobile_vr_enabled = "no"
module_webxr_enabled = "no"
disable_navigation_2d = "yes"
disable_navigation_3d = "yes"

# Networking the game doesn't use: Phone Link and the AI helper talk HTTP(S) through Godot's core classes.
module_multiplayer_enabled = "no"
module_enet_enabled = "no"
module_webrtc_enabled = "no"
module_websocket_enabled = "no"
module_upnp_enabled = "no"
module_jsonrpc_enabled = "no"
