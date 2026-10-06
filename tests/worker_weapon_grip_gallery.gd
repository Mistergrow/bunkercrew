extends SceneTree
## Native renderer fixture: actual Worker, WorkerVisual and WorkerWeapon nodes.
## Prepared frozen poses, not a progression playthrough. A private project and
## private XDG directories keep the live editor cache and player profiles intact.

const CLEANUP := preload("res://tests/scene_cleanup.gd")
const IDS := ["mara", "branko", "ivo", "nora", "levin", "selma", "oskar", "rika"]
const KINDS := ["rifle", "shotgun", "arcgun", "veteran_rifle", "breacher_shotgun", "storm_arcgun"]
const SIZE := Vector2i(2400, 800)

class UpgradeStub extends Node:
	var owned := {}
	func has_upgrade(_kind: String) -> bool: return true

class GameStub extends Node2D:
	var started := true
	var upgrades := UpgradeStub.new()
	var campaign := CampaignState.new()
	func _ready() -> void:
		add_child(upgrades)
		campaign.active = true
		campaign.expedition.epic_weapons = ["veteran_rifle", "breacher_shotgun", "storm_arcgun"]

class HandlessWeapon extends WorkerWeapon:
	var omit_hands := false
	func _draw_gripping_hands() -> void:
		if not omit_hands: super._draw_gripping_hands()

class Board extends Node2D:
	var actors: Array[Worker] = []
	var title := ""
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), Color("101a1c"))
		Art.text(self, Vector2(24, 36), "BUNKERCREW · WAFFENGRIFF · "+title, 21, Art.LIGHT)
		Art.text(self, Vector2(24, 63), "Vorbereitete echte Figuren · oben Spielgröße 1× · unten Detail 3× · eingefrorene Animation", 13, Art.MUTED)
		for column in IDS.size():
			var x := 12+column*296
			var spec := CharacterCatalog.data(IDS[column])
			var accent := Color(spec.accent)
			draw_rect(Rect2(x, 85, 284, 650), Color("1d292b"))
			draw_rect(Rect2(x, 85, 284, 3), accent)
			Art.text(self, Vector2(x+12, 120), str(spec.title), 17, accent)
			for floor_y in [236, 622]:
				draw_line(Vector2(x+12, floor_y), Vector2(x+272, floor_y), Color("647269"), 1)
			Art.text(self, Vector2(x+12, 276), "1×", 12, Art.MUTED)
			Art.text(self, Vector2(x+12, 676), "3×", 12, Art.MUTED)
		Art.text(self, Vector2(24, 769), "Originales Rendering · individuelle Charakterfarben · Griffkontakte am Waffenkörper", 14, Art.LIGHT)

var view: SubViewport
var game: GameStub
var board: Board
var checks := 0
var failures := 0
var output := "res://artifacts/weapon-grip-20261005/gallery/"
var revision := "after"

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _arguments() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--revision="): revision = arg.trim_prefix("--revision=")
	if not output.ends_with("/"): output += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _freeze(child)

func _make_board() -> void:
	InputSetup.install()
	LocaleText.set_locale("de", false)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	root.size = Vector2i(320, 200)
	view = SubViewport.new()
	view.size = SIZE
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(view)
	game = GameStub.new()
	view.add_child(game)
	board = Board.new()
	game.add_child(board)
	for column in IDS.size():
		for size_index in 2:
			var actor := Worker.new()
			actor.game = game
			actor.character_id = IDS[column]
			actor.player_id = column+1
			actor.scale = Vector2.ONE*(1 if size_index==0 else 3)
			actor.position = Vector2(164+column*296, 236 if size_index==0 else 622)
			board.add_child(actor)
			var visual := WorkerVisual.new()
			visual.name = "PixelVisual"
			actor.add_child(visual)
			var weapon := HandlessWeapon.new()
			weapon.name = "WorkerWeapon"
			actor.add_child(weapon)
			_freeze(actor)
			visual._identity.hide()
			board.actors.append(actor)

func _prepare(state: String, facing: float, kind: String="rifle", pitch: float=0.0, recoil: float=0.0) -> void:
	board.title = "%s · %s · %s · %s" % [revision.to_upper(), state.to_upper(), kind.to_upper(), "LINKS" if facing<0 else "RECHTS"]
	board.queue_redraw()
	for actor in board.actors:
		var visual := actor.get_node("PixelVisual") as WorkerVisual
		var weapon := actor.get_node("WorkerWeapon") as HandlessWeapon
		actor.facing = facing
		actor.velocity = Vector2.ZERO
		actor._airborne = false
		actor.hurt_flash = .11 if state=="flinch" else 0.0
		actor.medical.fractured = state=="fracture_walk"
		visual.crouched = state=="crouch"
		visual.ceiling_height = 58 if visual.crouched else 128
		visual.idle_clock.wait_remaining = 100
		if state in ["walk", "fracture_walk", "flinch"]: actor.velocity.x = facing*160
		if state=="jump":
			actor._airborne = true
			actor.velocity = Vector2(facing*130, -220)
		weapon.weapon_kind = kind
		weapon.aiming = true
		weapon.aim_direction = Vector2(facing*cos(pitch), sin(pitch))
		weapon.aim_point = Vector2.ZERO
		weapon.recoil = recoil
		weapon.flash = .04 if state=="fire" else 0.0
		weapon.reload_timer = weapon.reload_duration(kind)*.5 if state=="reload" else 0.0
		weapon._update_origin()
		visual._process(.2)
		visual._identity.hide()
		weapon.queue_redraw()

func _rendered() -> Image:
	for unused in 2: await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func _metadata() -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor in board.actors:
		var visual := actor.get_node("PixelVisual") as WorkerVisual
		var weapon := actor.get_node("WorkerWeapon") as WorkerWeapon
		actors.append({"character":actor.character_id, "scale":actor.scale.x, "facing":actor.facing, "pose":visual.pose_name, "locomotion":not visual.locomotion_pose.is_empty(), "fractured":actor.medical.fractured, "hurt_flash":actor.hurt_flash, "weapon":weapon.weapon_kind, "recoil":weapon.recoil, "reload_timer":weapon.reload_timer, "aim":[weapon.aim_direction.x, weapon.aim_direction.y], "origin":[weapon.global_position.x, weapon.global_position.y], "hands":str(visual.pose_skeleton.get("hands", []))})
	return {"release":ProjectSettings.get_setting("application/config/version"), "revision":revision, "renderer":RenderingServer.get_video_adapter_name(), "size":[SIZE.x, SIZE.y], "prepared_state":"Actual Worker + WorkerVisual + WorkerWeapon nodes in isolated SubViewport; pose updated once then simulation frozen; gallery is not live gameplay.", "actors":actors}

func _capture(name: String) -> void:
	var picture := await _rendered()
	check(picture.save_png(output+name+".png")==OK, name+" native image saved")
	var file := FileAccess.open(output+name+".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(_metadata(), "\t"))
	file.close()

func _run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	_arguments()
	_make_board()
	for facing in [1.0, -1.0]:
		var side := "right" if facing>0 else "left"
		for state in ["aim", "fire", "reload", "walk", "crouch", "jump", "fracture_walk", "flinch"]:
			_prepare(state, facing, "rifle", 0.0, 8.0 if state=="fire" else 0.0)
			await _capture("rifle-"+state+"-"+side)
		for kind in KINDS:
			_prepare("aim", facing, kind)
			await _capture(kind+"-aim-"+side)
	check(await CLEANUP.free_scene(view, self), "Gallery nodes retire cleanly")
	print("WORKER WEAPON GRIP GALLERY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
