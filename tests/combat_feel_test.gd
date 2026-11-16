extends SceneTree
## Camera impulses, gunfire/blast light voices and their limits: presentation
## only, bounded, rate limited and silent with reduced effects.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const CameraRig := preload("res://scripts/player_camera.gd")
const Feel := preload("res://scripts/combat_feel.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("COMBAT FEEL %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok: failures += 1

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":"abandoned_harbor","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	for frame in 4: await process_frame
	var rig = game.player_camera
	var worker = game.players[0]
	var here: Vector2 = worker.global_position
	rig.update_view(1,true)
	var view_before: Dictionary = rig.desired_view()
	var position_before: Vector2 = game.camera.position
	var zoom_before: Vector2 = game.camera.zoom
	var settings_before: Dictionary = rig.settings()

	rig.add_trauma(.8,here)
	check(is_equal_approx(rig.trauma,.8),"An event at the followed worker applies its full trauma")
	var moved := false
	var largest := 0.0
	for step in 30:
		rig._update_impulses(1.0/60)
		var screen: Vector2 = game.camera.offset*game.camera.zoom.x
		moved = moved or screen != Vector2.ZERO
		largest = maxf(largest,maxf(absf(screen.x),absf(screen.y)))
		check(screen.is_equal_approx(screen.round()),"Shake step %d stays on whole screen pixels"%step)
	check(moved and largest <= CameraRig.MAX_SHAKE+CameraRig.MAX_KICK,"Trauma moves the view by a small bounded offset (largest %.1f px)"%largest)
	check(game.camera.position == position_before and game.camera.zoom == zoom_before,"Shake lives in Camera2D.offset; followed position and zoom are untouched")
	check(rig.desired_view().center == view_before.center and rig.desired_view().zoom == view_before.zoom and rig.settings().zoom == settings_before.zoom and rig.settings().mode == settings_before.mode,"The desired view and saved view settings do not change")
	for step in 90: rig._update_impulses(1.0/60)
	check(rig.trauma == 0.0 and game.camera.offset == Vector2.ZERO,"Trauma decays to an exactly centred view")
	for step in 40: rig.add_trauma(1.0,here)
	check(rig.trauma <= 1.0,"Stacked events cannot exceed full trauma")
	for step in 120: rig._update_impulses(1.0/60)

	rig.add_trauma(1.0,here+Vector2(5000,0))
	check(rig.trauma == 0.0,"A distant event does not shake this view")
	rig.add_trauma(1.0,here+Vector2(500,0),900.0)
	var mid: float = rig.trauma
	check(mid > 0.0 and mid < 1.0,"Trauma falls off with distance to the local worker (%.2f at 500 px)"%mid)
	for step in 120: rig._update_impulses(1.0/60)
	rig.add_trauma(NAN,here)
	rig.add_trauma(1.0,Vector2(NAN,0))
	rig.add_kick(Vector2(NAN,0),3)
	check(rig.trauma == 0.0 and game.camera.offset == Vector2.ZERO,"Non-finite events are ignored")

	for step in 30: rig.add_kick(Vector2.LEFT,4.0)
	rig._update_impulses(1.0/60)
	var kicked: Vector2 = game.camera.offset*game.camera.zoom.x
	check(kicked.x < 0.0 and absf(kicked.x) <= CameraRig.MAX_KICK,"Recoil kicks are directional and capped (%.1f px)"%kicked.x)
	for step in 60: rig._update_impulses(1.0/60)
	check(game.camera.offset == Vector2.ZERO,"A kick settles back within a second")

	rig.set_shake(0.0)
	rig.add_trauma(1.0,here)
	rig.add_kick(Vector2.LEFT,4.0)
	rig._update_impulses(1.0/60)
	check(rig.trauma == 0.0 and game.camera.offset == Vector2.ZERO,"A zero shake setting disables trauma and kick")
	rig.set_shake(7.0)
	check(rig.shake_scale == 1.0,"The shake setting is clamped")
	rig.set_shake(NAN)
	check(rig.shake_scale == 1.0,"A non-finite shake setting is ignored")
	var path := "user://combat_feel_test_camera.cfg"
	rig.settings_path = path
	rig.set_shake(.4)
	rig.save_settings()
	var second = CameraRig.new()
	second.settings_path = path
	second.load_settings()
	check(is_equal_approx(second.shake_scale,.4),"The shake setting is saved and restored with the other camera settings")
	second.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	rig.settings_path = "user://camera.cfg"
	rig.set_shake(1.0)
	rig._save_delay = -1.0

	var feel = Feel.of(worker)
	check(is_instance_valid(feel) and feel.get_parent() == game and Feel.of(worker.get_node("WorkerWeapon")) == feel,"One shared layer is created below the game on demand")
	var loose := Node2D.new()
	root.add_child(loose)
	check(Feel.of(loose) == null,"Nodes outside a game get no layer")
	loose.queue_free()

	# Two seconds of 60 shots per second from one muzzle.
	var muzzle := here+Vector2(40,-38)
	var low := INF
	var high := 0.0
	for step in 120:
		feel.shot(null,muzzle,Vector2.RIGHT,1.0,false)
		feel._process(1.0/60)
		if step >= 50 and feel.shot_lamps.size() > 0:
			low = minf(low,feel.shot_lamps[0].energy)
			high = maxf(high,feel.shot_lamps[0].energy)
	check(feel.pulses <= 7,"Sustained fire yields at most one abrupt light pulse per %.2f s (%d in 2 s)"%[Feel.MIN_PULSE_INTERVAL,feel.pulses])
	check(feel.shot_lamps.size() == 1 and feel.shot_lamps[0].enabled,"One muzzle keeps one light voice")
	check(high > 0.0 and high-low < .12*high,"Automatic fire settles into a steady glow instead of strobing (%.3f..%.3f)"%[low,high])
	for step in 240: feel._process(1.0/60)
	low = INF
	high = 0.0
	for step in 180:
		# An ordinary automatic weapon: ten rounds per second for three seconds.
		if step%6 == 0: feel.shot(null,muzzle,Vector2.RIGHT,.72,false)
		feel._process(1.0/60)
		if step >= 90:
			low = minf(low,feel.shot_lamps[0].energy)
			high = maxf(high,feel.shot_lamps[0].energy)
	check(high > 0.0 and high-low < .10*high,"Ten rounds per second ripple the light by under ten percent (%.3f..%.3f)"%[low,high])
	for index in 40: feel.shot(null,muzzle+Vector2(index*300,0),Vector2.RIGHT,2.0,index%2 == 0)
	feel._process(1.0/60)
	check(feel.shot_lamps.size() <= Feel.SHOT_LIGHTS and feel._wisp_pos.size() == Feel.MAX_WISPS and feel._halo_pos.size() == Feel.MAX_HALOS and feel._casing_pos.size() == Feel.MAX_CASINGS,"Forty muzzles stay within the fixed light, halo, smoke and casing pools")
	for step in 240: feel._process(1.0/60)
	check(feel.diagnostics().lit == 0 and not feel.is_processing(),"All voices go dark and the layer sleeps after the fire stops")

	var pulses_before: int = feel.pulses
	for step in 120: rig._update_impulses(1.0/60)
	for index in 10: game.impact(here+Vector2(120+index*8,0),"explosion",Vector2.UP,1.5)
	feel._process(1.0/60)
	check(feel.blasts_seen == 10 and feel.blast_lamps.size() <= Feel.BLAST_LIGHTS and feel.diagnostics().lit >= 1,"Ten same-frame blasts share the two blast light voices")
	check(feel.pulses-pulses_before == 1,"Same-frame blasts produce a single abrupt light pulse")
	check(rig.trauma > 0.3 and rig.trauma <= 1.0,"A nearby blast shakes the local view (trauma %.2f)"%rig.trauma)
	for step in 200:
		feel._process(1.0/60)
		rig._update_impulses(1.0/60)
	check(feel.diagnostics().lit == 0 and game.camera.offset == Vector2.ZERO,"Blast light and shake end on their own")

	game.weather.set_reduced_effects(true)
	var shots_before: int = feel.shots_seen
	feel.shot(null,muzzle,Vector2.RIGHT,1.0,false)
	game.impact(here+Vector2(100,0),"explosion",Vector2.UP,1.5)
	rig.add_trauma(1.0,here)
	rig.add_kick(Vector2.LEFT,4.0)
	feel._process(1.0/60)
	rig._update_impulses(1.0/60)
	check(feel.shots_seen == shots_before and feel.diagnostics().lit == 0 and rig.trauma == 0.0 and game.camera.offset == Vector2.ZERO,"Reduced effects: no gunfire light, no blast light, no shake, no kick")
	var reduced_burst: Node = null
	for burst in get_nodes_in_group(ImpactBurst.GROUP):
		if burst.surface_material == "explosion" and burst.reduced: reduced_burst = burst
	check(is_instance_valid(reduced_burst) and not is_instance_valid(reduced_burst.glow_layer),"Reduced effects: blasts carry no additive flash layer")
	game.weather.set_reduced_effects(false)

	# The hit read is a silhouette rim with a mild lift (no flat overexposed fill).
	var tint := WeaponEffectArt.hit_tint(.2)
	check(tint.r > 1.0 and tint.r <= 1.25 and WeaponEffectArt.hit_tint(0.0) == Color.WHITE and WeaponEffectArt.hit_tint(.2,true).r < tint.r,"The shared hit tint lifts a fresh hit without flattening it, is plain at rest and gentler with reduced effects")
	check(WeaponEffectArt.strike_rim(.2).a == 1.0 and WeaponEffectArt.strike_rim(.1).a == .5 and WeaponEffectArt.strike_rim(0.0).a == 0.0 and WeaponEffectArt.strike_rim(.2,true).a == .5 and WeaponEffectArt.strike_rim(.1,true).a == 0.0,"The hit flash is a silhouette rim: full, half, then off; reduced effects keep one half-strength step")
	check(WeaponEffectArt.hit_pop(.2) <= 1.05 and WeaponEffectArt.hit_pop(.1) == 1.0 and WeaponEffectArt.hit_pop(.2,true) == 1.0,"The hit swell is at most five percent and absent with reduced effects")

	check(await Cleanup.free_scene(game,self),"Scene cleanup")
	print("COMBAT FEEL: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
