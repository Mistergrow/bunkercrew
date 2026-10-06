extends SceneTree
## Full main scene and real direct host. Required --no-upnp prevents router
## changes; this checks lobby/menu integration without claiming Internet reach.
var game
var checks := 0
var failures := 0
const JoinCode := preload("res://scripts/network_join_code.gd")
func _initialize() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func frames(count: int=2) -> void:
	for frame in count: await process_frame
func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await frames()
func _run() -> void:
	if "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("This fixture requires --no-upnp to leave router configuration unchanged")
		quit(1)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	await frames()
	check(game.network.state=="offline" and not game.network.active,"Actual main scene creates an idle session without opening a socket")
	await press("join")
	check(game.hud.overlay=="scenario" and not game.network.active,"F2 still opens local coop and never creates an online room")
	await press("ui_cancel")
	await frames()
	var online: Button
	for button in game.hud.buttons:
		if button.text=="ONLINE-KOOP": online = button
	check(is_instance_valid(online),"Main menu exposes a separate Online-Koop button")
	if not is_instance_valid(online):
		quit(1)
		return
	online.grab_focus()
	await press("ui_accept")
	check(game.hud.overlay=="network" and is_instance_valid(game.hud.network_panel),"Keyboard acceptance enters the real online lobby")
	var panel = game.hud.network_panel
	check(panel.server_field.text.is_empty() and not panel.server_field.visible,"Hosting this PC is the default; external relay is optional")
	check(panel.public_address_field.text.is_empty() and not panel.public_address_field.visible,"Automatic addressing stays the default and the manual field stays under server options")
	panel.create_button.grab_focus()
	await press("ui_accept")
	check(game.network.state=="lobby" and game.network.active and game.network.is_host,"Actual create button opens the direct ENet host")
	check(str(game.network.room_code).replace("-","").length()==26 and game.network.room_code==game.network.lan_code,"Default direct connection exposes a short eight-symbol LAN invitation")
	check(str(game.network.direct_code).replace("-","").length()==34 and JoinCode.decode(game.network.direct_code).invite==game.network.room_code.replace("-",""),"Direct fallback preserves the LAN address and the full invitation secret")
	check(game.network.transport._active_job==null,"Host preview performs no UPnP router mapping")
	check(game.network.get_parent()==root and game.network.process_mode==Node.PROCESS_MODE_ALWAYS,"Real session stays alive while the lobby scene is paused")
	check(not game.network.peer_connected and panel.start_button.disabled,"Real match cannot start before a partner has connected")
	panel.character_buttons[2].pressed.emit()
	check(game.selected_characters.slice(0,2)==["ivo","branko"],"Actual host character command changes only P1")
	panel.scene_button.pressed.emit()
	await frames()
	check(game.hud.overlay=="scenario" and game.network.state=="lobby","Host can choose a world while the room continues listening")
	game.hud.scenario_panel.choose("environment","frozen_rail_yard")
	game.hud.scenario_panel.next_button.pressed.emit()
	await frames()
	check(game.hud.overlay=="network" and game.hud.scenario_options.environment=="frozen_rail_yard","Confirming the real world chooser returns to the online room")
	panel = game.hud.network_panel
	check(game.selected_characters.slice(0,2)==["ivo","branko"] and panel.copy_button.visible,"Rebuilt lobby keeps identity choices and the shareable room code")
	if DisplayServer.get_name()!="headless":
		await frames(3)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/network"))
		root.get_texture().get_image().save_png("res://artifacts/network/actual-host-lobby.png")
	panel.leave_button.pressed.emit()
	await frames()
	check(game.hud.overlay=="menu" and not game.network.active and game.network.state=="offline","Leaving the real lobby closes the socket and returns to the menu")
	check(game.network.get_parent()==game,"Inactive session returns under the game scene for clean teardown")
	game.hud._open_network()
	await frames()
	panel = game.hud.network_panel
	panel.show_server_options = true
	panel.public_address_field.text = "8.8.8.8"
	panel._refresh()
	check(panel.public_address_field.visible and panel.public_address_field.editable,"Manual IPv4 is editable before creating a direct room")
	panel.create_button.pressed.emit()
	await frames()
	# Advertise an example address only. This fixture never connects to it or
	# maps a router port, and makes no claim that the address is reachable.
	var public_code: String = game.network.internet_code
	var local_code: String = game.network.lan_code
	check(game.network.state=="lobby" and game.network.advertised_address=="8.8.8.8" and JoinCode.decode(public_code).address=="8.8.8.8","Actual create button encodes the manually entered public IPv4")
	check(local_code.replace("-","").length()==26 and game.network.room_code==local_code and panel.copy_internet_button.visible and panel.copy_direct_button.visible,"Manual Internet code preserves the primary short LAN invitation and both separate copy actions")
	check(not panel.public_address_field.editable and game.network.transport._active_job==null,"Manual host locks its field and still performs no UPnP mapping in this fixture")
	for invalid in ["192.168.1.25","127.0.0.1","224.0.0.1","255.255.255.255","300.1.2.3","not-an-ip"]:
		check(not game.network.set_advertised_address(invalid) and game.network.internet_code==public_code and game.network.room_code==local_code and game.network.lan_code==local_code,"Invalid or non-public address preserves the host codes: "+invalid)
	check(not game.network.connection_hint.is_empty() and game.network.state=="lobby","Address validation leaves the current LAN room available and explains the problem")
	game.network.set_advertised_address("8.8.8.8")
	if DisplayServer.get_name()!="headless":
		await frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/network/actual-manual-address-lobby.png")
	panel.leave_button.pressed.emit()
	await frames()
	check(not game.network.active and game.hud.overlay=="menu","Manual-address room exits through the same clean lobby path")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Actual main scene and audio resources are released")
	print("LIVE NETWORK LOBBY: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
