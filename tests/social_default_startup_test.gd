extends SceneTree
## One normal application startup in an explicitly disposable XDG directory.
const Settings := preload("res://scripts/social_service_config.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _run() -> void:
	var isolated := OS.get_environment("XDG_DATA_HOME")
	if not isolated.begins_with("/tmp/bunkercrew-public-startup-") or "--no-profile-save" in OS.get_cmdline_user_args() or Settings.DEFAULT_URL.is_empty(): quit(2); return
	var hub := root.get_node("SocialHub")
	check(hub.server_url == Settings.DEFAULT_URL, "Fresh application selects the actually deployed central service")
	check(ProjectSettings.globalize_path(hub.settings_path).begins_with(isolated + "/"), "All profile writes are contained in the disposable fixture directory")
	if "--verify-opt-out" in OS.get_cmdline_user_args():
		check(hub._has_saved_profile and not hub.connect_on_start, "A valid saved offline preference is restored even with an empty identity set")
		var offline_until := Time.get_ticks_msec() + 1200
		while Time.get_ticks_msec() < offline_until: await process_frame
		check(hub.connection_state == "offline" and hub._socket == null, "Explicit disconnect stays offline after normal application restart")
		print("SOCIAL DEFAULT OPT OUT: %d/%d checks passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return
	var deadline := Time.get_ticks_msec() + 18000
	while hub.connection_state != "online" and Time.get_ticks_msec() < deadline: await process_frame
	check(hub.connection_state == "online" and hub.friend_code.length() == 12, "Normal fresh startup authenticates publicly without manual configuration")
	check(hub.connect_on_start and FileAccess.file_exists(hub.settings_path), "Automatic presence opt-in and local identity persist for the next startup")
	check(hub.friends.is_empty() and hub.requests.is_empty() and hub.blocked.is_empty(), "An isolated fresh identity inherits no other player's contacts")
	check(hub._peer_key.length() == 64, "Actual deployed server supports verified crew identities")
	hub.disconnect_service()
	print("SOCIAL DEFAULT STARTUP: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
