extends SceneTree
## Production is authoritative; the mixer child only presents its clocks.
## A separate replica scene verifies that its disabled production process does
## not also freeze drum presentation or accidentally produce free concrete.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const World := preload("res://scripts/network_world.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func advance(station: ProductionStation, animation: Node, seconds: float) -> void:
	var remaining := seconds
	while remaining > .000001:
		var step := minf(remaining,1.0/60.0)
		station._process(step)
		animation.advance_visual(step)
		remaining -= step

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func scene():
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.running = false
	freeze(game)
	return game

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	var station := ProductionStation.new()
	root.add_child(station)
	station.set_process(false)
	var animation := station.get_node_or_null("MixerAnimation")
	check(is_instance_valid(animation), "Concrete mixer owns an independent drum presentation child")
	if not is_instance_valid(animation):
		await Cleanup.free_scene(station,self)
		quit(1)
		return
	animation.set_process(false)
	var idle_phase: float = animation.phase
	advance(station,animation,.8)
	check(is_equal_approx(animation.phase,idle_phase) and animation.angular_speed == 0.0, "An empty mixer stays still")
	var original_binder := station.binder
	station.input_amount = station.input_cost("sand")
	station._process(0)
	check(station.working and station.input_amount == 0 and station.binder == original_binder-1, "Starting a batch consumes the existing sand and binder recipe once")
	advance(station,animation,1.0)
	check(animation.phase != idle_phase and animation.angular_speed > 0.0, "A real production clock starts the drum and builds rotation speed")
	check(station.output_amount == 0 and is_equal_approx(station.production_time,1.0), "Animation does not accelerate production or grant early concrete")
	var duration := station.duration()
	advance(station,animation,duration-1.05)
	check(station.working and station.output_amount == 0, "The batch remains unfinished immediately before its real recipe duration")
	advance(station,animation,.10)
	check(not station.working and station.output_amount == int(station.recipe().amount), "The original batch duration produces exactly the configured concrete amount")
	check(station.input_amount == 0 and station.binder == original_binder-1, "Visual motion cannot spend another ingredient or binder charge")
	advance(station,animation,1.0)
	var final_phase: float = animation.phase
	check(animation.angular_speed == 0.0, "The drum decelerates to a complete stop")
	advance(station,animation,.8)
	check(is_equal_approx(animation.phase,final_phase), "Idle preserves the final drum orientation")
	check(station.output_amount == int(station.recipe().amount), "Idle visual updates do not duplicate finished concrete")
	station.output_amount = 0
	station.input_amount = station.input_cost("sand")
	station.set_process(true)
	animation.set_process(true)
	await create_timer(.15).timeout
	check(station.working, "A new real processing batch can start after removing finished output")
	paused = true
	var paused_clock := station.elapsed
	var paused_production := station.production_time
	var paused_phase: float = animation.phase
	await create_timer(.12,true).timeout
	check(station.elapsed == paused_clock and station.production_time == paused_production, "Pause freezes the production and source clocks")
	check(animation.phase == paused_phase, "Pause also freezes visible drum rotation")
	paused = false
	await create_timer(.1).timeout
	check(station.elapsed > paused_clock and animation.phase != paused_phase, "Resuming restarts production and drum motion together")
	check(await Cleanup.free_scene(station,self), "Standalone production fixture releases cleanly")
	var host = scene()
	var host_mixer: ProductionStation = get_nodes_in_group("stations").filter(func(item): return item.game == host and item.kind == "mixer")[0]
	host_mixer.input_amount = host_mixer.input_cost("sand")
	host_mixer._process(0.0)
	host_mixer._process(1.0)
	var authority := World.new()
	authority.bind(host)
	var first: Dictionary = authority.capture()
	host_mixer._process(.4)
	var second: Dictionary = authority.capture()
	host_mixer._process(host_mixer.duration())
	var finished: Dictionary = authority.capture()
	check(await Cleanup.free_scene(host,self), "Host fixture releases before the independent client scene")
	var guest = scene()
	var replica := World.new()
	replica.bind(guest)
	var guest_mixer: ProductionStation = get_nodes_in_group("stations").filter(func(item): return item.game == guest and item.kind == "mixer")[0]
	var guest_animation := guest_mixer.get_node("MixerAnimation")
	# scene() freezes its fixture for construction. Restore only the visual
	# child's normal callback before applying snapshots, so freeze_client itself
	# must preserve presentation while disabling authoritative production.
	guest_animation.set_process(true)
	check(replica.apply(first), "Guest accepts the ordinary station snapshot: "+replica.last_error)
	check(not guest_mixer.is_processing() and guest_animation.is_processing(), "Replica production stays disabled while its visual child can render")
	var initial_phase: float = guest_animation.phase
	await create_timer(.12).timeout
	check(guest_animation.phase != initial_phase, "A frozen production replica still turns its drum from received clocks")
	check(is_equal_approx(guest_mixer.production_time,1.0) and guest_mixer.output_amount == 0, "Replica animation cannot advance recipe time or manufacture concrete")
	await create_timer(.25).timeout
	var stale_phase: float = guest_animation.phase
	await create_timer(.15).timeout
	check(is_equal_approx(guest_animation.phase,stale_phase), "A stalled snapshot stream cannot leave the drum spinning indefinitely")
	check(replica.apply(second), "A later host production snapshot is accepted: "+replica.last_error)
	await create_timer(.12).timeout
	check(guest_animation.phase != stale_phase and is_equal_approx(guest_mixer.production_time,1.4), "Fresh source clocks resume replica presentation without local production")
	check(replica.apply(finished), "The actual completion snapshot is accepted: "+replica.last_error)
	check(not guest_mixer.working and guest_mixer.output_amount == int(guest_mixer.recipe().amount), "Guest receives exactly the host's completed batch")
	check(await Cleanup.free_scene(guest,self), "Guest fixture releases its drum material and scene")
	print("MIXER ANIMATION: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
