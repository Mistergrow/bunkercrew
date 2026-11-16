extends SceneTree
## Blast families, flak presentation fuse, scorch and hostile trace pools, and
## the silhouette hit flash: presentation only, bounded, and deterministic from
## state both host and guests have.
const Feel := preload("res://scripts/combat_feel.gd")
var checks := 0
var failures := 0

class StubGame extends Node2D:
	var player_camera := Node.new()
	var impacts: Array = []
	func impact(point, kind, normal = Vector2.LEFT, strength = 1.0) -> void:
		impacts.append([point, kind, normal, strength])

class Shell extends Node2D:
	var direction := Vector2.RIGHT
	var distance_travelled := 0.0
	var retired := false
	var source: Node = null

class Aircraft extends Node2D:
	var game: Node
	var dead := false
	var profile := {"body_size": Vector2(40, 20)}
	func _ready() -> void: add_to_group("air_enemies")

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("COMBAT VFX %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failures += 1

func floor_body(parent: Node, y: float) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(4000, 40)
	shape.shape = box
	shape.position = Vector2(0, y + 20)
	body.add_child(shape)
	parent.add_child(body)

func blast(game: Node, at: Vector2, power: float, hint: String = "", reduced: bool = false) -> ImpactBurst:
	var burst := ImpactBurst.new()
	burst.surface_material = "explosion"
	burst.position = at
	burst.direction = Vector2.UP
	burst.power = power
	burst.class_hint = hint
	burst.seed_value = 311
	burst.reduced = reduced
	game.add_child(burst)
	return burst

func run() -> void:
	var game := StubGame.new()
	root.add_child(game)
	floor_body(game, 0.0)
	for frame in 3: await physics_frame
	var feel: Node2D = Feel.of(game.get_child(0) if game.get_child_count() > 0 else game)
	# Families from what is near the blast, settled within a few frames.
	var families := {}
	for spec in [["mech", Vector2(0, -30), 1.2], ["", Vector2(300, -10), 1.6], ["", Vector2(600, -10), .8], ["", Vector2(900, -900), 1.0]]:
		var burst := blast(game, spec[1], spec[2], spec[0])
		for frame in 8: await physics_frame
		families[str(spec[0]) if spec[0] != "" else str(spec[1])] = burst
	check(families["mech"].blast_class == "mech", "A named family is kept (mech)")
	check(families[str(Vector2(300, -10))].blast_class == "ground", "A strong blast on open ground is the ground family")
	check(families[str(Vector2(600, -10))].blast_class == "grenade", "A weak blast on the ground is the grenade family")
	check(families[str(Vector2(900, -900))].blast_class == "aircraft", "A blast with no ground below is the aircraft family")
	var bounded := true
	for burst: ImpactBurst in families.values():
		bounded = bounded and burst.bits.size() <= ImpactBurst.MAX_PARTICLES and burst.bits.all(func(bit): return float(bit.life) <= ImpactBurst.MAX_LIFETIME)
		bounded = bounded and burst.lifetime <= 3.0 and burst._lobe_offset.size() <= ImpactBurst.LOBES
	check(bounded, "Blast debris, lobes and lifetimes stay within the burst budgets")
	check(families[str(Vector2(300, -10))].bits.any(func(bit): return bit.has("trail")) and families[str(Vector2(900, -900))].bits.any(func(bit): return bool(bit.get("burning", false))), "Heavy debris trails smoke; aircraft debris burns")
	var quiet := blast(game, Vector2(1200, -10), 1.6, "ground", true)
	for frame in 8: await physics_frame
	check(not is_instance_valid(quiet.glow_layer) and quiet._lobe_count() <= 4 and quiet.bits.size() < families[str(Vector2(300, -10))].bits.size(), "Reduced effects: no additive layer, fewer billows and debris")
	check(game.impacts.is_empty(), "Blast presentation never raises new impact events")
	# Scorch marks: on the ground below ground blasts only, pooled and fading.
	check(is_instance_valid(feel), "The shared effect layer exists for a game with a camera rig")
	var marks := 0
	for index in Feel.MAX_SCORCH:
		if feel._scorch_state[index].x >= 0.0: marks += 1
	check(marks >= 2 and marks <= Feel.MAX_SCORCH, "Ground blasts leave scorch marks (%d) in the bounded pool" % marks)
	for index in 40: feel.scorch(Vector2(index * 200.0, 0.0), 40.0, index)
	marks = 0
	for index in Feel.MAX_SCORCH:
		if feel._scorch_state[index].x >= 0.0: marks += 1
	check(marks == Feel.MAX_SCORCH, "Forty marks reuse the fixed scorch pool")
	feel._process(Feel.SCORCH_LIFE + .1)
	marks = 0
	for index in Feel.MAX_SCORCH:
		if feel._scorch_state[index].x >= 0.0: marks += 1
	check(marks == 0, "Scorch marks fade out completely")
	# Flak presentation fuse.
	var plane := Aircraft.new()
	plane.game = game
	plane.position = Vector2(400, -300)
	game.add_child(plane)
	var shell := Shell.new()
	shell.position = Vector2(0, -290)
	game.add_child(shell)
	var before: int = feel.airbursts
	feel.track_flak(shell)
	for step in 30:
		shell.distance_travelled += 24.0
		shell.position += Vector2(24, 0)
		feel._process(1.0 / 60.0)
		if shell.has_meta(Feel.FLAK_FUSED): break
	check(shell.has_meta(Feel.FLAK_FUSED) and feel.airbursts == before + 1, "A shell passing an aircraft bursts beside it and hides its tracer")
	var near := false
	for burst in get_nodes_in_group(ImpactBurst.GROUP):
		if burst.surface_material == "flak" and burst.global_position.distance_to(plane.global_position) < 80.0: near = true
	check(near, "The airburst appears next to the aircraft it missed")
	var lone := Shell.new()
	lone.position = Vector2(0, -600)
	game.add_child(lone)
	feel.track_flak(lone)
	feel._process(1.0 / 60.0)
	var last := lone.global_position
	lone.queue_free()
	await process_frame
	feel._process(1.0 / 60.0)
	check(feel.airbursts == before + 2, "A shell that vanishes before its fuse (contact or expiry) bursts where it was last seen")
	var cleared := true
	for index in Feel.MAX_FLAK: cleared = cleared and feel._flak_id[index] == 0
	check(cleared and last.is_finite(), "Burst shells leave the bounded fuse list")
	check(game.impacts.is_empty(), "Airbursts are local presentation, not replicated impacts")
	# Hostile traces: fixed pool, gone after flight.
	for index in 50: feel.trace(Vector2(0, -50), Vector2(300 + index, -40), 2.0)
	var live := 0
	for index in Feel.MAX_TRACES:
		if feel._trace_state[index].x >= 0.0: live += 1
	check(live == Feel.MAX_TRACES, "Fifty hostile rounds share the fixed trace pool")
	feel._process(1.0)
	live = 0
	for index in Feel.MAX_TRACES:
		if feel._trace_state[index].x >= 0.0: live += 1
	check(live == 0, "Traces end once the round has arrived")
	# Silhouette hit flash.
	var part := Node2D.new()
	part.material = preload("res://scripts/actor_wet_materials.gd").get_material(true, -10000.0, false, 0.0)
	game.add_child(part)
	WeaponEffectArt.strike(part, .2)
	var rim: Variant = part.get_instance_shader_parameter(&"struck")
	check(rim is Color and is_equal_approx(rim.a, 1.0) and part.modulate.r <= 1.25, "A fresh hit sets a full silhouette rim and only a mild lift")
	WeaponEffectArt.strike(part, 0.0)
	rim = part.get_instance_shader_parameter(&"struck")
	check(rim is Color and rim.a == 0.0 and part.modulate == Color.WHITE, "The rim and lift end with the hit timer")
	game.player_camera.free()
	game.queue_free()
	await process_frame
	print("COMBAT VFX: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
