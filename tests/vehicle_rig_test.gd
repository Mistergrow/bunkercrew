extends SceneTree
## Grounded rolling gear, mirrored ballistic mounts, weather and detached wrecks.
const VehicleArt := preload("res://scripts/ground_vehicle_art.gd")
const Wreck := preload("res://scripts/enemy_motion_wreck.gd")
const Pose := preload("res://scripts/enemy_motion_pose.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
class Target extends Node2D:
	func attack_point() -> Vector2: return global_position
class AudioProbe extends RefCounted:
	var calls := 0
	func play_footstep(_kind,_point,_weight,_heavy,_player): calls+=1
class GameProbe extends Node2D:
	var audio := AudioProbe.new()
class SurfaceProbe extends RefCounted:
	var contacts := 0
	func contact_event(_point,_weight,_actor,_state): contacts+=1
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func run() -> void:
	var world:=Node2D.new()
	root.add_child(world)
	var target:=Target.new()
	world.add_child(target)
	var game:=GameProbe.new()
	world.add_child(game)
	var surfaces:=SurfaceProbe.new()
	for kind: String in EnemyCatalog.VEHICLE_CLASSES:
		for facing in [-1,1]:
			for rig_scale in [1.0,2.0]:
				var machine: SiegeMachine=load("res://scenes/enemy.tscn").instantiate()
				machine.kind=kind
				machine.attack_direction=facing
				machine.position=Vector2(700,430)
				machine.scale=Vector2.ONE*rig_scale
				world.add_child(machine)
				freeze(machine)
				machine.target=target
				target.global_position=machine.global_position+Vector2(facing*340,-15)
				machine.motion.pose=Pose.sample("scan",0,kind)
				machine.moving=false
				machine.locomotion_speed=0
				machine._pose_parts()
				check(machine.uses_rolling_contacts() and int(machine.profile.legs)==0,kind+" has rolling gear without hidden walking legs")
				check(Pose.PROFILES.has(kind) and Pose.PROFILES[kind]!=Pose.PROFILES.strider,kind+" has its own mechanical mass and actuator profile")
				check(not machine.motion.visible,kind+" hides generic walker sensor overlays while its motion controller remains active")
				var mouth: Vector2=machine.weapon_part.to_global(machine.weapon_muzzle())
				var axis: Vector2=(mouth-machine.weapon_part.global_position).normalized()
				var launch: Vector2=machine.abilities.launch_velocity(mouth,target.global_position).normalized() if machine.abilities.ballistic_attack() else (target.global_position-mouth).normalized()
				check(axis.dot(launch)>.9999,kind+" actual weapon mouth points along emitted projectile velocity in each facing/scale")
				check(signf(axis.x)==facing,kind+" weapon retains correct facing")
				var feet:=ActorWeatherGeometry.feet(machine)
				check(feet.size()==2,kind+" exposes two real rolling contact regions")
				for point in feet:
					check(absf(point.y+3*rig_scale*machine.visual_scale-machine.global_position.y)<.001,kind+" tire/tread contact sits on exact ground line")
				var segments:=ActorWeatherGeometry.segments(machine)
				check(segments.size()==7,kind+" weather follows hull roof and barrel instead of absent walker atlas")
				for segment in segments:
					check(Vector2(segment.from).is_finite() and Vector2(segment.to).is_finite() and Vector2(segment.normal).y<=0,kind+" exposed surface has finite upward rain normal")
				var material: ShaderMaterial=machine.body_part.material
				check(material!=null and is_equal_approx(material.get_shader_parameter("sprite_alpha_cutoff"),.5),kind+" source hull alpha haze is cut only by the body shader")
				var phase:=VehicleArt.travel(machine)
				machine.age+=17
				machine.gait+=5
				machine._pose_parts()
				check(is_equal_approx(VehicleArt.travel(machine),phase),kind+" wheels and tracks remain still when only idle time changes")
				machine.position.x+=facing*12
				check(is_equal_approx(VehicleArt.travel(machine)-phase,-12.0/machine.visual_scale),kind+" wheel phase comes from actual displacement in both directions")
				machine.moving=true
				machine.locomotion_speed=machine.move_speed
				machine._pose_parts()
				check(is_zero_approx(VehicleArt.deployment(machine)),kind+" retracts ground braces while travelling")
				for phase_index in 12:
					machine.position.x+=facing*3
					machine._pose_parts()
					for point in ActorWeatherGeometry.feet(machine):
						check(absf(point.y+3*rig_scale*machine.visual_scale-machine.global_position.y)<.001,kind+" suspension leaves tire/tread contact planted")
				machine.moving=false
				machine.locomotion_speed=0
				machine._pose_parts()
				check(is_equal_approx(VehicleArt.deployment(machine),1),kind+" braces fully settle when stopped")
				machine.game=game
				var before_contacts:=surfaces.contacts
				var before_sounds:=game.audio.calls
				machine.wetness._present_footstep(surfaces,null,feet[0],.9,{"kind":"water"})
				check(surfaces.contacts==before_contacts+1 and game.audio.calls==before_sounds,kind+" rolling contact splashes without playing a boot step")
				machine.game=null
				machine.free()
	# The negative-X decomposition bug also affected older mirrored walkers.
	for kind in ["scout_car","mortar_carrier","strider"]:
		for facing in [-1,1]:
			var machine: SiegeMachine=load("res://scenes/enemy.tscn").instantiate()
			machine.kind=kind
			machine.attack_direction=facing
			machine.position=Vector2(710,430)
			world.add_child(machine)
			freeze(machine)
			machine.target=target
			target.global_position=machine.position+Vector2(facing*340,-15)
			machine.moving=true
			machine.locomotion_speed=machine.move_speed
			machine._pose_parts()
			var hull_scale: Vector2=machine.body_part.scale
			var signs:=[]
			for part in [machine.legs_part,machine.body_part,machine.weapon_part]: signs.append(signf(part.transform.determinant()))
			var wreck:=Wreck.spawn(machine,kind,false)
			freeze(wreck)
			check(wreck.artist.body_part.scale==hull_scale,kind+" detached hull preserves authored negative-X scale")
			var stopped_phase:=VehicleArt.travel(wreck.artist)
			var stopped_deploy:=VehicleArt.deployment(wreck.artist)
			for delta in [.0,.3,.4]:
				wreck._process(delta)
				var body: Node2D=wreck.artist.body_part
				check(body.global_transform.y.normalized().dot(Vector2.DOWN)>.8,kind+" wreck roof remains above its floor in each facing")
				check(body.global_transform.x.normalized().dot(Vector2(-facing,0))>.8,kind+" wreck preserves horizontal facing throughout collapse")
				var parts: Array=[wreck.artist.legs_part,wreck.artist.body_part,wreck.artist.weapon_part]
				for index in parts.size(): check(signf(parts[index].transform.determinant())==signs[index],kind+" all detached parts preserve their reflection")
				if VehicleArt.is_vehicle(kind):
					check(is_equal_approx(VehicleArt.travel(wreck.artist),stopped_phase),kind+" wreck no longer rolls as destruction time advances")
					check(is_equal_approx(VehicleArt.deployment(wreck.artist),stopped_deploy),kind+" wreck retains interrupted support pose")
					check(absf(body.position.y-wreck.hull_offset.y)<=5.001,kind+" low chassis collapse stays within five pixels")
			wreck.free()
			machine.free()
	check(await Cleanup.free_scene(world,self),"All vehicle rigs, delegates and probes free cleanly")
	print("VEHICLE RIG: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
