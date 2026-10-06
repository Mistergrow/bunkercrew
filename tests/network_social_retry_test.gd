extends SceneTree
## Failed social publications must retry without duplicating accepted updates.
const Session := preload("res://scripts/network_session.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

class FixtureSession extends Session:
	var fail_kind := ""
	var attempted: Array[Dictionary] = []
	var delivered: Array[Dictionary] = []
	func _send(message: Dictionary, _reliable := true, _target_id: int = 0) -> bool:
		attempted.append(message.duplicate(true))
		if message.kind == fail_kind:
			fail_kind = ""
			return false
		delivered.append(message.duplicate(true))
		return true

class FixtureHub extends Node:
	@warning_ignore("unused_signal")
	signal crew_identity_verified(request: String, result: Dictionary)
	var connection_state := "offline"
	var display_name := "Mara"
	var blocked: Array = []
	var claim_enabled := true
	func crew_identity(context: String) -> Dictionary:
		return {"code":"ABCDEFGHJKLM", "service":"wss://friends.example/social", "context":context, "proof":"b".repeat(64)} if claim_enabled else {}

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _run() -> void:
	var session := FixtureSession.new()
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.active = true
	session.is_host = false
	session._authenticated = true
	session.local_player_id = 2
	session._client_token = "a".repeat(48)
	session._social.session = session
	session._social.blocked[1] = true
	session.fail_kind = "crew_preferences"
	session._social.preferences()
	check(session.delivered.is_empty(), "A rejected transmission does not reach the host")
	session._social.preferences()
	check(session.delivered.size() == 1 and session.delivered[0].blocked == [1], "Unchanged blocking preference retries after a failed send")
	session._social.preferences()
	check(session.attempted.size() == 2, "Accepted blocking preference is not published repeatedly")
	session._social.blocked.clear()
	session.fail_kind = "crew_preferences"
	session._social.preferences()
	session._social.preferences()
	check(session.delivered.size() == 2 and session.delivered[-1].blocked.is_empty(), "Unblocking also retries so the host resumes private delivery")
	var hub := FixtureHub.new()
	root.add_child(hub)
	session.attempted.clear()
	session.delivered.clear()
	session.fail_kind = "crew_identity"
	session.refresh_social_identity(hub)
	session.refresh_social_identity(hub)
	check(session.delivered.size() == 1 and session.delivered[0].identity.code == "ABCDEFGHJKLM", "Identity verification claim retries after a failed send")
	session.refresh_social_identity(hub)
	check(session.attempted.size() == 2, "Accepted identity claim is sent once")
	hub.claim_enabled = false
	session.fail_kind = "crew_identity"
	session.refresh_social_identity(hub)
	session.refresh_social_identity(hub)
	check(session.delivered.size() == 2 and session.delivered[-1].identity.is_empty(), "Withdrawing an identity retries too")
	session.active = false
	await Cleanup.free_scene(session, self)
	await Cleanup.free_scene(hub, self)
	print("NETWORK SOCIAL RETRY: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
