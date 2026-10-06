extends SceneTree
## Visual fixture, not a playthrough or a gameplay regression test.
## Record: godot --path . --fixed-fps 30 --disable-vsync --write-movie artifacts/worlds-v2/worlds-preview.avi --script tests/world_style_gallery.gd -- --no-profile-save
const OUTPUT := "res://artifacts/worlds-v2/"
const FRAMES_PER_WORLD := 120
var game: Node2D
var entries: Array = []
var captions: CanvasLayer

class Caption extends Node2D:
	var world_title := ""
	var world_number := 0
	func _draw() -> void:
		draw_rect(Rect2(866,752,550,119),Color("101c21"))
		draw_rect(Rect2(866,752,3,119),Color("c3925d"))
		Art.text(self,Vector2(885,779),"VISUELLE PRÜFSZENE  ·  %02d / 08"%world_number,14,Color("b7c7c7"))
		Art.text(self,Vector2(885,810),world_title.to_upper(),23,Color("f0e7ce"))
		Art.text(self,Vector2(885,835),"Bastion am Westrand · Wellen angehalten",14,Color("b7c7c7"))
		Art.text(self,Vector2(885,856),"Echte Spielszene · Atmosphäre in Bewegung",13,Color("889d9e"))

class Overview extends Node2D:
	var entries: Array = []
	var textures: Array[Texture2D] = []
	var runtime := false
	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,2040 if runtime else 1280),Color("0d181e"))
		Art.text(self,Vector2(24,40),"LETZTE SCHICHT / ACHT WELTEN",28,Color("eee5cf"))
		Art.text(self,Vector2(24,66),"Vorbereitete Spielszenen · Bastion links · Wellen angehalten" if runtime else "Vollständige Imagegen-Panoramen · Originaldateien ohne Nachbearbeitung",15,Color("9cafb0"))
		for index in entries.size():
			var origin := Vector2(24+(index%2)*708,102+floori(index/2.0)*(478 if runtime else 284))
			var dimensions := Vector2(684,427.5) if runtime else Vector2(684,228)
			draw_texture_rect(textures[index],Rect2(origin,dimensions),false)
			Art.text(self,origin+Vector2(0,dimensions.y+26),"%02d  %s"%[index+1,str(entries[index].title).to_upper()],18,Color("eee5cf"))

func _initialize() -> void:
	call_deferred("run")

func _make_scene(entry: Dictionary, index: int) -> void:
	if is_instance_valid(game):
		root.remove_child(game)
		game.queue_free()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":entry.id,"build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	game.rounds.running = false
	game.rounds.phase = "build"
	game.notice = ""
	game.notice_time = 0
	game.camera.position = game.camera_target_center
	game.camera.zoom = Vector2.ONE*game.camera_target_zoom
	game.weather.set_reduced_effects(false)
	var caption := captions.get_child(0) as Caption
	caption.world_title = str(entry.title)
	caption.world_number = index+1
	caption.queue_redraw()

func _save_overview(runtime: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440,2040 if runtime else 1280)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var overview := Overview.new()
	overview.entries = entries
	overview.runtime = runtime
	for entry: Dictionary in entries:
		if runtime:
			overview.textures.append(ImageTexture.create_from_image(Image.load_from_file(OUTPUT+str(entry.id)+".png")))
		else:
			overview.textures.append(ScenarioCatalog.texture(str(entry.path)))
	viewport.add_child(overview)
	root.add_child(viewport)
	await RenderingServer.frame_post_draw
	var path := OUTPUT+("runtime-overview.png" if runtime else "panorama-overview.png")
	assert(viewport.get_texture().get_image().save_png(path)==OK,"Could not save overview")
	viewport.queue_free()
	print("WORLD STYLE CAPTURE "+path)

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("World style gallery requires a graphical renderer")
		quit(1)
		return
	root.size = Vector2i(1440,900)
	ThemeDB.fallback_font = load("res://assets/mono.ttf")
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for entry: Dictionary in ScenarioCatalog.environments():
		if str(entry.id)!="sector07": entries.append(entry)
	assert(entries.size()==8,"Expected eight new world panoramas")
	captions = CanvasLayer.new()
	captions.layer = 100
	captions.add_child(Caption.new())
	root.add_child(captions)
	for index in entries.size():
		_make_scene(entries[index],index)
		for frame in FRAMES_PER_WORLD:
			await RenderingServer.frame_post_draw
			if frame==60:
				var path := OUTPUT+str(entries[index].id)+".png"
				assert(root.get_texture().get_image().save_png(path)==OK,"Could not save runtime image")
				print("WORLD STYLE CAPTURE "+path)
			await process_frame
	await _save_overview(false)
	await _save_overview(true)
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	captions.queue_free()
	print("WORLD STYLE GALLERY: 8 arranged actual scenes, 120 frames each; waves disabled, original shaders, normal camera")
	quit()
