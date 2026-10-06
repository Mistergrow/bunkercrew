extends SceneTree
## Covers all mechanical catalog enemies and the final boss. Prepared combat evidence
## follows the same observation path used by authoritative and replicated actors.
const Pose := preload("res://scripts/enemy_motion_pose.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
class WeatherProbe extends RefCounted:
	var reduced_effects := false
class GameProbe extends Node2D:
	var weather := WeatherProbe.new()
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func finish_action(motion) -> void:
	motion.advance(Pose.duration(motion.state,motion.identity)+0.1)
func run() -> void:
	var world := GameProbe.new()
	root.add_child(world)
	var target := Node2D.new()
	world.add_child(target)
	var kinds: Array[String] = EnemyCatalog.CLASS_ORDER.filter(func(kind):return not EnemyCatalog.is_human(kind)) # Human anatomy has its own regression.
	kinds.append("boss")
	for kind in kinds:
		var flying := AirEnemyCatalog.is_air(kind)
		var path := "res://scenes/boss_enemy.tscn" if kind=="boss" else ("res://scenes/air_enemy.tscn" if flying else "res://scenes/enemy.tscn")
		var machine = load(path).instantiate()
		machine.kind = "siege" if kind=="boss" else kind
		machine.position = Vector2(600,120 if flying else 430)
		world.add_child(machine)
		machine.set_physics_process(false)
		machine.set_process(false)
		var motion = machine.motion
		motion.set_process(false)
		check(motion.identity==kind and motion.state=="deploy",kind+" creates its own deployment")
		var spawn_position: Vector2 = machine.position
		machine.position.x = 20000
		motion._process(0.5)
		check(motion.elapsed==0.0,kind+" deployment waits until the offscreen spawn reaches the camera")
		machine.position = spawn_position
		var signatures := {}
		for action in Pose.STATES:
			var mid := Pose.sample(action,0.4,kind,flying)
			var signature := str(mid)
			check(not signatures.has(signature),kind+" distinct authored pose for "+action)
			signatures[signature] = true
			for endpoint in [0.0,1.0]:
				if action=="destroy": continue
				var sample := Pose.sample(action,endpoint,kind,flying)
				check(Vector2(sample.offset).length()<0.0001 and absf(sample.roll)<0.0001,kind+" "+action+" has continuous body endpoints")
		if not flying:
			motion.pose = Pose.sample("deploy",0.5,kind,false)
			var weather_feet := ActorWeatherGeometry.feet(machine)
			for index in weather_feet.size():
				check(weather_feet[index].distance_to(machine.legs_part.to_global(machine.leg_foot(index)))<0.01,kind+" weather contact follows the deployed foot")
			motion.pose = Pose.sample("deploy",0,kind,false)
		var before_position: Vector2 = machine.position
		var before_damage: float = float(machine.profile.damage)
		finish_action(motion)
		machine.target = target
		motion.advance(0.01)
		check(motion.state=="scan",kind+" acquires a changed combat target")
		finish_action(motion)
		if flying: machine.flight_velocity = Vector2(50,0)
		else:
			machine.moving = true
			machine.locomotion_speed = 50
		motion.advance(0.01)
		if flying: machine.flight_velocity = Vector2.ZERO
		else:
			machine.moving = false
			machine.locomotion_speed = 0
		motion.advance(0.01)
		check(motion.state=="stabilize",kind+" reacts to actual deceleration")
		machine.hp -= 1
		motion.advance(0.01)
		check(motion.state=="impact",kind+" damage interrupts with articulated recovery")
		finish_action(motion)
		machine.attack_count = 1
		motion.advance(0.01)
		check(motion.state=="service",kind+" services after a completed shot or volley")
		finish_action(motion)
		machine.attack_count = 3
		motion.advance(0.01)
		for pending in 3:
			if motion.state=="purge": break
			finish_action(motion)
		check(motion.state=="purge",kind+" vents after repeated attacks without service starvation")
		check(machine.position==before_position and float(machine.profile.damage)==before_damage,kind+" performances preserve simulation position and damage")
		# Freeze the actor just as NetworkWorld does. Its visual child keeps time.
		motion.automatic = false
		motion.play("scan",true)
		motion.set_process(true)
		var before_time: float = motion.elapsed
		for frame in 4: await process_frame
		check(motion.elapsed>before_time,kind+" child animates beneath a frozen network parent")
		paused = true
		before_time = motion.elapsed
		for frame in 3: await process_frame
		check(is_equal_approx(before_time,motion.elapsed),kind+" presentation honors the game pause")
		paused = false
		machine.game = world
		world.weather.reduced_effects = true
		before_time = motion.elapsed
		for frame in 4: await process_frame
		check(motion.elapsed>before_time,kind+" F3 reduces redraws without freezing animation")
		world.weather.reduced_effects = false
		machine.game = null
		motion.set_process(false)
		machine.windup = float(machine.profile.windup)*0.5
		machine.weapon_recoil = 3.0
		var final_windup: float = machine.windup
		var wreck_count := get_nodes_in_group("enemy_motion_wrecks").size()
		machine.die()
		machine.die()
		check(not machine.is_in_group("enemies") and machine.collision_layer==0,kind+" retires combat immediately at death")
		check(get_nodes_in_group("enemy_motion_wrecks").size()==wreck_count+1,kind+" creates exactly one detached articulated destruction")
		await process_frame
		check(not is_instance_valid(machine),kind+" original node frees immediately without extending kill time")
		for wreck in get_nodes_in_group("enemy_motion_wrecks"):
			check(wreck.get_child_count()>=3 and is_equal_approx(wreck.artist.windup,final_windup) and is_equal_approx(wreck.artist.weapon_recoil,3.0),kind+" wreck retains its full rig and the exact interrupted weapon pose")
			wreck.queue_free()
		await process_frame
		print("PASS ",kind,": seven additional states, combat triggers, replication freeze, pause, F3 and death")
	for index in 25:
		var casualty = load("res://scenes/enemy.tscn").instantiate()
		world.add_child(casualty)
		casualty.set_physics_process(false)
		casualty.die()
	var active_wrecks := 0
	for wreck in get_nodes_in_group("enemy_motion_wrecks"):
		if not wreck.is_queued_for_deletion(): active_wrecks += 1
	check(active_wrecks==20,"A simultaneous 25-enemy blast obeys the 20-wreck budget before deferred cleanup")
	await process_frame
	check(get_nodes_in_group("enemy_motion_wrecks").size()==20,"Deferred cleanup retains exactly the newest 20 wrecks")
	check(await Cleanup.free_scene(world,self),"All visual delegates and original scenes free cleanly")
	print("ENEMY MOTION: %d/%d checks passed" % [checks-failures,checks])
	quit(0 if failures==0 else 1)
