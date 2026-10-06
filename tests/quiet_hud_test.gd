extends SceneTree
## Actual matches, frozen actors for deterministic UI states; no saved profile.
const L := preload("res://scripts/locale_text.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var view: SubViewport
var checks:=0
var failures:=0
var captures:=false
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1
	print("QUIET HUD %s: %s"%["PASS" if value else "FAIL",label])
func frames(count: int=3) -> void:
	for unused in count: await process_frame
func capture(label: String) -> void:
	if not captures: return
	if "--roof-only" in OS.get_cmdline_user_args() and label not in ["qhd-en-supply","qhd-en-medical"]: return
	await frames()
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image()
	check(image.get_size()==view.size and image.save_png("res://artifacts/quiet-hud/"+label+".png")==OK,label+" actual renderer")
	if label=="qhd-en-supply":
		var top: Vector2=view.get_final_transform()*(view.get_canvas_transform()*Vector2(720,game.scenery.panorama_rect.position.y))
		var row:=roundi(top.y)
		var sum:=0.0
		var count:=0
		for x in range(200,image.get_width()-200):
			var a:=image.get_pixel(x,row-2)
			var b:=image.get_pixel(x,row+2)
			sum+=maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
			count+=1
		var difference:=sum/maxi(1,count)
		check(row>100 and row<image.get_height()-100 and difference<.012,"Roof panorama boundary mean difference across four rows %.5f at y%d"%[difference,row])
func test_context(worker: Node,label: String) -> Dictionary:
	var detail: Dictionary=game.hud.compact_context_details(worker)
	var valid: bool=detail.lines.size()<=3 and detail.action_lines.size()<=2
	for line in detail.lines: valid=valid and UiArt.FONT.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x<=348
	for line in detail.action_lines: valid=valid and UiArt.FONT.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x<=348
	valid=valid and UiArt.FONT.get_string_size(detail.title,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x<=348
	check(valid,label+" compact title/status/controls stay within their measured bounds")
	return detail
func run() -> void:
	root.size=Vector2i(320,180)
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	captures="--capture" in OS.get_cmdline_user_args()
	if captures and DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/quiet-hud"))
	view=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(1,{"environment":"flooded_power_station","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	game.set_process(false)
	game.medic.set_physics_process(false)
	game.notice_time=0
	game.dialogue.reset()
	var worker=game.players[0]
	worker.set_physics_process(false)
	worker.focus=null
	game.player_camera.update_view(0,true)
	await frames()
	var normal_area: float=game.hud.status_bounds().get_area()+game.hud.player_bounds(0).get_area()
	check(normal_area/(1440*900)<.04,"Calm solo status occupies less than 4% of logical viewport")
	check(not game.hud.medic_status_visible() and MedicalHud.brief_status(worker).is_empty(),"Healthy idle SAN and medical supplies add no permanent panels")
	var supply=get_nodes_in_group("supplies").filter(func(node):return node.game==game)[0]
	worker.position=supply.global_position+Vector2(250,0)
	check(not UiArt.world_label_visible(supply),"Distant crate label is hidden")
	worker.position=supply.global_position+Vector2(28,0)
	check(not UiArt.world_label_visible(supply),"Nearby crates leave world art clear; the focused dock identifies the target")
	worker.position.y+=140
	check(not UiArt.world_label_visible(supply),"Crate labels do not leak between floors")
	worker.position=supply.global_position+Vector2(28,0)
	worker.focus=supply
	check(not UiArt.world_label_visible(supply),"Focused crate uses one context title instead of a duplicate world label")
	game.hud._refresh_world_labels(.2)
	check(supply.has_meta("hud_label_visible") and not supply.get_meta("hud_label_visible"),"Visibility changes refresh otherwise static crate drawing")
	worker.focus=null
	worker.position=Vector2(1070,430)
	game.player_camera.update_view(0,true)
	game.hud._refresh_world_labels(.2)
	for locale in ["de","en"]:
		L.set_locale(locale,false)
		await capture("qhd-"+locale+"-solo-calm")
		worker.position=supply.global_position+Vector2(28,0)
		worker.focus=supply
		game.player_camera.update_view(0,true)
		var detail:=test_context(worker,"Supply "+locale)
		check(str(supply.amount) in " ".join(detail.lines),"Focused stock remains readable "+locale)
		await capture("qhd-"+locale+"-supply")
		worker.focus=null
		worker.position=Vector2(1070,430)
		game.player_camera.update_view(0,true)
	game.join_coop()
	game.notice_time=0
	await frames()
	var partner=game.players[1]
	partner.set_physics_process(false)
	worker.position=Vector2(820,430)
	partner.position=Vector2(920,430)
	partner.focus=null
	worker.inventory={"steel":2,"concrete":1,"ammo":1}
	partner.inventory={"sand":4}
	game.player_camera.update_view(0,true)
	check(not game.hud.player_bounds(0).intersects(game.hud.player_bounds(1)),"Co-op status remains on separate screen edges")
	check((normal_area+game.hud.player_bounds(1).get_area())/(1440*900)<.055,"Two-player baseline uses less than 5.5% of logical viewport")
	for locale in ["de","en"]:
		L.set_locale(locale,false)
		await capture("qhd-"+locale+"-coop-cargo")
	worker.hp=23
	worker.medical.bleeding=1
	worker.medical.fractured=true
	check(not MedicalHud.brief_status(worker).is_empty(),"Bleeding/fracture restores a concise medical warning")
	game.medic.position=worker.position+Vector2(-38,0)
	game.medic.target=worker
	game.medic.treating=true
	game.medic.status_label=L.format("SAN-1 · P%d %s",[worker.player_id,L.text("Schiene")])
	check(game.hud.medic_status_visible(),"Actual treatment exposes SAN status")
	await capture("qhd-en-medical")
	game.medic.target=null
	game.medic.treating=false
	var site=get_nodes_in_group("perimeter_sites").filter(func(node):return node.game==game and node.role=="ground")[0]
	worker.focus=site
	worker.position=site.position+Vector2(24,0)
	partner.position=worker.position+Vector2(110,0)
	game.player_camera.update_view(0,true)
	for locale in ["de","en"]:
		L.set_locale(locale,false)
		var detail:=test_context(worker,"Locked perimeter "+locale)
		var body: String=" ".join(detail.lines)
		check("2" in body and "1" in body and "11" in body and detail.action_lines.is_empty(),"Compact locked site retains material costs and wave/research restriction "+locale)
		await capture("qhd-"+locale+"-construction")
	view.size=Vector2i(960,600)
	view.size_2d_override=Vector2i(1440,900)
	await frames()
	game.hud._layout_viewport()
	worker.focus=null
	worker.medical.bleeding=0
	worker.medical.fractured=false
	worker.hp=worker.max_hp
	worker.inventory.clear()
	partner.inventory.clear()
	game.player_camera.update_view(0,true)
	for locale in ["de","en"]:
		L.set_locale(locale,false)
		await capture("small-"+locale+"-coop")
		game.hud._toggle_audio()
		await frames()
		check(game.hud.overlay=="audio" and is_instance_valid(game.hud.options_panel),"Options remain reachable without permanent HUD hotkey tables "+locale)
		game.hud._close_audio()
		await frames()
	await Cleanup.free_scene(game,self)
	view.queue_free()
	await frames()
	print("QUIET HUD %d/%d"%[checks-failures,checks])
	quit(1 if failures else 0)
