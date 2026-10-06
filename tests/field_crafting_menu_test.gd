extends SceneTree
## Prepared actual main-world players; genuine mining clears the first floor
## through finite cells with supplied work deltas. This isolates UI access and
## order ownership; it is not a first-time-player navigation acceptance.
const NetInput := preload("res://scripts/network_input.gd")
const Messages := preload("res://scripts/network_messages.gd")
var checks := 0
var failures := 0
var game: Node
var player: Node
var other: Node

func _initialize() -> void: run.call_deferred()
func check(condition: bool,label: String) -> void:
	checks += 1
	if condition: print("CRAFT MENU PASS ",label)
	else:
		failures += 1
		push_error(label)
func frames(count: int = 3) -> void:
	for _index in count: await process_frame
func event_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await frames()
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless" or "--capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/field-crafting-menu-captures")
	root.get_texture().get_image().save_png("res://artifacts/field-crafting-menu-captures/"+name+".png")
func click(button: Button) -> void:
	var point := button.get_global_transform_with_canvas()*(button.size*0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion,true)
	for pressed: bool in [true,false]:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = point
		mouse.global_position = point
		mouse.pressed = pressed
		root.push_input(mouse,true)
		await frames()
func arrange() -> void:
	player.position = game.workshop.position+Vector2(8,0)
	player.velocity = Vector2.ZERO
	player.preferred_focus = game.workshop
	await frames()
	for _index in 3: await physics_frame

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.start_scenario(2,{"environment":"sector07","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	player = game.players[0]
	other = game.players[1]
	var bench: Node = game.workshop
	check(bench.position==Vector2(game.scenario_bunker.room_left+452,635),"Workbench is physically below the mixer beside the first-floor ammunition bay")
	check(not bench.accessible() and not bench.visible,"Unexcavated floor hides the actual bench")
	player.inventory = {"steel":6}
	player.position = bench.position
	check(not bench.request(player,"supply",0) and player.inventory.steel==6,"Hidden bench cannot consume material through the command API")
	check(not game.hud.open_crafting(player,bench),"Hidden bench cannot open its modal")
	check(await preload("res://tests/scenario_excavation_fixture.gd").clear_field(game,0,player),"Real finite mining interactions clear the first service floor")
	await frames()
	bench.refresh_access()
	check(bench.accessible() and bench.visible and game.scenario_bunker.open_depths==0,"Actual first excavation exposes crafting before paid room lining")
	await arrange()
	await event_action("p1_interact")
	check(is_instance_valid(game.hud.crafting_panel),"Real interaction event opens the picture-selection menu")
	if not is_instance_valid(game.hud.crafting_panel):
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
		quit(1)
		return
	var panel: Control = game.hud.crafting_panel
	check(game.hud.blocks_gameplay_input() and not paused,"Menu blocks controls while production/world keeps running")
	check(panel.recipe_buttons.size()==CraftingCatalog.recipes().size() and root.gui_get_focus_owner()==panel.recipe_buttons[0],"All registered recipes are keyboard/controller focusable and initially focus the selected image")
	check(NetInput.sample_local(game).held.is_empty(),"Network sample is neutral while the local crafting menu is open")
	game.network.active = true
	game.network.is_host = true
	game.network.local_player_id = 1
	game.network.peer_connected = false
	check(panel._network_ready(),"Host can still craft while no healthy guest link remains")
	game.network.active = false
	await event_action("ui_right")
	check(panel.selected_index==1 and root.gui_get_focus_owner()==panel.recipe_buttons[1],"Native menu navigation moves across recipe pictures")
	var original_position: Vector2 = player.position
	var before_inventory: Dictionary = player.inventory.duplicate()
	await event_action("p1_craft_next")
	await event_action("p1_deploy")
	await event_action("restart")
	check(bench.recipe_index(player)==0 and player.inventory==before_inventory and game.hud.crafting_panel==panel and not game.hud.has_session_action(),"G, deployment and restart cannot leak through the modal")
	await click(panel.recipe_buttons[2])
	check(panel.selected_index==2,"Mouse click chooses the armor picture")
	panel.confirm_button.pressed.emit()
	check(bench.order_for(player,2).working and player.inventory.steel==3,"Explicit confirmation supplies the exact armor cost and starts real production")
	check(bench.order_view(other,2).materials.is_empty() and other.progression.armor_tier==0,"Other player's materials and equipment remain personal")
	await capture("armor-producing-de")
	panel._select(0)
	panel.confirm_button.pressed.emit()
	check(bench.order_for(player,0).working and player.inventory.steel==1 and bench.order_for(player,2).working,"Two selected plans retain independent paid production orders")
	check(not bench.request(other,"collect",2),"Other owner cannot collect the first player's armor")
	await create_timer(3.2,false).timeout
	panel._select(2)
	check(not panel.confirm_button.disabled,"Finished armor becomes available without reopening the menu")
	panel.confirm_button.pressed.emit()
	check(player.progression.armor_tier==1 and not bench.order_for(player,2).ready,"Explicit collection equips the paid personal armor once")
	check(not bench.request(player,"collect",2) and player.progression.armor_tier==1,"Duplicate collect cannot equip or credit an order twice")
	panel._select(3)
	panel.confirm_button.pressed.emit()
	check(not bench.order_for(player,3).working and bench.order_for(player,3).materials.get("steel",0)==1 and bench.order_for(player,3).materials.get("alloy",0)==0,"Partial steel payment cannot start armor without alloy")
	check(panel.confirm_button.disabled,"Empty hands disable further payment without losing the partial order")
	LocaleText.set_locale("en",false)
	await frames()
	await capture("armor-unavailable-en")
	LocaleText.set_locale("de",false)
	await event_action("ui_cancel")
	check(not is_instance_valid(game.hud.crafting_panel) and not game.hud.blocks_gameplay_input(),"Escape/controller cancel closes only crafting and restores controls")
	await arrange()
	Input.action_press("p1_interact")
	for _index in 3: await physics_frame
	check(is_instance_valid(game.hud.crafting_panel),"Held interaction fallback also opens a menu rather than paying automatically")
	game.hud.close_crafting()
	var before_close: Dictionary = player.inventory.duplicate()
	for _index in 3: await physics_frame
	check(player.inventory==before_close and not is_instance_valid(game.hud.crafting_panel),"Held opening input remains quarantined after close")
	Input.action_release("p1_interact")
	await frames()
	player.position = Vector2(bench.position.x+300,bench.position.y)
	check(not bench.request(player,"supply",0),"Host refuses crafting commands from outside interaction reach")
	player.position = original_position
	player.progression.armor_tier = 0
	other.position = bench.position+Vector2(-12,0)
	other.inventory = {"steel":2}
	var sender_before: Dictionary = player.inventory.duplicate()
	game.network._handle_command("craft",{"action":"supply","recipe":0},2)
	check(bench.order_for(other,0).working and other.inventory.get("steel",0)==0 and player.inventory==sender_before,"Host command credits only the authenticated sender's personal order")
	game.network.match_paused = true
	other.inventory = {"steel":3}
	game.network._handle_command("craft",{"action":"supply","recipe":2},2)
	check(other.inventory.steel==3 and not bench.order_view(other,2).working,"Authoritative pause refuses new crafting payments")
	game.network.match_paused = false
	game.network._handle_command("craft",{"action":"supply","recipe":999},2)
	check(other.inventory.steel==3,"Host revalidates the recipe range even outside the envelope decoder")
	var command := {"kind":"command","generation":1,"command":"craft","args":{"action":"supply","recipe":2}}
	check(Messages.valid(command,true),"Craft control envelope accepts a bounded explicit recipe")
	for arguments in [{"action":"supply","recipe":-1},{"action":"supply","recipe":CraftingCatalog.recipes().size()},{"action":"collect","recipe":0.5},{"action":"unknown","recipe":0},{"action":"supply","recipe":0,"player_id":2}]:
		command.args = arguments
		check(not Messages.valid(command,true),"Craft control envelope refuses forged/out-of-range arguments: "+str(arguments))
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("CRAFT MENU: %d/%d passed" % [checks-failures,checks])
	quit(0 if failures==0 else 1)
