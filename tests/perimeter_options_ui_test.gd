extends SceneTree
## Prepared research/site states; real local options callbacks and HUD text layout.
const L=preload("res://scripts/locale_text.gd")
const Cleanup=preload("res://tests/scene_cleanup.gd")
const OUTPUT="res://artifacts/perimeter-ui/"
var game
var view: SubViewport
var checks:=0
var failures:=0
var capture_enabled:=false
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
	print("PERIMETER UI %s: %s"%["PASS" if value else "FAIL",label])
func frames(count: int=3) -> void:
	for unused in count: await process_frame
func overlay(value: String) -> void:
	game.hud.overlay=value
	game.hud._apply_overlay_pause()
	await frames()
func capture(label: String) -> void:
	if not capture_enabled: return
	await frames()
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image()
	check(image.get_size()==view.size and image.save_png(OUTPUT+label+".png")==OK,label+" native capture")
func width(value: String,font_size: int) -> float:
	return UiArt.FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
func check_context(site: Node,worker: Node,label: String) -> Dictionary:
	worker.focus=site
	var detail: Dictionary=game.hud.context_details(worker)
	var fits:=width(L.format("P%d · %s",[worker.player_id,detail.title]),13)<=366
	for line in detail.lines: fits=fits and width(line,12)<=366
	for line in detail.action_lines: fits=fits and width(line,10)<=366
	var height: int=64+detail.lines.size()*16+detail.action_lines.size()*14+(17 if detail.multiple else 0)
	check(fits and height<=255,label+" localized costs/status fit the real context panel")
	if L.current_locale()=="en":
		var body: String=" ".join(detail.lines)+" "+" ".join(detail.action_lines)
		var untranslated:=false
		for word in ["Reparatur","Schuss","Ausbau","Stahl","Bodenwache"]: untranslated=untranslated or word in body
		check(not untranslated,label+" contains English status, resources and action text")
	return detail
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	capture_enabled="--capture" in OS.get_cmdline_user_args()
	if capture_enabled and DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	view=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.world_2d=World2D.new()
	view.gui_embed_subwindows=true
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.combat_events.persistence_enabled=false
	await frames()
	if not "combat_gore" in game or not is_instance_valid(game.combat_gore):
		check(false,"Actual main scene has the local presentation backend")
		await Cleanup.free_scene(game,self)
		quit(1)
		return
	game.start_scenario(2,{"environment":"overgrown_steelworks","position":"center","build_type":"bastion"})
	game.rounds.set_process(false)
	game.set_process(false)
	game.dialogue.reset()
	game.dialogue.set_process(false)
	game.notice_time=0
	for worker in game.players: worker.set_physics_process(false)
	var sites: Array=get_nodes_in_group("perimeter_sites").filter(func(site):return site.game==game)
	check(sites.size()==6,"Real center layout provides six persistent perimeter sites")
	check(not game.upgrades.node_data("perimeter_automation").is_empty(),"Research board includes the ground perimeter technology")
	if sites.is_empty() or game.upgrades.node_data("perimeter_automation").is_empty():
		await Cleanup.free_scene(game,self)
		quit(1)
		return
	for site in sites: site.set_physics_process(false)
	var ground=sites.filter(func(site):return site.role=="ground" and site.side==1)[0]
	var worker=game.players[0]
	worker.position=ground.position+Vector2(39,0)
	game.players[1].position=worker.position+Vector2(55,0)
	game.player_camera.update_view(0,true)
	var original_hp: float=worker.hp
	var original_cargo: Dictionary=worker.inventory.duplicate()
	var original_points: int=game.upgrades.points
	await overlay("audio")
	game.hud.options_panel.select_tab(0)
	var options=game.hud.options_panel
	for level in [0,1,2]:
		options.violence_choice.item_selected.emit(level)
		await frames()
		check(game.combat_gore.level==level and options.violence_choice.selected==level,"Native selector applies local presentation level %d"%level)
	check(worker.hp==original_hp and worker.inventory==original_cargo and game.upgrades.points==original_points and ground.tier==0,"Display choices preserve HP, inventory, research points and construction")
	check(not FileAccess.file_exists("user://violence.cfg"),"No-profile-save creates no violence configuration file")
	for resolution in ["qhd","small"]:
		view.size=Vector2i(2560,1440) if resolution=="qhd" else Vector2i(960,600)
		view.size_2d_override=Vector2i(1600,900) if resolution=="qhd" else Vector2i(1440,900)
		await frames()
		game.hud._layout_viewport()
		for locale in ["de","en"]:
			L.set_locale(locale,false)
			await overlay("audio")
			options=game.hud.options_panel
			options.select_tab(0)
			var labels: Array=["Aus","Blut","Blut + Abtrennungen"] if locale=="de" else ["Off","Blood","Blood + dismemberment"]
			var fit:=true
			for index in 3:
				var choice_font: Font=options.violence_choice.get_theme_font("font")
				var choice_extent: float=choice_font.get_string_size(labels[index],HORIZONTAL_ALIGNMENT_LEFT,-1,options.violence_choice.get_theme_font_size("font_size")).x
				fit=fit and options.violence_choice.get_item_text(index)==labels[index] and choice_extent<=options.violence_choice.size.x-40
			check(fit,"Three violence labels are translated and fit at "+resolution+" "+locale)
			check(options.tab_buttons.size()==5 and options.violence_choice.get_rect().end.y<options.renderer_choice.position.y,"Five tabs and renderer keep separate input areas")
			check(options.violence_choice.selected==2,"Locale and viewport changes preserve the selected local setting")
			await capture(resolution+"-"+locale+"-violence-options")
			if capture_enabled and resolution=="qhd":
				options.violence_choice.show_popup()
				await capture(resolution+"-"+locale+"-violence-choices")
				options.violence_choice.get_popup().hide()
			await overlay("upgrades")
			var panel=game.hud.upgrade_panel
			var board_fits: bool=panel.node_buttons.size()==UpgradeSystem.NODES.size() and panel.tab_buttons.size()==4 and panel.tree_scroll.clip_contents and panel.tree_scroll.get_rect()==panel.TREE_RECT
			for category in 4:
				panel.select_category(category)
				for index in panel.node_buttons.size():
					var button: Button=panel.node_buttons[index]
					var entry: Dictionary=UpgradeSystem.NODES[index]
					board_fits=board_fits and button.visible==(int(entry.branch)==category)
					if not button.visible: continue
					board_fits=board_fits and Rect2(Vector2.ZERO,panel.tree_content.size).encloses(button.get_rect()) and button.size.y>=72
					board_fits=board_fits and panel.node_title_lines(entry).size()<=2 and panel._node_title_size(entry.title)>=14
					for other in range(index):
						if panel.node_buttons[other].visible: board_fits=board_fits and not button.get_rect().intersects(panel.node_buttons[other].get_rect())
					board_fits=board_fits and panel._detail_lines(entry.detail).size()<=10
			check(board_fits,"Four complete research ledgers fit their clipped scroll content and inspector at "+resolution+" "+locale)
			panel.select_category(0)
			var ground_index: int=UpgradeSystem.NODES.find(game.upgrades.node_data("perimeter_automation"))
			panel.node_buttons[ground_index].grab_focus()
			await frames()
			check(panel.node_buttons[ground_index].has_focus() and panel.selected_id=="perimeter_automation" and panel.purchase_button.disabled,"Locked ground research stays inspectable through native focus without allowing purchase")
			check(width(L.text(game.upgrades.node_data("perimeter_automation").title).capitalize(),panel._selection_title_size(game.upgrades.node_data("perimeter_automation").title))<=347,"Expanded ground title fits detail column")
			await capture(resolution+"-"+locale+"-research")
			await overlay("")
			game.rounds.wave=1
			ground.tier=0
			ground.materials={}
			worker.inventory.clear()
			var detail:=check_context(ground,worker,"Locked "+locale)
			check(not detail.show_key and detail.action_lines.is_empty(),"Locked site does not advertise a working key")
			check("2" in " ".join(detail.lines) and "1" in " ".join(detail.lines),"Locked site still shows future material costs")
			await capture(resolution+"-"+locale+"-locked-site")
			game.rounds.wave=16
			game.upgrades.owned={"bunker_workshop":true,"bunker_armor":true,"perimeter_automation":true}
			ground.materials={"steel":1}
			worker.inventory={"steel":1}
			check_context(ground,worker,"Partial deposit "+locale)
			await capture(resolution+"-"+locale+"-site-costs")
			ground.tier=1
			ground.max_hp=160
			ground.hp=160
			ground.ammo=0
			worker.inventory={"ammo":1}
			ground.sync_replica()
			detail=check_context(ground,worker,"Ammunition "+locale)
			check(detail.show_key and "20" in " ".join(detail.lines),"Ammo prompt explains rounds per carried crate")
			await capture(resolution+"-"+locale+"-site-ammo")
			ground.hp=80
			worker.inventory={"steel":1}
			detail=check_context(ground,worker,"Repair "+locale)
			check(detail.show_key and "80" in " ".join(detail.lines),"Repair prompt shows one material and restored HP")
			await capture(resolution+"-"+locale+"-site-repair")
			ground.tier=0
			ground.hp=0
			ground.max_hp=0
			ground.sync_replica()
			game.upgrades.owned={}
	await overlay("upgrades")
	game.rounds.wave=16
	game.upgrades.owned={"bunker_workshop":true,"bunker_armor":true}
	game.upgrades.points=7
	game.hud.upgrade_panel._refresh()
	for id in ["perimeter_automation"]:
		game.hud.upgrade_panel._select(id)
		game.hud.upgrade_panel.purchase_button.pressed.emit()
		check(game.upgrades.has_upgrade(id),"Selected compact research card can buy "+id)
	check(game.upgrades.points==0,"The perimeter research purchase charges exactly seven points")
	await Cleanup.free_scene(game,self)
	view.queue_free()
	await frames(2)
	print("Perimeter options UI: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
