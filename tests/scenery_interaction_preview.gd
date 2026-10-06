extends SceneTree
## Actual swept projectiles drive visible scenery reactions in a held combat
## scene. Run at --fixed-fps 30 with --write-movie and --prop-world=<id>.
const Cleanup := preload("res://tests/scene_cleanup.gd")
class Caption extends Node2D:
	var title := ""
	var status := "Wind, feste Wurzeln und fallendes Material"
	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,70),Color("101917"))
		Art.text(self,Vector2(24,28),title,21)
		Art.text(self,Vector2(24,54),status+" · vorbereitete Spielsituation",12,Color("b7c7bc"))
var game
var props
var tree_index := -1
var device_index := -1
var world := "overgrown_steelworks"
var elapsed := 0.0
var active := false
var stage := 0
var caption: Caption
var checks := 0
var failures := 0
var initial_hp := 0.0
var captured_stages: Dictionary = {}

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("PROP PREVIEW %s: %s"%["PASS" if ok else "FAIL",label])

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--prop-world="): world = argument.trim_prefix("--prop-world=")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/scenery-interactions"))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":world,"position":"left","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.set_process(false)
	game.audio.settings_path = "user://prop-preview.cfg"
	game.audio.set_music_volume(0)
	game.audio.set_sfx_volume(.65)
	game.weather.lightning_enabled = false
	game.hud.canvas.hide()
	for worker in game.players: worker.set_physics_process(false)
	for frame in 5: await physics_frame
	props = game.scenery.props_layer
	for entry in props.entries:
		if entry.position.x<850 or entry.position.x>1370: continue
		if entry.kind=="tree" and not bool(props.reactions.state_for(entry.index).get("broken",false)) and tree_index<0:
			tree_index = int(entry.index)
		elif entry.kind in ["fan","pipe","signal","windsock","ore_cart","cable","bollard","tape"] and device_index<0:
			device_index = int(entry.index)
	check(tree_index>=0,"A visible intact tree is available")
	if tree_index<0:
		await Cleanup.free_scene(game,self)
		quit(1)
		return
	initial_hp = float(props.reactions.state_for(tree_index).get("hp",0))
	game.camera.position = props.entries[tree_index].position+Vector2(90,-120)
	game.camera.zoom = Vector2.ONE*1.65
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	var overlay := CanvasLayer.new()
	caption = Caption.new()
	caption.title = {"overgrown_steelworks":"STAHLWERK / LAUB, TREFFER UND BRUCH","frozen_rail_yard":"FROSTBAHNHOF / SCHNEE AUF ÄSTEN","ash_foundry":"ASCHEWERK / BRAND UND VERKOHLTES HOLZ"}.get(world,world)
	overlay.layer = 110
	overlay.add_child(caption)
	game.add_child(overlay)
	for frame in 2: await process_frame
	active = true

func shoot(index: int,flavor: String="rifle") -> void:
	var target: Vector2 = props.reactions.target_point(index)
	var shot := preload("res://scripts/worker_projectile.gd").new()
	shot.game = game
	shot.position = target-Vector2(85,0)
	shot.direction = Vector2.RIGHT
	shot.flavor = flavor
	shot.damage = 34.0 if flavor=="arcgun" else 16.0
	shot.speed = 1100
	shot.life = .20
	game.add_child(shot)

func _process(delta: float) -> bool:
	if not active: return false
	elapsed += delta
	if stage==0 and elapsed>=2:
		shoot(tree_index)
		caption.status = "Ein Gewehrtreffer löst Material am Stamm"
		stage = 1
	elif stage==1 and elapsed>=3.5:
		check(float(props.reactions.state_for(tree_index).get("hp",0))<initial_hp,"An actual swept rifle round damages the tree")
		shoot(tree_index,"arcgun")
		caption.status = "Ein Impulstreffer entzündet das Holz"
		stage = 2
	elif stage==2 and elapsed>=5.0:
		check(bool(props.reactions.state_for(tree_index).get("burning",false)) or bool(props.reactions.state_for(tree_index).get("broken",false)),"An actual impulse round ignites or finishes the damaged tree")
		stage = 3
	elif stage>=3 and stage<=9 and elapsed>=6.0+float(stage-3)*.25:
		shoot(tree_index)
		caption.status = "Weitere Gewehrtreffer brechen den beschädigten Stamm"
		stage += 1
	elif stage==10 and elapsed>=8.8:
		check(bool(props.reactions.state_for(tree_index).get("broken",false)),"Repeated actual rounds leave a broken tree")
		if device_index>=0:
			for shot in 8: shoot(device_index)
		caption.status = "Außenrequisiten erhalten passende Trümmer"
		stage = 11
	if elapsed>=12:
		active = false
		finish.call_deferred()
	for capture_time in [1.5,2.8,4.0,4.7,6.4,8.7,11.7]:
		if elapsed>=capture_time and not captured_stages.has(capture_time):
			captured_stages[capture_time] = true
			capture.call_deferred(capture_time)
	caption.queue_redraw()
	return false

func capture(at: float) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/scenery-interactions/%s-%0.1fs.png"%[world,at])

func finish() -> void:
	if device_index>=0: check(bool(props.reactions.state_for(device_index).get("broken",false)),"Actual rounds break the nearby outdoor device")
	print("PROP PREVIEW: %s %d/%d checks passed"%[world,checks-failures,checks])
	await Cleanup.free_scene(game,self)
	quit(1 if failures else 0)
