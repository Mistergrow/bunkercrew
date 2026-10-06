extends SceneTree
## Native real-world captures. Before reconstructs only the removed local strip.
const CLEANUP:=preload("res://tests/scene_cleanup.gd")
const OUTPUT:="res://artifacts/solo-story/shadows/"
var checks:=0
var failures:=0
var view: SubViewport
var game: Node2D
var cases: Array[Dictionary]=[]

class LegacyShadow extends Node2D:
	func _draw() -> void: draw_rect(Rect2(-15,-1,34,3),Color(0,0,0,.24))

class Caption extends Node2D:
	var title: String
	var subtitle: String
	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,87),Color("101917"))
		Art.text(self,Vector2(28,34),title,23,Color("e0dfcf"))
		Art.text(self,Vector2(28,65),subtitle,15,Color("aab6ac"))

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func rendered() -> Image:
	for frame in 2: await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()

func changed_pixels(first: Image,second: Image,point: Vector2) -> int:
	var changes:=0
	var region:=Rect2i(Vector2i(point)-Vector2i(58,7),Vector2i(116,18)).intersection(Rect2i(Vector2i.ZERO,first.get_size()))
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			if first.get_pixel(x,y)!=second.get_pixel(x,y): changes+=1
	return changes

func scene_capture(spec: Dictionary,caption: Caption) -> void:
	var actor: Worker=game.players[0]
	var shadow:=actor.get_node("PixelVisual/GroundShadow")
	actor.position=spec.position
	actor.velocity=Vector2(0,20)
	actor._airborne=true
	actor.get_node("PixelVisual")._process(.2)
	shadow.set_physics_process(true)
	game.camera.position=spec.camera
	game.camera.zoom=Vector2.ONE*float(spec.zoom)
	game.camera.force_update_scroll()
	for frame in 3:
		await physics_frame
		await process_frame
	shadow.set_physics_process(false)
	check(shadow.has_support and absf(shadow.ground_point.y-float(spec.floor))<.1,spec.id+": actual scenario terrain/roof is projected")
	var projection: Vector2=shadow.get_global_transform_with_canvas()*Vector2.ZERO
	var old_projection: Vector2=actor.get_global_transform_with_canvas()*Vector2.ZERO
	check(projection.y-old_projection.y>100,spec.id+": airborne figure and ground shadow are distinct in native viewport")
	if spec.id=="roof-edge":
		check((shadow.global_transform*Vector2(shadow.left_extent,0)).x>=game.scenario_bunker.room_left-.01,"Native roof edge clips at original scenario collider boundary")
	caption.title="BUNKERCREW · "+str(spec.title)
	caption.subtitle="Echte Aschewerk-Szene · Sprungpose nahe Scheitelpunkt · %.1fx Kamera · vorher"%float(spec.zoom)
	caption.queue_redraw()
	var legacy:=LegacyShadow.new()
	actor.get_node("PixelVisual").add_child(legacy)
	shadow.hide()
	var before:=await rendered()
	check(before.save_png(OUTPUT+str(spec.id)+"-before.png")==OK,spec.id+": before capture written")
	legacy.hide()
	var absent:=await rendered()
	shadow.show()
	# Keep the subtitle constant while counting only actual scene pixels.
	var after:=await rendered()
	check(changed_pixels(after,absent,projection)>10,spec.id+": corrected shadow actually draws at ground pixels")
	check(changed_pixels(before,absent,old_projection)>10,spec.id+": reconstructed removed strip floats at actor pixels")
	check(changed_pixels(after,absent,old_projection)==0,spec.id+": corrected shadow does not float at actor feet")
	caption.subtitle="Echte Aschewerk-Szene · Sprungpose nahe Scheitelpunkt · %.1fx Kamera · nachher"%float(spec.zoom)
	caption.queue_redraw()
	after=await rendered()
	check(after.save_png(OUTPUT+str(spec.id)+"-after.png")==OK,spec.id+": after capture written")
	cases.append({"id":spec.id,"worker_position":[actor.position.x,actor.position.y],"support":[shadow.ground_point.x,shadow.ground_point.y],"shadow_pixel":[projection.x,projection.y],"legacy_pixel":[old_projection.x,old_projection.y],"zoom":spec.zoom,"left_extent":shadow.left_extent,"right_extent":shadow.right_extent,"opacity":shadow.opacity})
	legacy.queue_free()
	await process_frame

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),true)
	InputSetup.install()
	LocaleText.set_locale("de",false)
	view=SubViewport.new()
	view.size=Vector2i(1440,900)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(1,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	freeze(game)
	game.hud.canvas.hide()
	# A visible native scene still carries actual scenario illumination/materials.
	var overlay:=CanvasLayer.new()
	overlay.layer=110
	var caption:=Caption.new()
	overlay.add_child(caption)
	game.add_child(overlay)
	for spec: Dictionary in [
		{"id":"terrain","title":"SCHATTEN AUF GELÄNDE","position":Vector2(1060,365),"camera":Vector2(1060,347),"floor":430,"zoom":2.5},
		{"id":"roof","title":"SCHATTEN AUF BUNKERDACH","position":Vector2(510,180),"camera":Vector2(510,162),"floor":245,"zoom":2.5},
		{"id":"roof-edge","title":"SCHATTEN AN DACHKANTE","position":Vector2(94,180),"camera":Vector2(94,162),"floor":245,"zoom":2.5},
	]: await scene_capture(spec,caption)
	check(await CLEANUP.free_scene(game,self),"Actual native main scene and audio retire cleanly")
	check(await CLEANUP.free_scene(view,self),"Native isolated viewport retires cleanly")
	var file:=FileAccess.open(OUTPUT+"native-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"prepared_state":"Actual ash_foundry main.tscn; real native rig in prepared jump-apex pose; simulation frozen and actual support helper advanced. Before restores only the removed actor-local shadow in this gallery; actual jump physics independently tested.","cases":cases},"\t"))
	file.close()
	print("WORKER GROUND SHADOW NATIVE: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
