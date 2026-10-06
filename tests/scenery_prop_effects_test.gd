extends SceneTree
## Actual painted Props, authoritative damage, bounded local effects and replica baseline.
const PROPS := preload("res://scripts/scenario_props.gd")
const CATALOG := preload("res://scripts/scenario_prop_catalog.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")

class Weather extends Node:
	var reduced_effects := false
	var rain_strength := 0.0
	var gust := 1.0
	func wind_strength() -> float: return gust

class Sound extends Node:
	var requests: Array[String] = []
	var source_positions: Array[Vector2] = []
	func play_sound_at(kind: String, point: Vector2) -> bool:
		requests.append(kind)
		source_positions.append(point)
		return true

class World extends Node2D:
	var weather: Node
	var audio: Node
	var network: Node = null
	var scenario_bunker: Node = null

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use --no-profile-save and an isolated XDG_DATA_HOME")
		quit(1)
		return
	root.size = Vector2i(1440, 900)
	var source_images: Dictionary = {}
	for tree_kind: String in CATALOG.TREE_PATHS:
		source_images[tree_kind] = load(CATALOG.TREE_PATHS[tree_kind]).get_image()
	for environment: String in CATALOG.PROFILES:
		var game := World.new()
		game.weather = Weather.new()
		game.audio = Sound.new()
		game.add_child(game.weather)
		game.add_child(game.audio)
		root.add_child(game)
		var props := PROPS.new()
		props.game = game
		props.environment_id = environment
		game.add_child(props)
		props.set_process(false)
		props.reactions.set_process(false)
		props.debris.set_process(false)
		props.visible_bounds = Rect2(-500, 0, 2500, 500)
		for entry: Dictionary in props.entries: entry.displayed = true
		var effects: Node2D = props.debris
		effects._process(.01)
		check(effects.burst_count == 0 and game.audio.requests.is_empty(), environment + ": authored initial ruins/fires do not replay impact bursts or sounds")
		var tree_index := -1
		for entry: Dictionary in props.entries:
			if entry.kind != "tree": continue
			if tree_index < 0: tree_index = int(entry.index)
			var opaque: bool = not entry.emit_points.is_empty()
			for source_point: Vector2 in CATALOG.canopy_points(entry.tree):
				opaque = opaque and source_images[entry.tree].get_pixelv(Vector2i(source_point)).a >= .25
			check(opaque, environment + ": shedding anchors lie on opaque source branches/crowns")
			var expected := "leaf" if entry.family == "broadleaf" else "snow" if entry.family == "conifer" and environment == "frozen_rail_yard" else "needle" if entry.family == "conifer" else "bark"
			check(effects.foliage_kind(entry) == expected, environment + ": foliage matches the actual tree; snow is exclusive to frost conifers")
			for index in entry.emit_points.size():
				var origin := props.canopy_point(entry, index)
				effects.particles.clear() # Origin coverage is separate from the bounded-pool checks below.
				effects._emit_foliage(entry, origin, false)
				check(effects.particles[-1].origin.is_equal_approx(origin), environment + ": emitted source follows this tree's wind-deformed opaque anchor")
		# Prepare a healthy tree, then use the real damage API.
		for index: int in props.reactions.states:
			var state: Dictionary = props.reactions.states[index]
			state.hp = float(props.reactions.HEALTH[props.entries[index].kind])
			state.burning = false
			state.burn_left = 0.0
			state.broken = false
			state.charred = false
		effects.reset()
		effects._process(.01)
		var tree_entry: Dictionary = props.entries[tree_index]
		var target: Vector2 = props.reactions.target_point(tree_index)
		check(props.reactions.damage_entry(tree_index, 5, "rifle", target, Vector2.RIGHT), environment + ": real tree damage accepts a contact")
		effects._process(.01)
		check(effects.burst_count == 1 and effects.particles.size() > 0 and game.audio.requests == ["impact_wood"], environment + ": one new hit emits local wood/foliage and bounded local feedback")
		check(game.audio.source_positions == [target], environment + ": local foliage feedback preserves the exact world-space damage contact")
		var burst_particles: int = effects.particles.size()
		effects._process(.01)
		check(effects.burst_count == 1 and effects.particles.size() == burst_particles and game.audio.requests.size() == 1, environment + ": unchanged serial never repeats a historical hit")
		check(props.reactions.damage_entry(tree_index, 200, "rifle", target, Vector2.RIGHT), environment + ": break is authoritative")
		effects._process(.01)
		check(effects._fall_fragments.size() == 1 and effects.fallen_geometry(tree_entry).progress < 1, environment + ": the painted upper tree survives as one finite falling fragment")
		var fragment: Dictionary = effects._fall_fragments[tree_index]
		check(fragment.mesh.texture == props._tree_by_index[tree_index].texture and fragment.mesh.mesh == props._tree_by_index[tree_index].mesh, environment + ": falling crown reuses the exact original art and mesh")
		check(float(fragment.material.get_shader_parameter("ground_y")) == props.to_global(tree_entry.position).y and float(fragment.material.get_shader_parameter("cut_local_y")) < 0, environment + ": falling art clips at the real ground and the broken trunk cut")
		var angle_before: float = fragment.pivot.rotation
		effects._process(.3)
		check(float(fragment.pivot.rotation) > angle_before and float(fragment.pivot.rotation) < PI * .5, environment + ": original crown rotates continuously around its cut")
		var positions := var_to_str(effects.particles)
		var elapsed_before: float = effects.elapsed
		var angle_paused: float = fragment.pivot.rotation
		paused = true
		effects._process(.8)
		check(effects.elapsed == elapsed_before and var_to_str(effects.particles) == positions and fragment.pivot.rotation == angle_paused, environment + ": pause freezes particles and the complete tree fall")
		paused = false
		effects._process(2.0)
		check(effects._fall_fragments.is_empty() and effects.fallen_geometry(tree_entry).progress == 1, environment + ": falling art expires and leaves a settled stump/timber wreck")
		var geometry: Dictionary = effects.fallen_geometry(tree_entry)
		check(geometry.base.y <= tree_entry.position.y - 2 and geometry.tip.y <= tree_entry.position.y - 2, environment + ": fallen timber remains above its anchored ground")
		var current: Dictionary = props.reactions.state_for(tree_index)
		current.hp = 0.0
		current.broken = true
		current.serial += 10
		var events_before: int = effects.burst_count
		var sounds_before: int = game.audio.requests.size()
		effects.sync_replica(true)
		effects._process(.01)
		check(effects.burst_count == events_before and game.audio.requests.size() == sounds_before and effects._fall_fragments.is_empty(), environment + ": first replica snapshot shows settled ruins without replaying old sounds/falls")
		# Sustained visible fires exercise particle budgets without fabricating images.
		for entry: Dictionary in props.entries:
			var state: Dictionary = props.reactions.state_for(int(entry.index))
			if not state.is_empty() and entry.kind == "tree":
				state.burning = true
				state.charred = true
				state.burn_left = 8.0
		var bounded := true
		var above_ground := true
		for tick in 40:
			effects._process(.1)
			bounded = bounded and effects.particles.size() <= effects.MAX_PARTICLES and effects._fall_fragments.size() <= effects.MAX_FALL_FRAGMENTS
			for item: Dictionary in effects.particles: above_ground = above_ground and float(item.position.y) <= float(item.ground) - 2 + .001
		check(bounded and effects.emitted > 20, environment + ": sustained fire stays inside the global particle and falling-art budgets")
		check(above_ground, environment + ": debris and embers never pass below their support ground")
		game.weather.reduced_effects = true
		effects._process(.1)
		check(effects.particles.size() <= effects.REDUCED_PARTICLES and effects._fall_fragments.is_empty(), environment + ": F3 removes expensive falls and reduces the particle pool")
		props.visible_bounds = Rect2(3000, 3000, 200, 100)
		effects._process(.1)
		var visible_emissions: int = effects.emitted
		effects._process(1.0)
		check(effects.particles.is_empty() and effects.emitted == visible_emissions, environment + ": offscreen scenery neither retains nor emits particles")
		effects.reset()
		check(effects.particles.is_empty() and effects._seen.is_empty() and effects._fall_fragments.is_empty() and effects.elapsed == 0 and effects.emitted == 0, environment + ": reset clears all local histories and bounded resources")
		check(await CLEANUP.free_scene(game, self), environment + ": effect nodes and fragment resources leave with the scene")
	print("SCENERY PROP EFFECTS: %d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
