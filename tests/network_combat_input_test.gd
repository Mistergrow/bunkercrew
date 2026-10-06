extends SceneTree
## Synthetic fixture input must preserve ordinary one-shot release edges.
const FIXTURE := preload("res://tests/network_combat_performance_peer.gd")
const NetInput := preload("res://scripts/network_input.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("NETWORK_COMBAT_INPUT_FAILED "+label)

func _run() -> void:
	if not InputMap.has_action("p1_reload"): InputMap.add_action("p1_reload")
	var model := Node2D.new()
	root.add_child(model)
	Input.action_press("p1_reload")
	await process_frame
	FIXTURE.release_action("p1_reload")
	check("reload" in NetInput.sample_local(model).released,"first held-to-released transition reaches native input")
	await process_frame
	FIXTURE.release_action("p1_reload")
	check(not "reload" in NetInput.sample_local(model).released,"releasing an already released key does not synthesize another network edge")
	var guarded := preload("res://scripts/network_session.gd").new()
	var repeated := preload("res://scripts/network_session.gd").new()
	var denied_normal := 0
	var denied_repeated := 0
	var edges := 0
	for frame in 180:
		await process_frame
		FIXTURE.release_action("p1_reload")
		var input := NetInput.sample_local(model)
		edges+=input.released.size()
		guarded._clock=float(frame)/60.0
		repeated._clock=guarded._clock
		if frame%2==0 or not input.released.is_empty():
			if not guarded._allow_message("input"): denied_normal+=1
		# Input may legitimately carry edges at every 60-Hz physics frame.
		# Deliberate 120-Hz traffic still exceeds the bounded catch-up budget.
		for _attempt in 2:
			if not repeated._allow_message("input"): denied_repeated+=1
	check(edges==0,"held-release guard remains quiet across 180 consecutive actual input samples")
	check(denied_normal==0,"ordinary30Hz input stays inside the actual production rate budget")
	check(denied_repeated>0,"deliberate120Hz traffic exceeds the finite60Hz rate plus supported catch-up burst")
	Input.action_press("p1_reload")
	await process_frame
	FIXTURE.release_action("p1_reload")
	check("reload" in NetInput.sample_local(model).released,"a later genuine reload key release is still preserved")
	guarded.free()
	repeated.free()
	model.queue_free()
	await process_frame
	print("NETWORK_COMBAT_INPUT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
