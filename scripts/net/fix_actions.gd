extends RefCounted
## One-click fixes shown next to a Doctor / Polox Ping finding. None of them
## changes anything silently: each opens the place where you decide (Windows
## Settings, the firewall helper, which explains and asks), except "Keep this
## PC awake", which is Polox's own setting.

const Firewall := preload("res://scripts/phone/firewall.gd")

const LABELS := {
	"network_settings": "Open network settings", "firewall_helper": "Run the firewall helper",
	"firewall_settings": "Open firewall settings", "power_settings": "Open sleep settings",
	"keep_awake": "Keep this PC awake", "device_manager": "Open Device Manager",
}


static func label(action: String) -> String:
	return str(LABELS.get(action, action))


## The ms-settings page for a network adapter ("Wi-Fi ..." -> wifi, else ethernet).
static func settings_page(adapter_name: String) -> String:
	var n := adapter_name.to_lower()
	return "ms-settings:network-wifi" if n.contains("wi-fi") or n.contains("wifi") or n.contains("wlan") or n.contains("wireless") else "ms-settings:network-ethernet"


static func run(action: String, arg: String = "", main: Node = null) -> void:
	match action:
		"network_settings":
			OS.shell_open(settings_page(arg))
		"firewall_helper":
			Firewall.open_helper(0, "allow")
		"firewall_settings":
			OS.shell_open("windowsdefender://network")
		"power_settings":
			OS.shell_open("ms-settings:powersleep")
		"device_manager":
			OS.create_process("mmc.exe", ["devmgmt.msc"])
		"keep_awake":
			var cfg: Dictionary = GameState.settings.get("phone_link", {})
			cfg["keep_awake"] = true
			GameState.settings["phone_link"] = cfg
			GameState.save_settings()
			if main and main.get("phone_link"):
				main.phone_link.keep_awake = true
			if DisplayServer.get_name() != "headless":
				DisplayServer.screen_set_keep_on(true)
			GameState.notify("This PC stays awake while Phone Link is on.")
