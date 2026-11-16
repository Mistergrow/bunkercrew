extends SceneTree
## Pass 3 machine presentation: vehicle suspension on the texel grid, the
## whole-machine hit flash, stepped rotor keys, living infantry attitudes,
## enemy-drop reveals, surface marks, the mixer's working cues and the wave
## alarm beacons. Everything is presentation derived from replicated state.
const VehicleArt := preload("res://scripts/ground_vehicle_art.gd")
const AircraftArt := preload("res://scripts/aircraft_art.gd")
const InfantryArt := preload("res://scripts/ground_infantry_art.gd")
const Marks := preload("res://scripts/impact_marks.gd")
const Alarm := preload("res://scripts/bunker_alarm.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
class WeatherProbe extends RefCounted:
	var reduced_effects := false
class RoundsProbe extends Node:
	var phase := "build"
class GameProbe extends Node2D:
	var weather := WeatherProbe.new()
	var rounds := RoundsProbe.new()
	var impacts := 0
	func impact(_at: Vector2, _material: String, _normal: Vector2 = Vector2.LEFT, _power: float = 1.0) -> void: impacts += 1
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func run() -> void:
	var game := GameProbe.new()
	root.add_child(game)
	game.add_child(game.rounds)
	await _vehicles(game)
	await _hit_flash(game)
	_rotors()
	_infantry_steps()
	await _marks(game)
	await _alarm(game)
	await _mixer()
	check(await Cleanup.free_scene(game,self), "Probe scene frees cleanly")
	print("MACHINE PRESENTATION: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)

func _vehicles(game: Node2D) -> void:
	var target := Node2D.new()
	game.add_child(target)
	for kind: String in EnemyCatalog.VEHICLE_CLASSES:
		var machine: SiegeMachine = load("res://scenes/enemy.tscn").instantiate()
		machine.kind = kind
		machine.game = game
		machine.position = Vector2(700, 430)
		game.add_child(machine)
		freeze(machine)
		machine.target = target
		target.global_position = machine.global_position+Vector2(-340,-15)
		machine.motion.pose = {}
		machine.moving = true
		machine.locomotion_speed = machine.move_speed
		var seen_heave := {}
		var seen_nose := {}
		var whole := true
		var upright := true
		for step in 80:
			machine.position.x -= 1.7
			machine._pose_parts()
			var ride := VehicleArt.suspension(machine)
			seen_heave[ride.x] = true
			seen_nose[ride.y] = true
			var offset: Vector2 = machine.body_part.position+Vector2(0,machine.body_height)
			var texel_ok := is_equal_approx(offset.x,roundf(offset.x)) and is_equal_approx(offset.y,roundf(offset.y))
			whole = whole and texel_ok
			upright = upright and machine.body_part.rotation == 0.0
		check(upright, kind+" hull never turns as a resampled quad while driving")
		check(whole, kind+" hull heave and recoil land on whole texels")
		check(seen_heave.size() >= 2 and seen_nose.size() >= 2, kind+" road bumps heave and pitch the hull while it drives")
		var max_nose := 0
		for nose: int in seen_nose: max_nose = maxi(max_nose,absi(nose))
		check(max_nose <= VehicleArt.MAX_NOSE, kind+" pitch stays within the authored texel range")
		var half := absf(Rect2(VehicleArt.RECTS[kind]).position.x)
		check(VehicleArt.shear(1,-half,half) == 1 and VehicleArt.shear(1,half,half) == -1 and VehicleArt.shear(1,0.0,half) == 0, kind+" pitch shears the nose and tail columns in opposite whole texels")
		machine.moving = false
		machine.locomotion_speed = 0.0
		machine.weapon_recoil = 0.0
		machine.hit_flash = 0.0
		var rest := VehicleArt.suspension(machine)
		machine.position.x -= 13.0
		check(rest == Vector2i.ZERO and VehicleArt.suspension(machine) == Vector2i.ZERO, kind+" a parked hull sits level wherever it stands")
		machine.locomotion_speed = machine.move_speed*.8
		check(VehicleArt.suspension(machine).y > 0, kind+" braking dips the nose")
		machine.free()
	target.free()

func _hit_flash(game: Node2D) -> void:
	var machine: SiegeMachine = load("res://scenes/enemy.tscn").instantiate()
	machine.kind = "runner"
	machine.game = game
	machine.position = Vector2(500, 430)
	game.add_child(machine)
	freeze(machine)
	machine.hit_flash = .2
	machine._pose_parts()
	var same := machine.body_part.modulate == machine.legs_part.modulate and machine.legs_part.modulate == machine.weapon_part.modulate
	check(same and machine.body_part.modulate.r > 1.3, "A fresh hit brightens hull, limbs and weapon together")
	var rim: Variant = machine.legs_part.get_instance_shader_parameter(&"struck")
	check(rim == null or (rim as Color).a == 0.0, "Limb plates no longer turn into a pale silhouette rim")
	machine.hit_flash = .1
	machine._pose_parts()
	check(machine.legs_part.modulate == SiegeMachine.FLASH_WARM, "The flash steps down once")
	machine.hit_flash = 0.0
	machine._pose_parts()
	check(machine.body_part.modulate == Color.WHITE, "The flash ends with the hit timer")
	game.weather.reduced_effects = true
	machine.hit_flash = .2
	machine._pose_parts()
	check(machine.body_part.modulate == SiegeMachine.FLASH_WARM, "Reduced effects keep only the gentle step")
	game.weather.reduced_effects = false
	machine.free()

func _rotors() -> void:
	var keys := {}
	for frame in 30: keys[AircraftArt._smear_key(frame/60.0,0,false)] = true
	check(keys.size() == AircraftArt.SMEAR_KEYS.size(), "Rotor blades cycle through every authored smear key")
	check(AircraftArt._smear_key(1.37,0,true) == 0 and AircraftArt._smear_key(.2,1,true) == 0, "Reduced effects hold one still blade")
	var changes := 0
	var previous := AircraftArt._smear_key(0.0,0,false)
	for frame in 60:
		var key := AircraftArt._smear_key(frame/60.0,0,false)
		if key != previous: changes += 1
		previous = key
	check(changes <= int(AircraftArt.SMEAR_FPS)+1, "Smear keys step at their own rate, not every display frame")

func _infantry_steps() -> void:
	var step := TAU/InfantryArt.LIVING_PER_TURN
	check(InfantryArt.living_step(0.0,0) == 0 and InfantryArt.living_step(step*2.1,0) == 2, "Living attitudes snap to the nearest authored key")
	check(InfantryArt.living_step(step*1.6,1) == 1 and InfantryArt.living_step(step*.4,1) == 1, "A remembered key holds across a small rock over the boundary")
	check(InfantryArt.living_step(step*12.0,0) == InfantryArt.LIVING_STEPS[-1] and InfantryArt.living_step(-step*9.0,0) == InfantryArt.LIVING_STEPS[0], "Extreme leans clamp to the baked range")
	check(InfantryArt.living_texture() != null, "The living attitude atlas is imported")

func _marks(game: Node2D) -> void:
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(20,80)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector2(300,300)
	game.add_child(wall)
	await physics_frame
	await physics_frame
	var face := ImpactBurst.new()
	face.position = Vector2(310,300)
	face.surface_material = "concrete"
	face.direction = Vector2.RIGHT
	game.add_child(face)
	var marks: Node2D = game.get_meta(Marks.META) if game.has_meta(Marks.META) else null
	check(is_instance_valid(marks) and marks.marks_made == 1, "A round on a static surface leaves a mark")
	var air := ImpactBurst.new()
	air.position = Vector2(600,120)
	air.surface_material = "metal"
	air.direction = Vector2.LEFT
	game.add_child(air)
	check(is_instance_valid(marks) and marks.marks_made == 1, "A burst in open air leaves no mark")
	wall.position.x += 4.0
	marks._process(.1)
	var live := 0
	for index in Marks.MAX_MARKS: if marks._state[index].x >= 0.0: live += 1
	check(live == 0, "A mark goes with the surface when it moves or is destroyed")
	face.retire()
	air.retire()
	wall.free()

func _alarm(game: Node2D) -> void:
	var alarm: Node2D = Alarm.create(game)
	game.add_child(alarm)
	alarm._process(.1)
	check(not alarm.active, "Beacons are dark during the build pause")
	game.rounds.phase = "warning"
	alarm._process(.1)
	check(alarm.active and alarm._key >= 0, "A wave warning starts the beacons turning")
	var keys := {}
	for frame in 120:
		alarm._process(1.0/60.0)
		keys[alarm._key] = true
	check(keys.size() == Alarm.ROTATION_KEYS, "The reflector steps through every authored key")
	check(1.0/Alarm.TURN_SECONDS < 3.0, "The bright face passes the viewer fewer than three times a second")
	game.weather.reduced_effects = true
	alarm._process(.1)
	check(alarm.active and alarm._key == -1, "Reduced effects keep a steady lit dome")
	game.weather.reduced_effects = false
	game.rounds.phase = "attack"
	alarm._process(.1)
	check(alarm.active, "The beacons keep turning into the attack")
	alarm._process(Alarm.ATTACK_HOLD)
	check(not alarm.active, "and stop a few seconds after it began")
	alarm.free()

func _mixer() -> void:
	var station := ProductionStation.new()
	root.add_child(station)
	station.set_process(false)
	var animation: Node = station.get_node("MixerAnimation")
	animation.set_process(false)
	check(station.label_keepout().has_area(), "The mixer names its drum mouth for name tags to clear")
	station.input_amount = station.input_cost("sand")
	station._process(0.0)
	for frame in 90:
		station._process(1.0/60.0)
		animation.advance_visual(1.0/60.0)
	check(animation.fill > .9, "A working mixer fills its mouth with concrete")
	check(animation._lamp_step in [1,2], "The motor lamp shows the batch running")
	var pulses := {}
	for frame in 120:
		station._process(1.0/60.0)
		animation.advance_visual(1.0/60.0)
		pulses[animation._lamp_step] = true
	check(pulses.size() == 2, "The working lamp steps between two levels, never off")
	station.free()
