extends SceneTree
## Actual story UI/layout capture. Gallery states are prepared; video modes use
## real walking/held work, with any skipped cure/waves explicitly captioned.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/story-mode/"
const ObjectivePanel := preload("res://scripts/story_objective_panel.gd")
class Caption extends Control:
	var heading := ""
	var detail := ""
	func _draw() -> void:
		draw_rect(Rect2(426,705,588,34),Color(.055,.085,.079,.94))
		UiArt.centered(self,Vector2(720,719),heading,11,UiArt.AMBER)
		UiArt.centered(self,Vector2(720,734),detail,10,UiArt.MUTED)
var game
var worker
var caption: Caption
var checks := 0
var failures := 0
var mode := "gallery"
var silent := false
var captures: Array[String] = []
var capture_view: SubViewport

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("STORY PREVIEW %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 3) -> void:
	for frame in count: await physics_frame

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := capture_view.get_texture().get_image() if is_instance_valid(capture_view) else root.get_texture().get_image()
	var expected := Vector2i(2560,1440) if is_instance_valid(capture_view) else Vector2i(1440,900)
	check(picture.get_size()==expected,"%s uses native %s output" % [label,expected])
	check(picture.save_png(OUTPUT+label+".png")==OK,label+" saved")
	captures.append(label)

func create_game() -> void:
	if is_instance_valid(game): await Cleanup.free_scene(game,self)
	game = load("res://scenes/main.tscn").instantiate()
	if is_instance_valid(capture_view): capture_view.add_child(game)
	else: root.add_child(game)
	if not is_instance_valid(capture_view): current_scene = game
	game.audio.settings_path = "user://story-preview.cfg"
	if silent:
		game.audio.set_music_volume(0.0)
		game.audio.set_sfx_volume(0.0)
	else:
		game.audio.set_music_volume(.16)
		game.audio.set_sfx_volume(.55)
	for frame in 4: await process_frame

func prepare(position: String) -> void:
	await create_game()
	game.story_mode = true
	game.start_scenario(1,{"environment":"mountain_pass","position":position,"build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.audio.settings_path = "user://story-preview.cfg"
	worker = game.players[0]
	game.camera.position = game.camera_target_center
	game.camera.zoom = Vector2.ONE
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	caption = Caption.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.hud.canvas.add_child(caption)
	await frames(4)

func title(heading: String,detail: String) -> void:
	caption.heading = heading
	caption.detail = detail
	caption.queue_redraw()

func walk_to(x: float) -> bool:
	var direction := signf(x-float(worker.position.x))
	var action := "p1_right" if direction>0 else "p1_left"
	Input.action_press(action)
	var reached := false
	for frame in 600:
		await physics_frame
		if (x-float(worker.position.x))*direction<=3:
			reached = true
			break
	Input.action_release(action)
	await frames(3)
	return reached and absf(worker.position.x-x)<20

func hold_target(target: Node,predicate: Callable,limit: int = 300) -> bool:
	if not game.valid_focus(worker,target): return false
	worker.preferred_focus = target
	worker.focus = target
	Input.action_press("p1_interact")
	var result := false
	for frame in limit:
		await physics_frame
		if predicate.call():
			result = true
			break
	Input.action_release("p1_interact")
	await frames(4)
	return result

func gallery() -> void:
	await create_game()
	check(is_instance_valid(game.hud.main_menu_panel.story_button),"Actual main menu exposes the story button")
	await capture("menu-qhd")
	game.hud.main_menu_panel.story_button.pressed.emit()
	await frames(3)
	check(game.hud.story_selected and game.hud.overlay=="scenario","Actual story button opens story scenario selection")
	await capture("selection-qhd")
	for position in ["left","center","right"]:
		await prepare(position)
		game.dialogue.reset()
		game.story.set_process(false)
		var objective_panel
		for candidate in get_nodes_in_group("story_objective_panels"):
			if game.is_ancestor_of(candidate): objective_panel = candidate
		var original_state: int = game.story.wall.state
		var fits := true
		for stage in 10:
			game.story.stage = stage
			for wall_state in 5:
				game.story.wall.state = wall_state
				var objective_layout: Dictionary = objective_panel.objective_layout()
				fits = fits and " ".join(objective_layout.rows) == game.story.objective() and game.hud.screen_rect().encloses(objective_layout.rect)
		game.story.stage = 0
		game.story.wall.state = original_state
		check(fits,position+" all objective stages and wall states retain complete text in the screen-edge panel")
		title("PROLOG · %s" % position.to_upper(),"Vorbereitete Ansicht · leerer Bauplatz und endliche Betonkiste")
		await frames(3)
		await capture(position+"-prologue-qhd")
		game.story.stage = 2
		game.rounds.wave = 4
		game.rounds.phase = "build"
		game.notice = ""
		game.notice_time = 0.0
		var relay = game.story.relay
		var body: Rect2 = relay.transform*Rect2(-24,-48,48,48)
		var vice := Rect2(game.workshop.position+Vector2(-5,-52),Vector2(30,13))
		check(is_equal_approx(body.end.y,game.workshop.position.y-39) and not body.intersects(vice),position+" radio sits on the workbench without overlapping its vice")
		title("AKT II · FELDFUNK", "Vorbereitete Welle 4 · Position und Lesbarkeit im echten Bunker")
		await frames(3)
		await capture(position+"-relay-qhd")

func wall_clip() -> void:
	await prepare("left")
	title("PROLOG · DIE ERSTE MAUER","Echter Weg und gehaltenes E · Aushärtezeit später gekürzt")
	await frames(30)
	var wall = game.story.wall
	var stock
	for supply in get_nodes_in_group("supplies"):
		if supply.kind=="concrete" and supply.position.y==430: stock = supply
	check(await walk_to(wall.position.x-35),"Recorded player walks from the normal spawn to the wall")
	check(await hold_target(wall,func(): return wall.state==DefenseWall.State.FORM),"Recorded held input assembles the form")
	check(await hold_target(stock,func(): return int(worker.inventory.get("concrete",0))==2),"Recorded held input takes two finite concrete units")
	check(await hold_target(wall,func(): return wall.state==DefenseWall.State.FRESH),"Recorded held input pays and pours the concrete")
	await capture("wall-fresh")
	await frames(36)
	title("ZEITSPRUNG · BETON HÄRTET", "18 Sekunden Aushärtung für diese Demonstration gekürzt")
	wall._process(Balance.CURE_TIME)
	await frames(36)
	check(game.story.stage==1 and wall.state==DefenseWall.State.HARD,"Completed cure advances the actual story")
	await capture("wall-complete")
	await frames(60)

func relay_clip() -> void:
	await prepare("left")
	game.dialogue.reset()
	game.notice = ""
	game.notice_time = 0.0
	game.story.stage = 1
	game.rounds.wave = 4
	game.rounds.phase = "build"
	worker.inventory = {"steel":2}
	title("VORBEREITETER AKT II · WELLE 4", "Zwei Stahl im Inventar · danach echter Weg und gehaltenes E")
	await frames(45)
	var relay = game.story.relay
	check(await walk_to(relay.position.x+35),"Recorded player walks to the actual radio")
	check(await hold_target(relay,func(): return game.story.stage==3),"Recorded held input pays the actual two-steel objective")
	for frame in 12:
		await physics_frame
		if game.weather.storm_events.serial>0: break
	check(game.weather.storm_events.serial==1,"Recorded story completion triggers a real tree strike")
	await capture("relay-tree-strike")
	title("ANTENNE AKTIV · BAUM GETROFFEN", "Vorhandene Brand-, Licht- und Bruchreaktionen laufen weiter")
	await frames(120)
	await capture("relay-tree-fire")
	await frames(150)

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--story-phase="): mode = argument.trim_prefix("--story-phase=")
	silent = "--silent" in OS.get_cmdline_user_args()
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1440,900)
	root.size = Vector2i(1440,900)
	if mode=="gallery":
		# Render at physical QHD while preserving the game's expanded 16:9 UI.
		# A fixed viewport excludes asynchronous desktop titlebar resizing.
		capture_view = SubViewport.new()
		capture_view.size = Vector2i(2560,1440)
		capture_view.size_2d_override = Vector2i(1600,900)
		capture_view.size_2d_override_stretch = true
		capture_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		capture_view.world_2d = World2D.new()
		root.add_child(capture_view)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	match mode:
		"gallery": await gallery()
		"wall": await wall_clip()
		"relay": await relay_clip()
		_:
			push_error("Unknown story preview phase")
			failures += 1
	if is_instance_valid(game): await Cleanup.free_scene(game,self)
	if is_instance_valid(capture_view): capture_view.queue_free()
	print("STORY PREVIEW: %d/%d checks passed (%s); prepared states are explicitly captioned" % [checks-failures,checks,mode])
	quit(1 if failures else 0)
