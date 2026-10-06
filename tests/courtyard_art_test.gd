extends SceneTree
## Exercise real scene integration: cosmetics stay outside every bunker, retain
## physical contact planes, survive gate destruction and add no update loops.
const MAIN = preload("res://scenes/main.tscn")
const CLEANUP = preload("res://tests/scene_cleanup.gd")
const ART = preload("res://scripts/courtyard_art.gd")
const CATALOG = preload("res://scripts/courtyard_art_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func verify_court(game: Node2D, expected_fronts: int,label: String) -> void:
	var courts: Array[Node] = game.perimeter.find_children("ServiceCourtyard","Node2D",false,false)
	check(courts.size() == 1,label + ": one courtyard exists")
	if courts.size() != 1: return
	var courtyard: Node2D = courts[0]
	check(courtyard.get_script() == ART,label + ": courtyard uses the generated modules")
	check(courtyard.sections.size() == expected_fronts and courtyard.lamps.size() == expected_fronts,label + ": active fronts receive matching service courts")
	var positioned := true
	for section: Dictionary in courtyard.sections:
		var edge: float = game.perimeter.layout.bunker_right if int(section.side) > 0 else game.perimeter.layout.bunker_left
		positioned = positioned and is_equal_approx(float(section.edge),edge) and is_equal_approx(float(section.ground),game.perimeter.layout.ground_y)
		positioned = positioned and float(section.end) > float(section.start)
		positioned = positioned and (is_equal_approx(float(section.start),edge) if int(section.side) > 0 else is_equal_approx(float(section.end),edge))
		for fence in game.perimeter.sites:
			if fence.role == "fence" and fence.side == int(section.side):
				positioned = positioned and is_equal_approx(float(section.front),fence.position.x)
	check(positioned,label + ": pavement and rear mesh remain outside the actual bunker and on its physical floor")
	var ends_join := true
	for section: Dictionary in courtyard.sections:
		var near_gate: float = float(section.end) if int(section.side) > 0 else float(section.start)
		ends_join = ends_join and is_equal_approx(absf(near_gate - float(section.front)),13.0)
	check(ends_join,label + ": continuous rear fence joins the bunker and overlaps the outer gate heel without open end gaps")
	var lamps_correct := true
	for lamp: Sprite2D in courtyard.lamps:
		lamps_correct = lamps_correct and lamp.texture == CATALOG.ATLAS and lamp.material == ART.lamp_material()
		lamps_correct = lamps_correct and is_equal_approx(lamp.position.y + lamp.region_rect.size.y * lamp.scale.y,game.perimeter.layout.ground_y)
	check(lamps_correct,label + ": lamp feet stay on ground and share the GPU animation material")
	check(courtyard.find_children("*","CollisionObject2D",true,false).is_empty() and not courtyard.is_processing() and not courtyard.is_physics_processing(),label + ": courtyard adds no collision bodies or per-frame loops")
	check(courtyard.z_index < 0 and courtyard.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,label + ": rear mesh remains behind figures with sharp texture sampling")
	var before: Array = courtyard.sections.duplicate(true)
	var lamp_ids: Array[int] = []
	for lamp in courtyard.lamps: lamp_ids.append(lamp.get_instance_id())
	for fence in game.perimeter.sites:
		if fence.role != "fence": continue
		fence.set_physics_process(false)
		fence.gate_amount = .5
		fence.sync_replica()
		fence.take_damage(9999)
	check(courtyard.sections == before and courtyard.lamps.size() == lamp_ids.size(),label + ": opening and destruction preserve the court and its fixed coordinates")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var atlas_image := CATALOG.ATLAS.get_image()
	check(atlas_image != null and atlas_image.get_size() == Vector2i(1254,1254),"the generated atlas loads at its unchanged source size")
	if atlas_image != null:
		check(atlas_image.get_pixel(0,0).a == 0.0,"atlas background is transparent")
		check(atlas_image.get_pixel(949,236).a < .1,"large torn mesh opening remains transparent")
	for environment in ScenarioCatalog.environments(true):
		for placement in ["left","center","right"]:
			var game := MAIN.instantiate() as Node2D
			root.add_child(game)
			game.start_scenario(1,{"environment":str(environment.id),"position":placement,"build_type":"bastion"})
			game.rounds.running = false
			verify_court(game,2 if placement == "center" else 1,str(environment.id) + "/" + placement)
			check(await CLEANUP.free_scene(game,self),"scenario releases its courtyard")
	var classic := MAIN.instantiate() as Node2D
	root.add_child(classic)
	classic.start(1)
	classic.rounds.running = false
	verify_court(classic,1,"classic")
	check(await CLEANUP.free_scene(classic,self),"classic releases its courtyard")
	print("Courtyard art: %d/%d checks passed" % [checks - failures,checks])
	quit(1 if failures else 0)
