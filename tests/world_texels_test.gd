extends SceneTree
## Playfield art at one texel per world unit (style bible §1, rule 1): the
## offline bakes exist for every size the game draws, match their sources and
## are drawn 1:1, and the high-density sources stay unloaded where a bake
## replaces them.

const Index := preload("res://scripts/world_texel_index.gd")
const DefenseArt := preload("res://scripts/defense_structure_art.gd")
const AircraftArt := preload("res://scripts/aircraft_art.gd")
const VehicleArt := preload("res://scripts/ground_vehicle_art.gd")
const Flybys := preload("res://scripts/convoy_air_encounter_catalog.gd")
## Hull attitude stances step by SiegeMachine.HULL_TILT_STEP (0.03 rad):
## neighbouring keys lie 17 or 18 tenths of a degree apart.
const STANCE_GAP := 18
class WeatherProbe extends RefCounted:
	var reduced_effects := false
class GameProbe extends Node2D:
	var weather := WeatherProbe.new()
	func impact(_at: Vector2, _material: String, _normal: Vector2 = Vector2.LEFT, _power: float = 1.0) -> void: pass

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	_check_index()
	_check_draw_sizes()
	_check_stances()
	_check_hull_bakes()
	_check_enemy_parts()
	await _check_hulls_drawn()
	await _check_props()
	print("WORLD TEXELS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check_index() -> void:
	var sizes: Array[Vector2] = []
	for path: String in Index.ATLASES:
		var atlas := load(path) as Texture2D
		check(atlas != null and FileAccess.file_exists(path + ".source.json"), path + " exists with its provenance")
		sizes.append(atlas.get_size() if atlas != null else Vector2.ZERO)
	var inside := true
	var exact := true
	for key: String in Index.ENTRIES:
		var entry: Array = Index.ENTRIES[key]
		var region: Rect2 = entry[1]
		inside = inside and Rect2(Vector2.ZERO, sizes[int(entry[0])]).encloses(region)
		var parts := key.split("|")
		if parts.size() == 3 and not key.begins_with("authored:"):
			# A plain bake is exactly the world size it is drawn at.
			var size := parts[2].split("x")
			exact = exact and region.size == Vector2(int(size[0]), int(size[1]))
	check(inside, "Every baked region lies inside its world-texel atlas")
	check(exact, "Every bake is exactly its world size: one texel per world unit")
	var same := true
	for path: String in Index.RESOURCES:
		var resource := load(path) as AtlasTexture
		var source: Array = Index.RESOURCES[path]
		same = same and resource != null and resource.atlas.resource_path == source[0] and resource.region == source[1]
	check(same, "Resource lookups match their .tres atlas regions (re-bake after editing a region)")

func _check_draw_sizes() -> void:
	# Every fixed draw rect of the stations, defenses and stores has its bake.
	for part: Array in [["mixer_frame", Vector2i(110, 73)], ["furnace", Vector2i(124, 111)], ["core", Vector2i(90, 100)], ["mount", Vector2i(65, 44)], ["mount", Vector2i(68, 46)], ["mixer_drum", Vector2i(74, 65)]]:
		var baked := WorldTexels.texture(MachineryArt.ATLAS.resource_path, MachineryArt.REGIONS[part[0]], part[1])
		check(baked != null and Vector2i(baked.get_size()) == part[1], "%s has its %s world-texel bake" % part)
	check(DefenseArt.console(Vector2(60, 56)) is AtlasTexture and DefenseArt.console(DefenseArt.FLAK_CONSOLE_BOUNDS.size).get_size() == DefenseArt.FLAK_CONSOLE_BOUNDS.size, "Dome and flak consoles draw their bakes")
	check(WorldTexels.resource_texture("res://assets/props/workbench.tres", Vector2i(98, 61)) != null, "The station workbench has its bake")
	check(WorldTexels.texture(SupplyArt.SOURCE, SupplyArt.REGION, Vector2i(SupplyArt.BOUNDS.size)) != null, "Supply crates draw a 58 x 38 bake")
	check(ExcavationRoomArt.rock_texture().get_size() == Vector2(480, 480), "The rock face is baked at its 480-unit repeat")
	for part: String in ["ammo_box", "press_frame", "press_ram"]:
		check(WorldTexels.authored(part) != null, part + " is baked at world density")
	check(WorldTexels.authored("ammo_box").get_size() == Vector2(18, 15), "The ammo can keeps the 18 x 15 footprint of the old box")

func _check_stances() -> void:
	# Barrels turn through baked stances: no gap over 2 degrees across the
	# right-facing aim range (left-facing mounts mirror it).
	for part: Array in [[Vector2i(95, 34), -90.0, 65.0], [Vector2i(84, 23), -90.0, 30.0]]:
		var base := WorldTexels.key(MachineryArt.ATLAS.resource_path, MachineryArt.REGIONS.barrel, part[0])
		var angles := WorldTexels._stance_angles(base)
		var covered := not angles.is_empty() and angles[0] <= int(part[1] * 10.0) and angles[angles.size() - 1] >= int(part[2] * 10.0)
		for index in range(1, angles.size()):
			covered = covered and angles[index] - angles[index - 1] <= 20
		check(covered, "Barrel %s has stances every 2 degrees over its aim range" % [part[0]])

func _check_props() -> void:
	WorldTexels.missing.clear()
	var dressing = load("res://scripts/level_dressing.gd").new()
	root.add_child(dressing)
	await process_frame
	var one_to_one := true
	for prop in get_nodes_in_group("level_props"):
		var texture: Texture2D = prop.artwork.texture
		one_to_one = one_to_one and prop.artwork.scale == Vector2.ONE and texture is AtlasTexture and (texture as AtlasTexture).atlas.resource_path.ends_with("_world.png")
		one_to_one = one_to_one and prop.artwork.position - texture.get_size() * .5 == (prop.artwork.position - texture.get_size() * .5).round()
	check(one_to_one, "Every placed prop draws its bake 1:1 on whole world units")
	check(WorldTexels.missing.is_empty(), "No prop size is drawn without a bake: %s" % [WorldTexels.missing.keys()])
	check(not ResourceLoader.has_cached("res://assets/industrial_props.png"), "The 1254 px props atlas is not loaded for baked props")
	dressing.queue_free()
	await process_frame

## Every enemy hull is baked at each size it is drawn at: aircraft (live,
## bank widths, convoy flybys), walker chassis and vehicles, normal and elite,
## with attitude stances over the live range.
func _stances_cover(source: String, region: Rect2, size: Vector2i, reach: float) -> bool:
	var angles := WorldTexels._stance_angles(WorldTexels.key(source, region, size))
	if angles.is_empty() or angles[0] > -roundi(rad_to_deg(reach) * 10.0) or angles[angles.size() - 1] < roundi(rad_to_deg(reach) * 10.0): return false
	for index in range(1, angles.size()):
		if angles[index] - angles[index - 1] > STANCE_GAP: return false
	return true

func _check_hull_bakes() -> void:
	var fixed := ["interceptor", "dive_bomber", "pulse_fighter", "patrol_plane"]
	for kind: String in AirEnemyCatalog.CLASS_ORDER:
		var profile := AirEnemyCatalog.profile(kind)
		var region: Rect2 = AircraftArtCatalog.REGIONS[kind]
		var size := AircraftArt.hull_size(profile.body_size, float(profile.scale))
		var hull := WorldTexels.level(AircraftArtCatalog.TEXTURE_PATH, region, size)
		# The level stance is trimmed to its silhouette: at most two texels less.
		var trim := size - Vector2i(hull.get_size()) if hull != null else Vector2i(-1, -1)
		check(trim.x >= 0 and trim.y >= 0 and trim.x <= 2 and trim.y <= 2, "%s hull is baked at its drawn %s" % [kind, size])
		check(_stances_cover(AircraftArtCatalog.TEXTURE_PATH, region, size, .42 if kind in fixed else .30), kind + " hull has attitude stances every tilt step over its live range")
		if kind in fixed:
			for bank: float in AircraftArt.BANK_KEYS:
				var banked := AircraftArt.hull_size(profile.body_size, float(profile.scale), bank)
				check(not WorldTexels._stance_angles(WorldTexels.key(AircraftArtCatalog.TEXTURE_PATH, region, banked)).is_empty(), "%s banks through a baked %s" % [kind, banked])
	for id: String in Flybys.ORDER:
		var spec: Dictionary = Flybys.DEFINITIONS[id]
		var body := AircraftArtCatalog.hull_size(str(spec.kind), float(spec.width))
		check(_stances_cover(AircraftArtCatalog.TEXTURE_PATH, AircraftArtCatalog.REGIONS[spec.kind], AircraftArt.hull_size(body, 1.0), float(spec.bank)), "Convoy flyby %s is baked at its width with its bank" % id)
	for kind: String in EnemyCatalog.GROUND_CLASSES:
		if EnemyCatalog.is_human(kind): continue
		var profile := EnemyCatalog.profile(kind)
		for elite in [false, true]:
			var drawn: float = float(profile.scale) * (EnemyCatalog.ELITE_SIZE_SCALE if elite else 1.0)
			if EnemyCatalog.is_vehicle(kind):
				var size := VehicleArt.hull_texels(kind, drawn)
				var hull := WorldTexels.texture(VehicleArt.HULL_PATH, VehicleArt.REGIONS[kind], size)
				check(hull != null and Vector2i(hull.get_size()) == size, "%s%s hull is baked at %s" % [kind, " (elite)" if elite else "", size])
			else:
				var region: Rect2 = SiegeMachine.BODY_REGIONS[str(profile.get("chassis", kind))]
				var size := SiegeMachine.chassis_texels(kind, profile, drawn)
				check(_stances_cover(SiegeMachine.CHASSIS_PATH, region, size, .30), "%s%s chassis is baked at %s with lean stances" % [kind, " (elite)" if elite else "", size])

## Pass 7A: the parts that were still drawn at a machine's or a human's scale
## are baked at their drawn sizes too: the infantry kit at the human factor,
## the walker cannons at every walker scale, the vehicle guns in aim stances.
func _check_enemy_parts() -> void:
	const InfantryAtlas := preload("res://scripts/infantry_art_atlas.gd")
	for path: String in [InfantryAtlas.WORLD_PATH, InfantryAtlas.LIVING_WORLD_PATH, InfantryAtlas.GUN_WORLD_PATH, InfantryAtlas.TURNS_WORLD_PATH, InfantryAtlas.LIMBS_WORLD_PATH]:
		check(InfantryAtlas.sheet(path) != null and FileAccess.file_exists(path.get_basename() + ".source.json"), path.get_file() + " is imported with its provenance")
	var limbs: Array[int] = InfantryAtlas.LimbIndex.DATA
	var limb_size := InfantryAtlas.sheet(InfantryAtlas.LIMBS_WORLD_PATH).get_size()
	var inside := limbs.size() == InfantryAtlas.LimbIndex.PER_SIDE * InfantryAtlas.ROLES.size() * 2 * 6
	for index in range(0, limbs.size(), 6):
		inside = inside and Rect2(Vector2.ZERO, limb_size).encloses(Rect2(limbs[index], limbs[index + 1], limbs[index + 2], limbs[index + 3]))
	check(inside, "Every authored limb sprite of every role and side lies in its atlas")
	for kind: String in EnemyCatalog.GROUND_CLASSES:
		if EnemyCatalog.is_human(kind) or EnemyCatalog.is_vehicle(kind) or GroundVariantVisual.has_special_weapon(kind): continue
		for elite in [false, true]:
			var machine: SiegeMachine = load("res://scenes/enemy.tscn").instantiate()
			machine.kind = kind
			machine.profile = EnemyCatalog.profile(kind)
			machine.visual_scale = float(machine.profile.scale) * (EnemyCatalog.ELITE_SIZE_SCALE if elite else 1.0)
			check(SiegeMachine.WeaponIndex.BASES.has(machine.weapon_bake_key()), "%s%s cannon keys are baked at its drawn scale" % [kind, " (elite)" if elite else ""])
			machine.free()
	for kind: String in EnemyCatalog.VEHICLE_CLASSES:
		var rect: Rect2 = VehicleArt.GUN_RECTS[kind]
		for elite in [false, true]:
			var size := Vector2i((rect.size * float(EnemyCatalog.profile(kind).scale) * (EnemyCatalog.ELITE_SIZE_SCALE if elite else 1.0)).round())
			var angles := WorldTexels._stance_angles(WorldTexels.key(VehicleArt.GUN_SOURCE, VehicleArt.gun_region(kind), size))
			var low := 69 if kind == "mortar_carrier" else -230
			var high := 774 if kind == "mortar_carrier" else 545
			var covered := not angles.is_empty() and angles[0] <= low and angles[angles.size() - 1] >= high
			for index in range(1, angles.size()):
				covered = covered and angles[index] - angles[index - 1] <= 20
			check(covered, "%s%s gun has aim stances every 2 degrees over its aim range" % [kind, " (elite)" if elite else ""])

## Live machines draw their hull bakes upright on whole world texels, and the
## graded high-density hull atlases stay unloaded.
func _check_hulls_drawn() -> void:
	WorldTexels.missing.clear()
	var game := GameProbe.new()
	root.add_child(game)
	var machines: Array[Node2D] = []
	for kind: String in EnemyCatalog.GROUND_CLASSES:
		if EnemyCatalog.is_human(kind): continue
		for elite in [false, true]:
			var machine: Node2D = load("res://scenes/enemy.tscn").instantiate()
			machine.kind = kind
			machine.elite = elite
			machine.game = game
			machine.position = Vector2(300.37 + machines.size() * 140.0, 430.61)
			game.add_child(machine)
			machines.append(machine)
	for kind: String in AirEnemyCatalog.CLASS_ORDER:
		var air: Node2D = load("res://scenes/air_enemy.tscn").instantiate()
		air.kind = kind
		air.game = game
		air.position = Vector2(300.52 + machines.size() * 140.0, 120.29)
		game.add_child(air)
		machines.append(air)
	for machine in machines:
		machine.set_physics_process(false)
		machine.rotation = 0.0
		machine.body_part.rotation = 0.045
		machine.body_part.queue_redraw()
	# Two idle frames: the parts' draw callbacks run (also headless).
	await process_frame
	await process_frame
	check(WorldTexels.missing.is_empty(), "Every live hull size has a bake: %s" % [WorldTexels.missing.keys()])
	var on_grid := true
	for machine in machines:
		# The frame itself (no rest turn): whole world texels, axis-aligned.
		var world: Transform2D = machine.body_part.get_global_transform() * WorldTexels.upright(machine.body_part)
		on_grid = on_grid and world.origin.is_equal_approx(world.origin.round()) and world.x.abs().is_equal_approx(Vector2.RIGHT) and world.y.is_equal_approx(Vector2.DOWN)
	check(on_grid, "Hull frames are upright world texels on the world grid")
	for path: String in [AircraftArtCatalog.TEXTURE_PATH, SiegeMachine.CHASSIS_PATH, VehicleArt.HULL_PATH, VehicleArt.GUN_SOURCE]:
		check(not ResourceLoader.has_cached(path), path.get_file() + " is not loaded for baked hulls")
	game.queue_free()
	await process_frame
