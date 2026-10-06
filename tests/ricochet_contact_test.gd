extends SceneTree
## Actual swept bullets and barrel-obstruction contacts; no synthetic hit point.
const Spatial := preload("res://scripts/spatial_sound.gd")
const Vehicle := preload("res://scripts/convoy_vehicle.gd")

class World extends Node2D:
	var combat_gore: Node
	var network: Node
	var scenery: Node
	var upgrades: Node
	var campaign: Node
	var audio: Node
	var sounds: Array[Dictionary] = []
	var impacts: Array[Dictionary] = []
	var flashes: Array[Dictionary] = []
	func sound_at(kind: String, at: Vector2) -> void:
		sounds.append({"kind":kind, "at":at})
	func impact(at: Vector2, surface: String, normal: Vector2, strength: float) -> void:
		impacts.append({"at":at, "surface":surface, "normal":normal, "strength":strength})
	func fx(at: Vector2, color: Color, count: int) -> void:
		flashes.append({"at":at, "color":color, "count":count})

class LegacyWorld extends Node:
	var sounds: Array[String] = []
	func sound(kind: String) -> void:
		sounds.append(kind)

class Surface extends StaticBody2D:
	var surface := "metal"
	var hp := 100.0
	func impact_material() -> String:
		return surface
	func take_damage(amount: float) -> void:
		hp -= amount

class SpecialSurface extends Surface:
	var cue := "impact_core"
	func impact_sound() -> String:
		return cue

var checks := 0
var failures := 0
var contacts: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func shape(body: StaticBody2D, at: Vector2, angle: float, layer: int = 2) -> void:
	body.position = at
	body.rotation = angle
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20, 150)
	collision.shape = rectangle
	body.add_child(collision)

func kinds(world: World) -> Array[String]:
	var result: Array[String] = []
	for sound: Dictionary in world.sounds:
		result.append(sound.kind)
	return result

func _classifier_checks() -> void:
	var target := Surface.new()
	var glancing := Vector2(1, 0.0)
	var normal := Vector2(-0.5, -sqrt(0.75))
	for surface: String in ["metal", "concrete", "flesh", "earth", "glass", "wood", "mining_ore", "arc", "explosion"]:
		target.surface = surface
		for flavor: String in ["rifle", "shotgun", "turret", "dart", "tracer", "arcgun", "arc", "flak", "bomb", "rocket", "grenade", ""]:
			var expected := ""
			if flavor in ["rifle", "shotgun", "turret", "dart", "tracer"]:
				if surface == "metal": expected = "ricochet_metal"
				elif surface == "concrete": expected = "ricochet_stone"
			check(ImpactBurst.ricochet_for(target, normal, glancing, flavor) == expected, "%s/%s contact uses only its appropriate ballistic deflection bank" % [surface, flavor])
	target.surface = "metal"
	for invalid: Vector2 in [Vector2.ZERO, Vector2(NAN, 1), Vector2(INF, 0), Vector2(0, -INF)]:
		check(ImpactBurst.ricochet_for(target, invalid, glancing, "rifle").is_empty(), "A missing or nonfinite face normal cannot create a ricochet")
		check(ImpactBurst.ricochet_for(target, normal, invalid, "rifle").is_empty(), "A missing or nonfinite projectile direction cannot create a ricochet")
	check(ImpactBurst.ricochet_for(target, Vector2.LEFT, Vector2.RIGHT, "rifle").is_empty(), "A head-on bullet retains the ordinary material strike")
	check(ImpactBurst.ricochet_for(target, Vector2.LEFT, Vector2.LEFT, "rifle").is_empty(), "A bullet moving away from a face cannot produce a contact skid")
	check(ImpactBurst.ricochet_for(target, Vector2.UP, Vector2.RIGHT, "rifle").is_empty(), "A parallel path with no penetration does not create a false impact")
	check(ImpactBurst.ricochet_for(target, normal * 20.0, glancing * 1100.0, "rifle") == "ricochet_metal", "Incidence is independent of projectile speed and supplied normal magnitude")
	check(ImpactBurst.ricochet_for(null, normal, glancing, "rifle").is_empty(), "A missing contact surface cannot acquire a default concrete ricochet")
	var custom := SpecialSurface.new()
	custom.cue = "impact_wood"
	custom.surface = "concrete"
	check(ImpactBurst.ricochet_for(custom, normal, glancing, "rifle").is_empty(), "Wooden formwork cannot inherit the concrete ricochet from its wall collider")
	custom.cue = "impact_metal"
	check(ImpactBurst.ricochet_for(custom, normal, glancing, "rifle") == "ricochet_metal", "Exposed rebar on a concrete wall uses the metal deflection bank")
	custom.free()
	target.free()

