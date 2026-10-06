extends SceneTree
## Real sockets and production-duration deadlines, with paused slow gameplay.
const Hub := preload("res://scripts/social_hub.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var observations: Dictionary = {}
var hub: Node

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func wait_for(predicate: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_usec() + int(seconds * 1000000)
	while Time.get_ticks_usec() < end:
		if predicate.call(): return true
		await process_frame
	return false

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2); return
	hub = Hub.new()
	hub.persistence_enabled = false
	root.add_child(hub)
	Engine.time_scale = .1
	paused = true
	var replies: Array[Dictionary] = []
	var identities: Array[Dictionary] = []
	hub.room_resolved.connect(func(_request: String, reply: Dictionary): replies.append({"reply":reply,"at":Time.get_ticks_usec()}))
	hub.crew_identity_verified.connect(func(_request: String, reply: Dictionary): identities.append({"reply":reply,"at":Time.get_ticks_usec()}))
	check(hub.configure_server(OS.get_environment("BUNKERCREW_DEADLINE_SILENT")), "Only the test-owned silent TLS endpoint is configured")
	var started := Time.get_ticks_usec()
	var unresolved: String = hub.resolve_short_code("ABCDEF")
	check(not unresolved.is_empty() and hub._socket != null, "Short-code lookup opens an actual socket to the silent service")
	check(await wait_for(func(): return replies.size() == 1, 14), "A silent handshake ends its original room request within the real connection deadline")
	var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
	observations.silent_tls_seconds = elapsed
	check(elapsed >= 11.8 and elapsed <= 13.0 and hub._room_requests.is_empty() and hub.connection_state == "error", "Twelve real seconds bound TLS connection and pending lookup despite pause and 0.1 gameplay speed")
	hub.disconnect_service()
	check(hub.configure_server(OS.get_environment("BUNKERCREW_DEADLINE_SERVICE")) and hub.connect_service(), "Real authenticated test service opens normally")
	check(await wait_for(func(): return hub.connection_state == "online", 5), "Normal production SocialService authenticates this isolated client")
	replies.clear()
	started = Time.get_ticks_usec()
	var room: String = hub.resolve_short_code("ABCDEF")
	var friend := "A".repeat(12)
	check(not room.is_empty() and hub.add_friend(friend), "Actual room and friend commands are sent through their ordinary paths")
	check(hub.verify_crew_identity({"service":hub.server_url,"code":friend,"context":"a".repeat(48),"proof":"b".repeat(64)}, "deadline-check"), "Actual crew identity verification is sent through the authenticated socket")
	check(await wait_for(func(): return identities.size() == 1 and not hub.is_friend_request_pending(friend), 10), "Missing friend and crew acknowledgements both finish within eight real seconds")
	observations.friend_seconds = float(Time.get_ticks_usec() - started) / 1000000.0
	observations.crew_seconds = float(int(identities[0].at) - started) / 1000000.0 if not identities.is_empty() else -1.0
	check(observations.friend_seconds >= 7.8 and observations.friend_seconds <= 9.0 and observations.crew_seconds >= 7.8 and observations.crew_seconds <= 9.0 and hub._crew_requests.is_empty(), "Independent eight-second acknowledgement deadlines expire and release their bounded queues")
	check(await wait_for(func(): return replies.size() == 1, 8), "An unanswered authenticated room lookup finishes within fifteen real seconds")
	observations.room_seconds = float(Time.get_ticks_usec() - started) / 1000000.0
	check(observations.room_seconds >= 14.8 and observations.room_seconds <= 16.0 and replies.size() == 1 and hub._room_requests.is_empty() and hub.connection_state == "online", "Room timeout neither retries the original action forever nor tears down the healthy social link")
	await process_frame
	check(replies.size() == 1 and identities.size() == 1, "Each timed-out asynchronous request completes exactly once")
	hub.disconnect_service()
	paused = false
	Engine.time_scale = 1.0
	check(await Cleanup.free_scene(hub, self), "Real deadline fixture releases its isolated hub and sockets")
	print("SOCIAL_DEADLINE_EVIDENCE ", JSON.stringify(observations))
	print("SOCIAL DEADLINE: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
