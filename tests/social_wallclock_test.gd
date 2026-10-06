extends SceneTree
## Social service deadlines must keep real time across a blocked engine frame.
const Hub := preload("res://scripts/social_hub.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/beta-0.5-hardening-20261004/network/social-wallclock.json"
var checks := 0
var failures := 0
var evidence: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("SOCIAL CLOCK %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var hub := Hub.new()
	root.add_child(hub)
	hub.set_process(false)
	check(hub._socket == null and not hub._wanted,"Actual isolated Hub remains offline without creating a socket")
	hub._process(0.0)
	var before: float = hub._clock
	var started := Time.get_ticks_usec()
	var replies: Array[Dictionary] = []
	hub.room_resolved.connect(func(resolved_request: String, result: Dictionary): replies.append({"request":resolved_request,"result":result}))
	var request := "a".repeat(32)
	hub._room_requests[request] = {"code":"ABCDEF","deadline":hub._clock + .25,"sent":false}
	OS.delay_msec(350)
	hub._process(.01)
	var wall := float(Time.get_ticks_usec() - started) / 1000000.0
	var elapsed: float = hub._clock - before
	evidence = {"wall_seconds":wall,"social_seconds":elapsed,"supplied_engine_delta":.01}
	check(absf(elapsed - wall) < .03,"Blocked engine frame counts fully toward the social service clock")
	check(not hub._room_requests.has(request) and replies.size() == 1 and replies[0].request == request and replies[0].result == {"ok":false,"error_code":"service_unavailable"},"Expired real broker lookup emits its single existing failure immediately after the stall")
	var future := "b".repeat(32)
	hub._room_requests[future] = {"code":"ABCDEF","deadline":hub._clock + 2.0,"sent":false}
	hub._process(10.0)
	check(hub._room_requests.has(future) and replies.size() == 1,"Accelerated simulation delta cannot expire a live real-time broker lookup")
	hub._client_tokens = 0.0
	before = hub._clock
	hub._process(100.0)
	check(hub._client_tokens < .2 and hub._clock - before < .1,"Accelerated simulation delta cannot refill the social action budget")
	started = Time.get_ticks_usec()
	OS.delay_msec(120)
	hub._process(0.0)
	wall = float(Time.get_ticks_usec() - started) / 1000000.0
	check(absf(hub._client_tokens - minf(8.0,wall * 2.0)) < .06,"Client action tokens refill at their actual elapsed-time rate")
	# Sample an already-connecting broker: queue its public request through
	# the actual method without opening a socket or authenticating a profile.
	hub.connection_state = "connecting"
	before = hub._clock
	OS.delay_msec(120)
	var fresh: String = hub.resolve_short_code("ABCDEF")
	var fresh_deadline: float = float(hub._room_requests.get(fresh,{}).get("deadline",0.0))
	check(not fresh.is_empty() and fresh_deadline - before >= 15.11 and hub._socket == null,"Lookup requested after idle starts its full real timeout at the action, not the last engine tick")
	hub._cancel_room_requests()
	check(replies.size() == 3 and hub._room_requests.is_empty(),"Cancelling remaining real requests still reports each exactly once")
	check(hub._socket == null and hub._identities.is_empty(),"Deadline coverage creates neither a transport nor a saved identity")
	check(await Cleanup.free_scene(hub,self),"Actual social Hub releases cleanly")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	FileAccess.open(OUTPUT,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks-failures,"failures":failures,"evidence":evidence,"fixture":"Actual offline SocialHub, real 350ms/120ms OS stalls, no sockets; original broker request/signal and token paths, capped/accelerated simulation deltas, isolated XDG and no-save flags."},"\t") + "\n")
	print("SOCIAL WALLCLOCK: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