func _contact_api_checks(world: World) -> void:
	var target := SpecialSurface.new()
	world.add_child(target)
	var point := Vector2(263.5, 91.25)
	var normal := Vector2(-0.5, -sqrt(0.75))
	ImpactBurst.contact(world, target, point, normal, Vector2.RIGHT, 0.9, "rifle")
	check(kinds(world) == ["impact_core", "ricochet_metal"], "A spatial-only world retains the dedicated core strike alongside its glancing bullet")
	check(world.sounds.all(func(sound: Dictionary) -> bool: return sound.at == point), "Both cues use the exact supplied world contact, never the collider centre")
	check(world.impacts.size() == 1 and world.impacts[0].surface == "metal", "Adding deflection audio emits one unchanged material effect")
	check(target.get_meta("gore_contact").flavor == "rifle" and target.get_meta("impact_contact_frame") == Engine.get_physics_frames(), "Precise contact metadata still reaches the receiver and gore system")
	world.sounds.clear()
	Spatial.emit(world, "ricochet_metal", Vector2(NAN, 1))
	check(world.sounds.is_empty(), "Malformed world coordinates never enter the spatial audio API")
	var legacy := LegacyWorld.new()
	root.add_child(legacy)
	ImpactBurst.contact(legacy, target, point, normal, Vector2.RIGHT, 0.9, "rifle")
	check(legacy.sounds == ["impact_core", "ricochet_metal"], "Legacy sound-only worlds receive their compatible unpositioned fallback")
	legacy.free()
	target.free()
	world.sounds.clear()
	world.impacts.clear()

func _swept_case(world: World, family: String, flavor: String, material: String, angle: float, expected: String, enemy: bool = false) -> void:
	var target := Surface.new()
	target.surface = material
	shape(target, Vector2(400, 400), angle, 4 if enemy else 2)
	world.add_child(target)
	if enemy: target.add_to_group("enemies")
	await physics_frame
	await physics_frame
	world.sounds.clear()
	world.impacts.clear()
	var shot: Node2D = null
	var expected_damage := 0.0
	match family:
		"handheld":
			var bullet := WorkerShot.new()
			bullet.game = world
			bullet.flavor = flavor
			shot = bullet
			if enemy: expected_damage = bullet.damage
		"turret":
			var bullet := BunkerProjectile.new()
			bullet.game = world
			shot = bullet
			if enemy: expected_damage = bullet.damage
		"flak":
			var bullet := FlakProjectile.new()
			bullet.game = world
			shot = bullet
			if enemy: expected_damage = bullet.damage * 0.45
		"hostile":
			var bullet := HostileAirProjectile.new()
			bullet.game = world
			bullet.flavor = flavor
			bullet.velocity = Vector2(1100, 0)
			shot = bullet
			expected_damage = bullet.damage
		_:
			check(false, "Unknown projectile fixture: " + family)
			target.free()
			return
	shot.position = Vector2(220, 400)
	world.add_child(shot)
	shot.set_physics_process(false)
	shot.call("_physics_process", 0.25)
	var emitted := kinds(world)
	var ricochets := emitted.filter(func(kind: String) -> bool: return kind.begins_with("ricochet_"))
	var label := "%s/%s against %s at %.0f degrees" % [family, flavor, material, rad_to_deg(angle)]
	check(ricochets == ([] if expected.is_empty() else [expected]), label + " selects the expected real contact audio")
	check(shot.is_queued_for_deletion() and is_equal_approx(target.hp, 100.0 - expected_damage), label + " preserves one-shot lifetime and existing damage/friendly-cover rules")
	var actual: Vector2 = shot.global_position
	check(world.sounds.size() >= 1 and world.sounds.all(func(sound: Dictionary) -> bool: return sound.at.is_equal_approx(actual)), label + " locates every cue at the swept collider face")
	check(absf(actual.y - 400.0) < 0.001 and actual.x > 350.0 and actual.x < 400.0, label + " stops on cover rather than reflecting or reaching the far side")
	check(world.impacts.size() == (2 if flavor in ["bomb", "rocket", "grenade"] else 1), label + " adds no extra visual contact or explosion")
	if family == "handheld" and flavor == "arcgun":
		check(world.impacts[0].surface == "arc", "Impulse contact retains its electric visual preset")
	if family == "hostile" and flavor == "arc":
		check(world.impacts[0].surface == "arc", "Hostile air impulse retains its existing electric contact preset")
	contacts.append({"family":family, "flavor":flavor, "material":material, "angle_degrees":rad_to_deg(angle), "sounds":emitted, "point":[actual.x, actual.y], "remaining_hp":target.hp})
	target.free()
	await process_frame

