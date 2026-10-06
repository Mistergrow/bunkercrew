extends SceneTree
## Real HUD with prepared cargo/stations; frozen waves, no profile changes.
const DEST := "res://artifacts/bunkercrew-ui"
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var view: SubViewport
var checks := 0
var failures := 0
var captures := false
var shots: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func frames(count: int=3) -> void:
	for index in count: await process_frame

func capture(label: String) -> void:
	if not captures: return
	await frames()
	await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png(DEST+"/"+label+".png")==OK,"Capture "+label)
	shots.append(label)

func check_dock(index: int,label: String) -> Dictionary:
	var worker=game.players[index]
	var solo: bool=game.network.active or game.players.size()==1
	var width: float=minf(520,game.hud.screen_rect().size.x-392) if solo else (440.0 if game.players.size()==2 else game.hud.player_bounds(index).size.x)
	var detail: Dictionary=game.hud.compact_context_details(worker,width-24,14)
	var rect: Rect2=game.hud.context_bounds(index,detail)
	var screen: Rect2=game.hud.screen_rect()
	check(screen.encloses(rect),label+" context remains inside actual viewport")
	check(rect.position.y>=screen.end.y-275,label+" keeps context in the bottom edge region")
	check(not rect.intersects(game.hud.player_bounds(index)),label+" does not cover health or ammunition")
	check(UiArt.FONT.get_string_size(detail.title,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x<=width-24,label+" title fits at 16px")
	for line: String in detail.lines+detail.action_lines:
		check(UiArt.FONT.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x<=width-24,label+" body/control line fits at14px")
	var original: Vector2=worker.focus.position
	worker.focus.position+=Vector2(40,-30)
	check(rect==game.hud.context_bounds(index,detail),label+" dock position is independent of object movement")
	worker.focus.position=original
	return detail

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	captures="--capture" in OS.get_cmdline_user_args()
	if captures and DisplayServer.get_name()=="headless": quit(2); return
	AudioServer.set_bus_mute(0,true)
	root.size=Vector2i(320,180)
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
	view=SubViewport.new()
	view.size=Vector2i(1440,900)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.running=false
	game.rounds.set_process(false)
	game.set_process(false)
	game.medic.set_physics_process(false)
	game.dialogue.reset()
	game.notice_time=0
	var furnace=get_nodes_in_group("stations").filter(func(node): return node.game==game and node.kind=="furnace")[0]
	furnace.set_process(false)
	furnace.output_amount=1
	var worker=game.players[0]
	worker.set_physics_process(false)
	worker.position=furnace.position+Vector2(-35,0)
	worker.focus=furnace
	worker.inventory={"sand":worker.capacity()}
	game.player_camera.view_zoom=.9
	game.player_camera.update_view(0,true)
	await frames()
	for locale in ["de","en"]:
		LocaleText.set_locale(locale,false)
		var detail:=check_dock(0,"Solo "+locale)
		var text: String=" ".join(detail.lines+detail.action_lines)
		check(text.count(LocaleText.text("Inventar voll"))==1,"Full inventory appears exactly once "+locale)
		check(not detail.show_key,"Blocked collection displays no actionable hold key "+locale)
		await capture("solo-furnace-"+locale)
		game.hud.overlay="help"
		game.hud._apply_overlay_pause()
		await capture("controls-"+locale)
		game.hud.overlay=""
		game.hud._apply_overlay_pause()
	worker.focus=game.core
	var intact: Dictionary=game.hud.context_details(worker)
	check(not intact.show_key and intact.action.is_empty(),"Intact core never advertises a no-op hold action")
	var room_site=get_nodes_in_group("scenario_room_sites").filter(func(node): return node.game==game)[0]
	worker.focus=room_site
	var raw_room: Dictionary=game.hud.context_details(worker)
	check(not raw_room.show_key and raw_room.action.is_empty(),"Unexcavated room asks for digging before enabling construction")
	var stock=get_nodes_in_group("supplies").filter(func(node): return node.game==game and node.kind=="ammo")[0]
	worker.focus=stock
	worker.position=stock.position+Vector2(-28,0)
	worker.inventory={"ammo":1}
	worker.selected_kind="ammo"
	game.player_camera.update_view(0,true)
	for locale in ["de","en"]:
		LocaleText.set_locale(locale,false)
		var supply:=check_dock(0,"Ammunition storage "+locale)
		var actions: String=" ".join(supply.action_lines)
		check("R" in actions and "E" in actions and "G" in actions,"Storage keeps refill, collect and deposit controls "+locale)
		await capture("supply-controls-"+locale)
	# Repeated nearby presses remain explicit in two/four player couch co-op.
	while game.players.size()<4: game.join_coop()
	game.notice_time=0
	for index in game.players.size():
		var partner=game.players[index]
		partner.set_physics_process(false)
		partner.position=furnace.position+Vector2(-95+index*48,0)
		partner.focus=furnace
		partner.inventory={"sand":partner.capacity()} if index%2==0 else {}
	game.player_camera.update_view(0,true)
	await frames()
	for resolution in [Vector2i(1440,900),Vector2i(2560,1440),Vector2i(960,600)]:
		view.size=resolution
		view.size_2d_override=Vector2i(1600,900) if resolution.x==2560 else Vector2i(1440,900)
		view.size_2d_override_stretch=true
		await frames()
		game.hud._layout_viewport()
		game.player_camera.update_view(0,true)
		for locale in ["de","en"]:
			LocaleText.set_locale(locale,false)
			var rectangles: Array[Rect2]=[]
			for index in 4:
				var detail:=check_dock(index,"Co-op%d %s %s"%[index+1,str(resolution),locale])
				var bounds: Rect2=game.hud.context_bounds(index,detail)
				for other in rectangles: check(not bounds.intersects(other),"Local context columns never overlap")
				rectangles.append(bounds)
			for index in 4:
				game.hud.combat_overlay.handle_event("hit",{"player_id":index+1,"position":game.players[index].position+Vector2(0,220),"damage":15,"enemy_id":500+index})
			var numbers: Array=game.hud.combat_overlay.number_layout()
			check(not numbers.is_empty(),"Crowded co-op still displays combat feedback")
			for number in numbers:
				for reserved: Rect2 in game.hud.occupied_gameplay_bounds():
					check(not number.rect.intersects(reserved),"Combat feedback avoids all status/context docks")
			game.hud.combat_overlay.numbers.clear()
			await capture("coop4-%d-%s"%[resolution.x,locale])
	# Prepared projection points span four floors; camera fitting must reserve
	# the full footer height, not merely keep feet inside the window.
	var positions: Array[Vector2]=[]
	for index in 4:
		positions.append(game.players[index].position)
		game.players[index].position=Vector2(650,245+index*185)
	game.player_camera.view_zoom=1.25
	game.player_camera.update_view(0,true)
	var footer_top: float=game.hud.screen_rect().end.y
	for occupied: Rect2 in game.hud.occupied_gameplay_bounds():
		if occupied.position.y>game.hud.screen_rect().get_center().y: footer_top=minf(footer_top,occupied.position.y)
	for index in 4:
		var feet: Vector2=game.hud.world_to_ui(game.players[index].position)
		check(feet.y<footer_top-12,"Four-floor camera keeps every worker above the docks")
		game.players[index].position=positions[index]
	# An online guest gets a single local dock; remote crew occupies a small list.
	game.network.active=true
	game.network.is_host=false
	game.network.local_player_id=3
	game.network.state="playing"
	game.network.set_process(false)
	game.network.set_physics_process(false)
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	await frames()
	game.hud._layout_viewport()
	game.player_camera.update_view(0,true)
	var online:=check_dock(2,"Online guest")
	check(game.hud.context_details(game.players[2]).key=="E","Online P3 retains local E controls")
	var local: Rect2=game.hud.context_bounds(2,online)
	for index in [0,1,3]: check(not local.intersects(game.hud.player_bounds(index)),"Remote crew health does not cover local context")
	await capture("online-guest-en")
	game.network.leave()
	var metadata:=FileAccess.open(DEST+("/hud-metadata.json" if captures else "/hud-checks.json"),FileAccess.WRITE)
	metadata.store_string(JSON.stringify({"captures":shots,"fixture":"Actual Ash Foundry scene; stopped waves and frozen worker positions, assigned cargo and one prepared furnace output. Online guest state arranged locally; no sockets opened.","checks":checks,"failures":failures},"\t"))
	check(await Cleanup.free_scene(game,self),"Scene releases cleanly")
	view.queue_free()
	await frames()
	print("BUNKERCREW HUD: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
