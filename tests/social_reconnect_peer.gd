extends SceneTree
## Real service sockets and isolated durable profiles. The Python driver kills
## and restarts the service, then starts fresh Godot processes with these files.
const Hub := preload("res://scripts/social_hub.gd")
var hub
var role := ""
var phase := ""
var folder := ""
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SOCIAL RECONNECT %s: %s" % [role,label])

func mark(stage: String, data: Dictionary = {}) -> void:
	var file := FileAccess.open(folder.path_join(role + "-" + stage + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func read_marker(name: String) -> Dictionary:
	var path := folder.path_join(name + ".json")
	if not FileAccess.file_exists(path): return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

func wait_for(predicate: Callable, label: String, seconds: float = 15.0) -> bool:
	var limit := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < limit:
		if predicate.call(): return true
		await process_frame
	check(false, label + " timed out")
	return false

func _run() -> void:
	if OS.get_environment("BUNKERCREW_SOCIAL_ISOLATED") != "1": quit(2); return
	role = OS.get_environment("BUNKERCREW_SOCIAL_ROLE")
	phase = OS.get_environment("BUNKERCREW_SOCIAL_PHASE")
	folder = OS.get_environment("BUNKERCREW_SOCIAL_FOLDER")
	if role not in ["host", "guest"] or phase not in ["initial", "cold"] or folder.is_empty(): quit(2); return
	hub = Hub.new()
	hub.settings_path = folder.path_join(role + "-profile.json")
	root.add_child(hub)
	if phase == "initial":
		check("--no-profile-save" in OS.get_cmdline_user_args(), "Initial run protects default player profiles")
		check(hub.configure_server(OS.get_environment("BUNKERCREW_SOCIAL_URL")), "Real local endpoint is configured")
		check(hub.set_display_name("Mara" if role == "host" else "Ivo"), "Real display name is configured")
		check(hub.connect_service(), "Manual opt-in opens the real service")
	else:
		check("--no-profile-save" not in OS.get_cmdline_user_args(), "Cold run permits only the driver's isolated user directory")
		check(hub.connect_on_start, "Durable manual opt-in is restored in a fresh process")
	if not await wait_for(func(): return hub.connection_state == "online", "Authenticated real connection"):
		await finish(); return
	var original_code: String = hub.friend_code
	if phase == "initial": await initial_flow(original_code)
	else: await cold_flow(original_code)
	await finish()

func initial_flow(original_code: String) -> void:
	mark("public-code", {"code":original_code})
	if role == "guest":
		if not await wait_for(func(): return not read_marker("host-public-code").is_empty(), "Host's public friend code"): return
		check(hub.add_friend(str(read_marker("host-public-code").code)), "Real outgoing request is sent")
	else:
		if not await wait_for(func(): return not hub.requests.is_empty(), "Real incoming request"): return
		check(hub.accept_friend(str(hub.requests[0].code)), "Real incoming request is accepted")
	if not await wait_for(func(): return hub.friends.size() == 1, "Mutual durable friendship"): return
	var friend: String = str(hub.friends[0].code)
	if role == "host": hub.set_presence({"status":"playing","environment":"mountain_pass","joinable":false,"room_code":"","relay_url":""})
	else:
		if not await wait_for(func(): return hub.friends[0].status == "playing", "Actual friend's playing presence"): return
	mark("ready")
	if not await wait_for(func(): return hub.connection_state == "error", "Hard service outage"): return
	check(hub.friends[0].status == "offline" and not hub.friends[0].joinable, "Outage clears stale online/joinable state immediately")
	mark("disconnected")
	if not await wait_for(func(): return hub.connection_state == "online", "Automatic reconnection after real server restart", 20.0): return
	check(hub.friend_code == original_code and hub.friends.size() == 1 and hub.friends[0].code == friend, "Same credential and friendship recover after database restart")
	if role == "guest":
		if not await wait_for(func(): return hub.friends[0].status == "playing", "Latest presence is republished after reconnect"): return
	check(hub.requests.is_empty() and hub.invitations.is_empty(), "Restart introduces no duplicate requests or stale invitations")
	mark("reconnected", {"code":original_code})
	await wait_for(func(): return not read_marker("done-initial").is_empty(), "Peer has also reconnected")

func cold_flow(original_code: String) -> void:
	var previous: Dictionary = read_marker(role + "-public-code")
	check(not previous.is_empty() and original_code == previous.get("code", ""), "Fresh process authenticates the original stable public code")
	check(hub.friends.size() == 1 and hub.display_name == ("Mara" if role == "host" else "Ivo"), "Server and client restarts preserve the accepted friend and display name")
	mark("cold-connected")
	if role == "host":
		check(hub.set_display_name("Mära"), "Unicode rename queues an authenticated server update")
	else:
		await wait_for(func(): return hub.friends[0].name == "Mära", "Friend receives the confirmed Unicode rename")
	await wait_for(func(): return not read_marker("done-cold").is_empty(), "Both cold processes finish")

func finish() -> void:
	hub.queue_free()  # Application exit preserves opt-in; explicit Logout clears it.
	await process_frame
	print("SOCIAL RECONNECT %s %s: %d/%d checks passed" % [phase,role,checks-failures,checks])
	quit(1 if failures else 0)
