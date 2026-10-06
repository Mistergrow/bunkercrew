extends SceneTree
## Native QHD UI and real one-unit cargo. Camera close-up is explicitly prepared.
const L=preload("res://scripts/locale_text.gd")
const OUTPUT="res://artifacts/medic-logistics/"
var game
var view: SubViewport
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	print("LOGISTICS UI ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures+=1
		push_error(label)
func frames(count:=4):
	for index in count: await process_frame
func capture(label: String):
	await frames()
	await RenderingServer.frame_post_draw
	var picture:=view.get_texture().get_image()
	check(picture.get_size()==Vector2i(2560,1440),label+": native QHD")
	check(picture.save_png(OUTPUT+label+".png")==OK,label+": saved")
func run():
	root.size=Vector2i(1440,900)
	root.content_scale_size=Vector2i(1440,900)
	view=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.world_2d=World2D.new()
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames()
	game.start_scenario(1,{"environment":"sector07","position":"left","build_type":"bastion"})
	game.rounds.set_process(false)
	game.upgrades.owned={"bunker_workshop":true}
	game.upgrades.points=4
	for language in ["de","en"]:
		L.set_locale(language,false)
		game.hud.overlay="upgrades"
		game.hud._apply_overlay_pause()
		await frames()
		var panel=game.hud.upgrade_panel
		panel._select("medic_logistics")
		check(panel.node_buttons.size()==10,language+": all ten real research buttons exist")
		var fits:=true
		for index in panel.node_buttons.size():
			var bounds: Rect2=panel.node_buttons[index].get_rect()
			fits=fits and Rect2(145,292,768,406).encloses(bounds)
			for other in range(index+1,panel.node_buttons.size()):
				fits=fits and not bounds.intersects(panel.node_buttons[other].get_rect())
		check(fits,language+": every branch card fits with no overlap")
		var lines: Array[String]=game.hud._wrap(game.upgrades.node_data("medic_logistics").detail,34)
		check(407+(lines.size()-1)*17<540,language+": transport description clears the purchase button")
		var labels_fit:=true
		for entry: Dictionary in UpgradeSystem.NODES:
			labels_fit=labels_fit and UiArt.FONT.get_string_size(L.text(entry.title).capitalize(),HORIZONTAL_ALIGNMENT_LEFT,-1,panel._node_title_size(entry.title)).x<=131
		check(labels_fit,language+": research titles fit their native cards")
		await capture(language+"-technology")
	game.hud.overlay=""
	game.hud._apply_overlay_pause()
	game.upgrades.purchase("medic_logistics")
	var timeout:=0.0
	while game.medic.logistics_cargo.is_empty() and timeout<20:
		await physics_frame
		timeout+=game.get_physics_process_delta_time()
	check(game.medic.logistics_cargo=="sand","Preview robot actually removed and carries one unit from the roof crate")
	paused=true
	game.camera.zoom=Vector2.ONE*2.6
	game.camera.position=game.medic.global_position+Vector2(0,-60)
	game.camera.force_update_scroll()
	for language in ["de","en"]:
		L.set_locale(language,false)
		game.medic.queue_redraw()
		await capture(language+"-cargo-detail")
	paused=false
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	view.queue_free()
	await process_frame
	print("LOGISTICS UI: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
