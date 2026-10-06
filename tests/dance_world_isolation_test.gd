extends SceneTree
## A real isolated lab must not inherit combat groups from the open match.
const Lab := preload("res://scripts/music_dev_dashboard.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	InputSetup.install()
	var lab := Lab.new()
	lab.audition_enabled = false
	root.add_child(lab)
	lab.set_process(false)
	var actor: Worker = lab.preview_world.actors[0]
	var visual: WorkerVisual = actor.get_node("PixelVisual")
	lab.preview_clock.playing = true
	lab.preview_clock.elapsed = 4.0
	lab._process(0.5)
	check(visual.idle_allowed() and visual.rhythm.weight > 0.0,"The actual silent developer preview rests into its prepared beat")
	var match_enemy := Node2D.new()
	match_enemy.position = actor.position
	root.add_child(match_enemy)
	match_enemy.add_to_group("enemies")
	check(match_enemy.get_world_2d()!=actor.get_world_2d(),"Actual lab actors and the open match occupy independent World2D instances")
	lab._process(0.5)
	check(visual.idle_allowed() and visual.rhythm.weight > 0.0,"Enemies from the open match cannot cancel the isolated lab's dance")
	match_enemy.remove_from_group("enemies")
	match_enemy.add_to_group("air_projectiles")
	lab._process(0.5)
	check(visual.idle_allowed() and visual.rhythm.weight > 0.0,"Ordnance from the open match cannot cancel the isolated lab's dance")
	match_enemy.queue_free()
	var local_threat := Node2D.new()
	local_threat.position = actor.position
	lab.preview_world.add_child(local_threat)
	local_threat.add_to_group("enemies")
	lab._process(0.0)
	check(not visual.idle_allowed() and visual.rhythm.weight==0.0,"A real nearby enemy in the same world still immediately cancels dancing")
	local_threat.remove_from_group("enemies")
	local_threat.add_to_group("air_projectiles")
	lab._process(0.0)
	check(not visual.idle_allowed() and visual.rhythm.weight==0.0,"Nearby ordnance in the same world still immediately cancels dancing")
	local_threat.queue_free()
	lab._process(0.5)
	check(visual.idle_allowed() and visual.rhythm.weight > 0.0,"A queued retired threat cannot hold the rig in a false danger state")
	check(await Cleanup.free_scene(lab,self),"Actual isolated lab rigs and preview audio retire cleanly")
	print("DANCE WORLD ISOLATION: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