func _barrel_checks(world: World) -> void:
	var turret := RoofTurret.new()
	turret.game = world
	turret.position = Vector2(700, 400)
	world.add_child(turret)
	turret.set_physics_process(false)
	turret.aim_angle = 0.0
	var target := Surface.new()
	shape(target, turret.global_position + RoofTurret.PIVOT + Vector2(40, 0), PI / 3.0)
	world.add_child(target)
	await physics_frame
	await physics_frame
	world.sounds.clear()
	world.impacts.clear()
	var ammo := turret.ammo
	check(turret.fire() and turret.ammo == ammo - 1, "A roof barrel obstruction consumes one real round")
	check(kinds(world).count("ricochet_metal") == 1 and target.hp == 100.0, "A glancing obstruction inside the roof barrel emits one ping without friendly damage")
	var at: Vector2 = world.impacts[0].at
	check(world.sounds.filter(func(sound: Dictionary) -> bool: return sound.kind == "ricochet_metal")[0].at == at, "Roof muzzle obstruction keeps its face contact as the deflection source")
	target.free()
	turret.free()
	await process_frame
	var vehicle: Node2D = Vehicle.new()
	vehicle.game = world
	vehicle.position = Vector2(1000, 400)
	world.add_child(vehicle)
	vehicle.set_physics_process(false)
	for child: Node in vehicle.get_children():
		child.set_process(false)
		child.set_physics_process(false)
	vehicle.has_mg = true
	vehicle.ammo = 3
	vehicle.aim_angle = 0.0
	target = Surface.new()
	shape(target, vehicle.gun_origin() + Vector2(40, 0), PI / 3.0)
	world.add_child(target)
	await physics_frame
	await physics_frame
	world.sounds.clear()
	world.impacts.clear()
	check(vehicle.fire() and vehicle.ammo == 2, "A convoy MG barrel obstruction consumes one real round")
	check(kinds(world).count("ricochet_metal") == 1 and target.hp == 100.0, "A glancing obstruction inside the convoy MG barrel emits one ping without friendly damage")
	at = world.impacts[0].at
	check(world.sounds.filter(func(sound: Dictionary) -> bool: return sound.kind == "ricochet_metal")[0].at == at, "Convoy muzzle obstruction keeps its face contact as the deflection source")
	target.free()
	vehicle.queue_free()
	await process_frame

func _run() -> void:
	_classifier_checks()
	var world := World.new()
	root.add_child(world)
	_contact_api_checks(world)
	for flavor: String in ["rifle", "shotgun"]:
		for material: String in ["metal", "concrete"]:
			await _swept_case(world, "handheld", flavor, material, PI / 3.0, "ricochet_metal" if material == "metal" else "ricochet_stone")
		await _swept_case(world, "handheld", flavor, "metal", 0.0, "")
	for material: String in ["earth", "glass", "wood", "flesh"]:
		await _swept_case(world, "handheld", "rifle", material, PI / 3.0, "")
	await _swept_case(world, "handheld", "arcgun", "metal", PI / 3.0, "")
	await _swept_case(world, "handheld", "rifle", "metal", PI / 3.0, "ricochet_metal", true)
	await _swept_case(world, "turret", "turret", "metal", PI / 3.0, "ricochet_metal", true)
	await _swept_case(world, "turret", "turret", "concrete", PI / 3.0, "ricochet_stone")
	await _swept_case(world, "flak", "flak", "metal", PI / 3.0, "", true)
	for flavor: String in ["dart", "tracer", "arc", "bomb", "rocket", "grenade"]:
		await _swept_case(world, "hostile", flavor, "metal", PI / 3.0, "ricochet_metal" if flavor in ["dart", "tracer"] else "")
	await _barrel_checks(world)
	world.queue_free()
	await process_frame
	var report := {"checks":checks, "failures":failures, "contacts":contacts, "prepared_state":"Physics-server swept WorkerShot, BunkerProjectile, FlakProjectile and HostileAirProjectile against real rectangular cover at 0 or 60 degrees; sound_at-only probe records actual hit positions; real roof/convoy muzzle obstruction paths"}
	var directory := "res://artifacts/ricochet-20261005"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory + "/contact-verification.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("RICOCHET CONTACT: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
