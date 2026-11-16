extends SceneTree
## Readability pass: the threat overlay's rules (which enemies get a bar,
## which off-screen threats get an edge arrow, when the overlay owns the
## enemies' status drawing), the team read hook of the actor material and the
## layering of the wind-borne ground haze behind the actors. Headless.
##   godot --headless --path . --script tests/threat_overlay_test.gd -- --no-profile-save --no-upnp
const Overlay := preload("res://scripts/threat_overlay.gd")
const WetMaterials := preload("res://scripts/actor_wet_materials.gd")
const BackdropGrade := preload("res://scripts/backdrop_grade.gd")
const Wind := preload("res://scripts/world_wind.gd")
var failures := 0
var checks := 0

class StubBunker extends Node:
	var room_left := 0.0
	var room_right := 400.0
	var ground_y := 430.0

class StubRounds extends Node:
	var phase := "attack"

class StubHud extends CanvasLayer:
	var overlay := ""
	func screen_rect() -> Rect2:
		return Rect2(0, 0, 1440, 900)

class StubGame extends Node2D:
	var started := true
	var players: Array = []
	var scenario_bunker: Node
	var rounds: Node
	var hud: CanvasLayer
	var weather: Node = null

class StubEnemy extends Node2D:
	var game: Node
	var hp := 100.0
	var max_hp := 100.0
	var kind := "strider"
	var elite := false
	var dead := false
	var attack_count := 0
	var windup := 0.0
	var visual_scale := 1.0
	var body_height := 43.0
	var profile := {"label": "STREIFER"}

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func _initialize() -> void:
	run.call_deferred()

func _enemy(game: Node, kind: String, at: Vector2) -> StubEnemy:
	var enemy := StubEnemy.new()
	enemy.game = game
	enemy.kind = kind
	enemy.position = at
	var hull := CollisionShape2D.new()
	hull.name = "MachineHitbox"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(60, 50)
	hull.shape = shape
	hull.position = Vector2(0, -25)
	enemy.add_child(hull)
	enemy.add_to_group("enemies")
	game.add_child(enemy)
	return enemy

