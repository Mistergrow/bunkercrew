extends SceneTree
## Explicit temporary profiles, hostile packet shapes and no external services.
const Hub := preload("res://scripts/social_hub.gd")
const JoinCode := preload("res://scripts/network_join_code.gd")
var checks := 0
var failures := 0
var profiles: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func create_hub(path: String = ""):
	var hub := Hub.new()
	if not path.is_empty():
		hub.settings_path = path
		profiles.append(path)
	root.add_child(hub)
	return hub

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var untouched = create_hub()
	check(untouched.connection_state == "offline" and untouched.friend_code.is_empty() and untouched._identities.is_empty(), "No-profile-save neither reads nor connects an existing user account")
	check(not untouched.add_friend("ABCDEFGHJKLM") and not untouched.error_message.is_empty(), "Offline friend requests fail with a useful status")
	for name_value in ["Mära", "Mara 🎧", "Ivo 2", "水手"]:
		check(Hub.valid_name(name_value), "Unicode names remain usable")
	for name_value in ["", "x".repeat(25), "Mara\n", "Mara\u202e", "Mara\u061c", "Mara\u200b", "Mara\u2028", " Mara"]:
		check(not Hub.valid_name(name_value), "Invisible/control and oversized names are rejected")
	for url in ["ws://localhost:8765/ws", "ws://127.0.0.1:8765", "wss://play.example.com/ws", "wss://play.example.com/social"]:
		check(not Hub.normalize_url(url).is_empty() and Hub.normalize_url(url).ends_with("/social"), "Service endpoint normalization keeps TLS/loopback policy")
	for url in ["ws://play.example.com/ws", "ws://192.168.1.2/ws", "wss://secret@play.example.com/ws", "wss://play.example.com:99999/ws", "wss://play.example.com/ws?secret=x", "wss://play.example.com/no-route", "wss://play..example.com/ws"]:
		check(Hub.normalize_url(url).is_empty(), "Malformed and insecure external endpoints are rejected")
	check(Hub.valid_code("ABCD-EFGH-JKLM") and not Hub.valid_code("ABCDEF") and not Hub.valid_code("ABCDEFGHIJKL"), "Public friend code remains distinct from a relay room code")
	var path := "res://artifacts/social/profile-test-%d.json" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var first = create_hub(path)
	check(first.set_display_name("Mära"), "Explicit isolated profile stores its display name")
	check(first.configure_server("ws://127.0.0.1:24979/ws"), "Explicit isolated profile stores its server endpoint")
	check(first.connect_service(), "Connecting creates a cryptographic identity and a real loopback socket")
	var identity: Dictionary = first._identities[first.server_url].duplicate(true)
	check(str(identity.secret).length() == 64 and identity.secret.is_valid_hex_number(false), "Credentials contain 256 random bits")
	first.friend_code = "ABCDEFGHJKLM"
	first._identities[first.server_url].code = first.friend_code
	check(first._save_profile(), "Ready identity and public code persist atomically")
	if OS.get_name() in ["Linux", "macOS", "FreeBSD", "OpenBSD", "NetBSD", "Android", "iOS"]:
		check(FileAccess.get_unix_permissions(path) == (FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER), "Primary credential file is owner-only")
		check(FileAccess.get_unix_permissions(path + ".bak") == (FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER), "Backup credential file is owner-only")
	first._wanted = false
	first._socket.close()
	first.queue_free()
	await process_frame
	var second = create_hub(path)
	check(second.display_name == "Mära" and second.friend_code == "ABCDEFGHJKLM" and second._identities[second.server_url].secret == identity.secret, "Fresh node restores the same profile identity and public code")
	check(second.connect_on_start and second.connection_state == "offline", "Opt-in survives but no-profile-save prevents automatic connections")
	check(second.configure_server("ws://localhost:24979/social") and second.connect_service(), "A different service receives an independent identity")
	check(second._identities[second.server_url].secret != identity.secret, "Credentials never cross service boundaries")
	second.disconnect_service()
	second.queue_free()
	await process_frame
	# Preserve a fully valid backup and corrupt the primary exactly as an
	# interrupted external write would. Loading must keep the old credential.
	var backup := {"version":1,"name":"Mära","server":"ws://127.0.0.1:24979/social","connect_on_start":true,"identities":{"ws://127.0.0.1:24979/social":{"secret":identity.secret,"code":"ABCDEFGHJKLM"}}}
	var backup_file := FileAccess.open(path + ".bak", FileAccess.WRITE)
	backup_file.store_string(JSON.stringify(backup)); backup_file.close()
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{interrupted"); broken.close()
	var recovered = create_hub(path)
	check(recovered.friend_code == "ABCDEFGHJKLM" and recovered._identities[recovered.server_url].secret == identity.secret, "Corrupt primary recovers the last valid identity rather than replacing it")
	check(FileAccess.get_file_as_string(path) == "{interrupted", "Opening a recovered profile does not rewrite files")
	var oversized := FileAccess.open(path, FileAccess.WRITE)
	oversized.store_string(" ".repeat(Hub.MAX_PROFILE_BYTES + 1)); oversized.close()
	check(recovered._read_profile(path).is_empty(), "Oversized profiles are rejected before parsing")
	var packet := {"op":"state","friends":[],"requests":[],"blocked":[],"invitations":[]}
	recovered.connection_state = "online"
	check(recovered._receive(packet), "Valid bounded social state is accepted")
	var malformed := packet.duplicate(true)
	malformed.invitations = [{"id":"a".repeat(32),"from_code":"ABCDEFGHJKLM","name":"Mara","room_code":"ABCDEF","relay_url":"ws://127.0.0.1:8765/ws"}]
	check(not recovered._receive(malformed), "Missing invitation expiry is rejected without an invalid dictionary access")
	malformed.invitations[0].expires = INF
	check(not recovered._receive(malformed), "Nonfinite invitation expiry is rejected")
	malformed.invitations[0].expires = Time.get_unix_time_from_system() + 120.0
	check(not recovered._receive(malformed), "Unknown senders cannot appear as confirmed friend invitations")
	malformed.friends = [{"code":"ABCDEFGHJKLM","name":"Mara","status":"lobby","environment":"ash_foundry","joinable":true}]
	check(recovered._receive(malformed) and recovered.invitations.size() == 1, "Actual six-character relay invitations match the service contract")
	malformed.invitations[0].room_code = JoinCode.invite("127.0.0.1",24777,"23456789ABCDEFGH")
	malformed.invitations[0].relay_url = ""
	check(recovered._receive(malformed), "Authenticated direct invitations retain their address checksum and invitation secret")
	malformed.invitations[0].room_code = "ABCDEF"
	check(not recovered._receive(malformed), "Short relay codes are rejected for direct invitations")
	recovered.connection_state = "connecting"
	var ready_bad := {"op":"ready","code":"JKLMNPQRSTUV","name":"Ivo","friends":[],"requests":[],"blocked":[],"invitations":[{}]}
	check(not recovered._receive(ready_bad) and recovered.friend_code == "ABCDEFGHJKLM", "Malformed ready packet cannot partially replace the persistent identity")
	recovered.disconnect_service()
	recovered.queue_free()
	untouched.queue_free()
	await process_frame
	for profile_path in profiles:
		for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
			if FileAccess.file_exists(profile_path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path + suffix))
	print("SOCIAL HUB: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
