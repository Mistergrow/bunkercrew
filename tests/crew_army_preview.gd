extends SceneTree
## Prepared runtime rigs at native size plus 2x character detail.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const IDS := ["mara","branko","ivo","nora","levin","selma"]
class Board extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,900),Color("111b21"))
		Art.text(self,Vector2(30,43),"CREW · EIGENE BEWEGUNGEN UND RUHEGESTEN",24,Art.LIGHT)
		for index in 6:
			var x := 25+index*235
			draw_rect(Rect2(x,65,225,365),Color("1b282d"))
			Art.text(self,Vector2(x+15,97),IDS[index].to_upper(),20,Art.LIGHT)
			Art.text(self,Vector2(x+15,122),["Kontrolliert","Standfest","Unruhig","Prüfend","Wachsam","Fürsorglich"][index],13,Art.MUTED)
			Art.text(self,Vector2(x+15,260),"GEHEN · 2×",12,Art.MUTED)
			Art.text(self,Vector2(x+15,406),"RUHEGESTE · 2×",12,Art.MUTED)
		Art.text(self,Vector2(30,470),"GEGNER · SPIELGRÖSSE · PASSENDE TREFFERFLÄCHEN",21,Art.LIGHT)
		for y in [580,720,850]: draw_line(Vector2(25,y),Vector2(1415,y),Color("526066"),1)
var actors: Array[Worker] = []
var enemies: Array[Node2D] = []
func _initialize() -> void: run.call_deferred()
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func run() -> void:
	LocaleText.set_locale("de",false)
	InputSetup.install()
	root.size = Vector2i(1440,900)
	var board := Board.new()
	root.add_child(board)
	for identity: String in IDS:
		for row in 2:
			var actor: Worker = load("res://scenes/player.tscn").instantiate()
			actor.character_id = identity
			actor.position = Vector2(135+IDS.find(identity)*235,245 if row==0 else 390)
			actor.scale = Vector2.ONE*2
			board.add_child(actor)
			freeze(actor)
			actors.append(actor)
	var kinds := ["runner","strider","breaker","assault","colossus","siege","scout_car","mortar_carrier","battle_tank","grenadier","rifle_guard","scout","heavy_gunner","marksman","combat_medic"]
	for index in kinds.size():
		var kind: String = kinds[index]
		var enemy = load("res://scenes/ground_infantry.tscn" if EnemyCatalog.is_human(kind) else "res://scenes/enemy.tscn").instantiate()
		enemy.kind = kind
		enemy.position = Vector2(95+(index%6)*230,[580,720,850][floori(index/6.0)])
		board.add_child(enemy)
		freeze(enemy)
		enemy.moving = false
		enemy.gait = .8
		enemy._pose_parts()
		enemies.append(enemy)
		var label := Label.new()
		label.text = LocaleText.text(str(enemy.profile.label))
		label.position = enemy.position+Vector2(-65,10)
		label.add_theme_font_size_override("font_size",13)
		board.add_child(label)
	for frame in 120:
		for index in actors.size():
			var actor := actors[index]
			var visual: WorkerVisual = actor.get_node("PixelVisual")
			actor._airborne = false
			actor._landing_time = 0
			actor._jump_windup = 0
			actor.velocity = Vector2(150,0) if index%2==0 else Vector2.ZERO
			visual._process(1.0/30.0)
			if index%2==1:
				visual.special_pose = Personality.gestures(actor.character_id)[0]
				visual.pose_skeleton = WorkerPoseArt.sample(visual.special_pose,clampf(frame/30.0/Personality.duration(visual.special_pose),0,1),0,Vector2(24,-13),actor.character_id)
				visual.queue_redraw()
		for enemy in enemies:
			enemy.age += 1.0/30
			enemy._pose_parts()
			enemy.body_part.queue_redraw()
			enemy.legs_part.queue_redraw()
			enemy.weapon_part.queue_redraw()
		await process_frame
		if DisplayServer.get_name()!="headless" and (frame==60 or "--video" in OS.get_cmdline_user_args()):
			await RenderingServer.frame_post_draw
			var path := "res://artifacts/crew-army.png" if "--video" not in OS.get_cmdline_user_args() else "res://artifacts/crew-motion-%03d.png"%frame
			root.get_texture().get_image().save_png(path)
	await Cleanup.free_scene(board,self)
	print("CREW ARMY PREVIEW: six character animations and fifteen compact enemy rigs rendered")
	quit()
