extends SceneTree
## Walker and infantry feet must stay on their world position while planted,
## and must not jump when the unit starts or halts. Stepping repeats the
## movement lines of SiegeMachine; only presentation is evaluated.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const STEP := 1.0/60.0
class Stage extends Node2D:
	var stats := {}
	func fx(_at: Vector2, _color: Color, _count: int = 0) -> void: pass
	func spawn_pickup(_kind: String, _amount: int, _at: Vector2) -> void: pass
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func feet(actor) -> Array[Vector2]:
	return ActorWeatherGeometry.feet(actor)

func advance(actor, walking: bool) -> void:
	actor.moving = walking
	if walking:
		actor.locomotion_speed = move_toward(actor.locomotion_speed,actor.move_speed,actor.move_speed*STEP*3.6)
		actor.position.x += actor.attack_direction*actor.locomotion_speed*STEP
		actor.gait += STEP*float(actor.profile.gait)*clampf(actor.locomotion_speed/actor.move_speed,0.3,1.0)
	else:
		actor.locomotion_speed = move_toward(actor.locomotion_speed,0,actor.move_speed*STEP*4)
		actor.gait = move_toward(actor.gait,roundf(actor.gait/PI)*PI,STEP*5)
	if "stance" in actor: actor.stance = 0.0
	actor._pose_parts()

func run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	var report: Array[String] = []
	for kind in EnemyCatalog.GROUND_CLASSES:
		if EnemyCatalog.is_vehicle(kind): continue
		for direction in [-1.0,1.0]:
			for wave in [1,20]:
				var actor = load("res://scenes/ground_infantry.tscn" if EnemyCatalog.is_human(kind) else "res://scenes/enemy.tscn").instantiate()
				actor.kind = kind
				actor.wave = wave
				actor.game = stage
				actor.attack_direction = direction
				actor.position = Vector2(900,430)
				stage.add_child(actor)
				actor.set_physics_process(false)
				actor.motion.set_process(false)
				actor.motion.pose = {}
				if "infantry" in actor: actor.infantry.set_process(false)
				for warm in 60: advance(actor,true)
				var worst_plant := 0.0
				var worst_jump := 0.0
				var worst_brake := 0.0
				var planted: Dictionary = {}
				var previous := feet(actor)
				var floor_y: float = actor.global_position.y-(4.0 if EnemyCatalog.is_human(kind) else 3.0)*float(actor.visual_scale)
				for frame in 420:
					# Walk, halt, walk again: covers steady travel, braking and restart.
					advance(actor,frame<200 or frame>=290)
					var now := feet(actor)
					for index in now.size():
						worst_jump = maxf(worst_jump,now[index].distance_to(previous[index]))
						if now[index].y>=floor_y-0.05:
							if not planted.has(index): planted[index] = now[index].x
							var drift := absf(now[index].x-float(planted[index]))
							if frame<200: worst_plant = maxf(worst_plant,drift)
							else: worst_brake = maxf(worst_brake,drift)
						else:
							planted.erase(index)
					previous = now
				report.append("%s dir=%d wave=%d plant=%.2f brake=%.2f jump=%.2f" % [kind,int(direction),wave,worst_plant,worst_brake,worst_jump])
				check(worst_plant<0.1,"%s planted feet stay on the ground (direction %d, wave %d): drift %.2f px" % [kind,int(direction),wave,worst_plant])
				# The stride shortens with the replicated speed while braking; the
				# remaining drift over that quarter second stays below one boot.
				check(worst_brake<5.5,"%s feet stay within one boot while braking and restarting (direction %d, wave %d): %.2f px" % [kind,int(direction),wave,worst_brake])
				check(worst_jump<3.5,"%s feet never pop between frames when starting or halting (direction %d, wave %d): %.2f px" % [kind,int(direction),wave,worst_jump])
				actor.free()
	for line in report: print(line)
	print("ENEMY FOOT PLANT: %d checks, %d failures" % [checks,failures])
	await Cleanup.free_scene(stage,self)
	quit(1 if failures else 0)
