extends SceneTree
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks:=0
var failures:=0
var game
var view: SubViewport
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	print("PARTY %s: %s"%["PASS" if value else "FAIL",label])
	if not value: failures+=1
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless" or not "--capture" in OS.get_cmdline_user_args(): return
	for unused in 3: await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://artifacts/expedition/party-"+label+".png")
func run() -> void:
	root.size=Vector2i(1600,900)
	view=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1440,900)
	view.size_2d_override_stretch=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.combat_events.persistence_enabled=false
	game.hud._open_character_selection(2)
	for unused in 3: await process_frame
	var panel: CharacterSelectPanel=game.hud.character_panel
	check(panel.player_count==2 and panel.slot_buttons.size()==4 and panel.count_buttons.size()==3,"local co-op starts at two with controls for two, three and four")
	panel.count_buttons[1].pressed.emit()
	check(panel.player_count==3 and game.hud.selection_count==3 and panel.slot_buttons[2].visible and not panel.slot_buttons[3].visible,"three-player selection enables exactly three independent slots")
	panel.count_buttons[2].pressed.emit()
	panel.select_slot(3)
	panel.select_character("ivo")
	check(panel.player_count==4 and game.selected_characters==["mara","branko","nora","ivo"],"four players have distinct starter identities; choosing a teammate swaps slots")
	var before: Array=game.selected_characters.duplicate()
	panel.select_character("levin")
	check(game.selected_characters==before,"unrecovered character stays unavailable to fourth slot")
	panel.count_buttons[0].pressed.emit()
	check(panel.active_slot==1 and game.selected_characters[3]=="ivo","reducing party size keeps choices and moves focus into active range")
	panel.count_buttons[2].pressed.emit()
	await capture("four-selection")
	panel.begin_session()
	for unused in 3: await physics_frame
	check(game.started and game.players.size()==4 and not paused,"begin spawns four actual local players")
	check(game.players[2].character_id=="nora" and game.players[3].character_id=="ivo" and game.players[2]!=game.players[3],"distinct chosen identities reach separate real actors")
	check(game.players[2].action("fire")=="p3_fire" and game.players[3].action("fire")=="p4_fire","third and fourth actors have independent input actions")
	check(PartyConfig.player_color(1)!=PartyConfig.player_color(3) and PartyConfig.player_color(2)!=PartyConfig.player_color(4),"all four HUD and aiming identities have distinct colors")
	game.rounds.running=false
	await capture("four-game")
	await Cleanup.free_scene(game,self)
	print("PARTY SELECTION: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
