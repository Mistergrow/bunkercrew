extends SceneTree
## Actual held interaction while moving away must draw towards its real target
## without changing movement/facing or losing the underlying world-space gait.
const Rig := preload("res://scripts/worker_locomotion.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const MiningPose := preload("res://scripts/mining_worker_pose.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const IDS := ["mara","branko","ivo","nora","levin","selma","oskar","rika"]
var checks := 0
var failures := 0

class RoundFixture extends Node:
	var phase := "salvage"
	var wave := 16

class WorldFixture extends Node2D:
	var rounds: Node
	var target: Node2D
	func get_focus(_worker: Node2D) -> Node2D: return target

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	InputSetup.install()
	var world := WorldFixture.new()
	world.rounds = RoundFixture.new()
	world.add_child(world.rounds)
	root.add_child(world)
	var worker := Worker.new()
	worker.game = world
	world.add_child(worker)
	worker.set_physics_process(false)
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	worker.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	visual.idle_clock.wait_remaining = 1000
	var station := ProductionStation.new()
	station.kind = "furnace"
	world.add_child(station)
	station.set_process(false)
	world.target = station
	Input.action_press("p1_interact")
	for id: String in IDS:
		worker.configure_character(id)
		for facing: float in [-1.0,1.0]:
			worker.position = Vector2.ZERO
			worker.facing = facing
			worker.velocity = Vector2(facing*80,0)
			worker.inventory = {"ore":2}
			worker.selected_kind = "ore"
			worker._interaction_held = false
			worker._requires_interact_release = false
			station.position = Vector2(-facing*48,0)
			station.transfer.clear()
			visual.locomotion = Rig.new()
			worker._update_interaction(.05)
			check(worker._interacting and worker.focus==station and worker.facing==facing and float(station.transfer.get(worker.get_instance_id(),0))>0,id+": real held interaction is allowed behind a walking worker and keeps authoritative facing")
			var before := [worker.position,worker.velocity,worker.facing,worker.inventory.duplicate(true),station.transfer.duplicate(true),station.input_amount]
			visual._process(.2)
			var pose: Dictionary = visual.work_pose
			check(not pose.is_empty() and pose.work_action=="deposit",id+": actual WorkerVisual still renders the accepted machine deposit")
			if not pose.is_empty():
				var transform := ActorWeatherGeometry.worker_transform(visual)
				var world_contact: Vector2 = visual.to_global(transform*Vector2(pose.work_contact))
				check((world_contact.x-worker.global_position.x)*(station.global_position.x-worker.global_position.x)>0,id+": visible hands/working contact face the actual rearward furnace on either side")
				var body := PoseArt.torso_transform(pose)
				for limb in 2:
					check(Vector2(pose.hands[limb]).distance_to(body*PoseArt.shoulder_local(pose,limb))<22.91,id+": target-facing machine hands keep both arms connected")
			check(before==[worker.position,worker.velocity,worker.facing,worker.inventory,station.transfer,station.input_amount],id+": presentation changes no authoritative position, velocity, facing, ingredients or clock")
			var base := visual.locomotion._previous
			for limb in 2:
				var expected := Vector2(base.feet[limb])*Vector2(facing,1)
				var actual := ActorWeatherGeometry.worker_transform(visual)*Vector2(pose.feet[limb])
				check(actual.is_equal_approx(expected),id+": working toward a rearward target preserves each underlying world-space gait foot")
			check((ActorWeatherGeometry.worker_transform(visual)*Vector2(pose.hip)).is_equal_approx(Vector2(base.hip)*Vector2(facing,1)),id+": target-facing work preserves the actual walking hip and supported leg attachments")
			var work_feet: Array[Vector2] = []
			for limb in 2:
				work_feet.append(ActorWeatherGeometry.worker_transform(visual)*Vector2(pose.feet[limb]))
			worker._interacting = false
			worker.focus = null
			worker.velocity = Vector2.ZERO
			visual._process(0.0)
			for limb in 2:
				check((ActorWeatherGeometry.worker_transform(visual)*Vector2(visual.pose_skeleton.feet[limb])).is_equal_approx(work_feet[limb]),id+": actual WorkerVisual exits rearward work without mirroring the old planted world soles")
			# Mining already chooses its own target-facing drawing direction. Its
			# first released frame must retain the old supported world-space boots.
			worker.inventory.clear()
			worker.velocity = Vector2.ZERO
			var old_pose := MiningPose._sample_local(Vector2(58,-22),3,false,id)
			old_pose.facing = -facing
			var transition := Rig.new()
			transition.follow(old_pose,worker)
			var released := transition.advance(worker,"idle",0.0)
			for limb in 2:
				check((Vector2(released.feet[limb])*Vector2(facing,1)).is_equal_approx(Vector2(old_pose.feet[limb])*Vector2(-facing,1)),id+": releasing target-facing mining preserves the painted world-space boot before the normal transition")
	Input.action_release("p1_interact")
	check(await CLEANUP.free_scene(world,self),"Directional interaction fixtures release all owning nodes")
	print("WORKER WORK TARGET DIRECTION: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