func run() -> void:
	var game := StubGame.new()
	game.scenario_bunker = StubBunker.new()
	game.rounds = StubRounds.new()
	var hud := StubHud.new()
	game.hud = hud
	root.add_child(game)
	game.add_child(game.scenario_bunker)
	game.add_child(game.rounds)
	root.add_child(hud)
	var overlay: Control = Overlay.new()
	overlay.game = game
	overlay.hud = hud
	root.add_child(overlay)

	var far := _enemy(game, "strider", Vector2(1300, 430))
	var near := _enemy(game, "rifle_guard", Vector2(700, 430))
	var hurt := _enemy(game, "battle_tank", Vector2(1300, 430))
	hurt.hp = 40.0
	var engaged := _enemy(game, "runner", Vector2(1300, 430))
	engaged.attack_count = 1
	var other_game := StubGame.new()
	root.add_child(other_game)
	var stranger := _enemy(other_game, "strider", Vector2(700, 430))
	overlay._process(1.0)

	check(Overlay.covers(far), "The overlay owns the status drawing of its game's enemies while the HUD shows")
	check(not Overlay.covers(stranger), "Enemies of another game keep their own status drawing")
	check(not overlay._wants_bar(far, 1.0), "A healthy enemy far beyond the outer fence gets no bar")
	check(overlay._wants_bar(near, 1.0), "An enemy closing on the bunker gets a bar before any hit")
	check(overlay._wants_bar(hurt, .4), "A damaged enemy keeps its bar")
	check(overlay._wants_bar(engaged, 1.0), "An enemy that has fired keeps its bar")
	var everything := Rect2(-5000, -5000, 10000, 10000)
	var shown: Array = overlay.bar_enemies(everything)
	check(shown.size() == 3 and not far in shown, "Bars fade in for exactly the approaching, damaged and engaged enemies")
	var crowd: Array[StubEnemy] = []
	for index in 24:
		var extra := _enemy(game, "strider", Vector2(500 + index * 10, 430))
		extra.hp = 50.0
		crowd.append(extra)
	overlay._process(.2)
	overlay._process(1.0)
	check(overlay.bar_enemies(everything).size() == Overlay.MAX_BARS, "Bars are capped at %d" % Overlay.MAX_BARS)
	for extra in crowd:
		extra.remove_from_group("enemies")
		extra.queue_free()
	await process_frame
	overlay._scan = 0.0
	overlay._process(.016)

	# Off-screen threats: grouped per side and class, nearest first, capped.
	var view := Rect2(0, 0, 900, 500)
	var groups: Array = overlay.arrow_groups(view)
	var right_groups := groups.filter(func(group: Dictionary) -> bool: return group.side == "right")
	var walkers := right_groups.filter(func(group: Dictionary) -> bool: return group.kind == "mech")
	check(right_groups.size() == 2 and walkers.size() == 1 and int(walkers[0].count) == 2, "Beyond the right edge two walkers share one counted arrow and the tank has its own")
	var sides := {}
	for kind in ["rifle_guard", "strider", "battle_tank", "scout_drone"]:
		for at in [Vector2(-900, 430), Vector2(450, -900), Vector2(2400, 430)]:
			_enemy(game, kind, at)
	overlay._scan = 0.0
	overlay._process(.016)
	groups = overlay.arrow_groups(view)
	for group: Dictionary in groups: sides[group.side] = true
	check(groups.size() == Overlay.MAX_ARROWS, "Edge arrows are capped at %d" % Overlay.MAX_ARROWS)
	var ordered := true
	for index in range(1, groups.size()):
		ordered = ordered and float(groups[index - 1].distance) <= float(groups[index].distance)
	check(ordered, "The nearest threats keep their arrows")
	check(Overlay.family("rifle_guard") == "infantry" and Overlay.family("battle_tank") == "vehicle" and Overlay.family("scout_drone") == "air" and Overlay.family("colossus") == "mech", "Every enemy class maps to one of four glyphs")
	var all_classes := true
	for kind in EnemyCatalog.CLASS_ORDER: all_classes = all_classes and Overlay.GLYPHS.has(Overlay.family(kind))
	check(all_classes, "All 33 enemy classes have a glyph")
	check(overlay.in_combat(), "Arrows show while the wave attacks")
	game.rounds.phase = "build"
	check(not overlay.in_combat(), "No arrows in the build phase")
	hud.overlay = "pause"
	overlay._process(.016)
	check(not overlay.visible and Overlay.covers(near), "A menu hides the threat read without handing labels back to the world")
	hud.overlay = ""
	hud.visible = false
	overlay._process(.016)
	check(not Overlay.covers(near), "With the HUD hidden the enemies draw their own status again")

	# Team read on the shared actor material.
	var player := Node2D.new()
	player.add_to_group("players")
	root.add_child(player)
	check(WetMaterials.team_of(near) == WetMaterials.TEAM_HOSTILE and WetMaterials.team_of(player) == WetMaterials.TEAM_CREW and WetMaterials.team_of(game) == WetMaterials.TEAM_NONE, "Enemies, crew and everything else get their own team read")
	var surface := WetMaterials.get_material(true, -10000.0, false, 0.0)
	WetMaterials.set_team_night(.8)
	check(is_equal_approx(float(surface.get_shader_parameter("team_night")), .8), "The night strength reaches every pooled actor material")
	WetMaterials.set_team_night(0.0)
	var dark := BackdropGrade.haze_for({"sky_color": "#23394F"}, 1.0)
	var lit := BackdropGrade.haze_for({"sky_color": "#23394F"}, 0.0)
	check(dark.get_luminance() < lit.get_luminance(), "The night backdrop grade recedes toward the shadows instead of lifting them")

	# Wind-borne dust and snow banks lie behind the actors.
	var wind: Node2D = Wind.new()
	root.add_child(wind)
	var haze: Node2D = wind.get_node_or_null("GroundHaze")
	check(haze != null and not haze.z_as_relative and haze.z_index < 5, "Ground haze banks draw behind the enemies (z 5) and the crew")
	wind.queue_free()
	player.queue_free()
	overlay.queue_free()
	hud.queue_free()
	game.queue_free()
	other_game.queue_free()
	await process_frame
	print("THREAT OVERLAY: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
