extends SceneTree
const LobbyPanel := preload("res://scripts/network_panel.gd")
const JoinCode := preload("res://scripts/network_join_code.gd")
const L := preload("res://scripts/locale_text.gd")
class ClipboardPanel extends LobbyPanel:
	var copied := ""
	func _write_clipboard(value: String) -> void:
		copied = value
class Session extends Node:
	signal changed
	var active := false
	var is_host := true
	var local_player_id := 1
	var state := "offline"
	var room_code := ""
	var short_room_code := ""
	var lan_code := ""
	var direct_code := ""
	var internet_code := ""
	var error_message := ""
	var peer_connected := false
	var _authenticated := false
	@warning_ignore("unused_private_class_variable")
	var _short_resolution := ""
	var relay_url := ""
	var advertised_address := ""
	var connection_hint := ""
	var commands: Array = []
	var max_players := 4
	var fixture_slots: Array=[]
	func connected_player_count() -> int: return fixture_slots.size() if not fixture_slots.is_empty() else (2 if peer_connected else 1)
	func is_player_connected(id: int) -> bool: return id in fixture_slots if not fixture_slots.is_empty() else (id==1 or id==2 and peer_connected)
	func character_owner(id: String, excluding_player: int=0) -> int:
		var characters: Array = get_parent().selected_characters
		for index in characters.size():
			if index+1 != excluding_player and is_player_connected(index+1) and characters[index] == id: return index+1
		return 0
	var starts := 0
	var resumes := 0
	var requested_url := "!"
	func host_room(url: String="") -> void:
		requested_url = url
		relay_url = url
		active = true
		is_host = true
		local_player_id = 1
		state = "lobby"
		room_code = JoinCode.lan("23456789ABCDEFGH")
		lan_code = room_code
		direct_code = JoinCode.invite("192.168.1.25",JoinCode.DEFAULT_PORT,"23456789ABCDEFGH")
		connection_hint = "Im selben Netzwerk bereit. Routerfreigabe nicht angefordert."
		changed.emit()
	func join_room(url: String,code: String) -> void:
		requested_url = url
		relay_url = url
		active = true
		is_host = false
		local_player_id = 2
		state = "lobby"
		room_code = code
		peer_connected = true
		_authenticated = true
		changed.emit()
	func leave() -> void:
		active = false
		state = "offline"
		room_code = ""
		lan_code = ""
		direct_code = ""
		internet_code = ""
		changed.emit()
	func send_command(kind: String,args: Dictionary) -> void:
		commands.append({"kind":kind,"args":args})
	func start_match(_options: Dictionary,_characters: Array) -> void:
		starts += 1
	func resume_campaign() -> bool:
		resumes += 1
		return true
	func set_advertised_address(address: String) -> bool:
		advertised_address = address
		return true
class World extends Node2D:
	var network: Node
	var selected_characters := ["mara","branko"]
	var started := false
	var restarts := 0
	func restart() -> void: restarts += 1
	func return_to_menu() -> bool:
		restarts += 1
		return true
class ChatUi extends Control:
	var unread := 0
	func available() -> bool: return false
	func open() -> void: pass
class Hud extends Node:
	var chat_panel := ChatUi.new()
	func _init() -> void: add_child(chat_panel)
	var overlay := "network"
	var scenario_options: Dictionary = {}
	var selection_count := 1
	var story_selected := false
	func _open_social() -> void: overlay = "friends"
	func _wrap(text: String,_limit: int) -> Array[String]: return [text]
	func _open_scenario_selection(count: int) -> void:
		selection_count = count
		overlay = "scenario"
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _run() -> void:
	InputSetup.install()
	L.set_locale("de",false)
	root.size = Vector2i(1440,900)
	var game := World.new()
	game.network = Session.new()
	game.add_child(game.network)
	root.add_child(game)
	var hud := Hud.new()
	game.add_child(hud)
	var panel := ClipboardPanel.new()
	panel.game = game
	panel.hud = hud
	game.add_child(panel)
	check(panel._member_count()==0 and panel.crew_status()=="Kein aktiver Raum", "Fresh offline lobby cannot claim a connected player or active room")
	check(panel.crew_buttons.all(func(button): return button.disabled), "All offline crew rows remain empty and noninteractive")
	L.set_locale("en",false)
	check(panel.crew_status()=="No active room", "Offline room status uses the selected language")
	L.set_locale("de",false)
	check(not panel.server_field.visible and panel.server_field.text=="wss://bunkercrew.vibechain.rocks/ws" and not panel.direct_mode,"New online rooms default to the public SSL relay without opening advanced settings")
	check(not panel.public_address_field.visible and panel.public_address_field.text.is_empty(),"Manual public address is an optional advanced setting")
	panel.restore_connection_preferences({"server":""})
	check(not panel.direct_mode and not panel.server_field.text.is_empty(),"An old implicit empty RAM draft migrates to the online relay default")
	panel.restore_connection_preferences({"server":"","connection_mode":"direct"})
	check(panel.direct_mode and panel.server_field.text.is_empty(),"An explicit new LAN/direct choice survives draft restoration")
	panel.restore_connection_preferences({"server":"wss://custom.example/ws"})
	check(not panel.direct_mode and panel.server_field.text=="wss://custom.example/ws","An old nonempty custom relay draft retains its selected endpoint")
	panel.connection_mode_button.pressed.emit()
	check(panel.direct_mode and panel.server_field.text.is_empty(),"Explicit server-options mode action selects LAN/direct")
	panel.connection_mode_button.pressed.emit()
	check(not panel.direct_mode and panel.server_field.text=="wss://bunkercrew.vibechain.rocks/ws","Returning from LAN/direct restores the online default")
	panel._host()
	check(game.network.requested_url=="wss://bunkercrew.vibechain.rocks/ws" and game.network.relay_url==game.network.requested_url and panel.connection_mode_button.disabled,"Creating a new default online room requests the SSL relay and fixes its transport mode")
	game.network.leave()
	panel.show_server_options = true
	panel.server_field.text = "wss://relay.example.invalid"
	panel._refresh()
	check(panel.public_address_field.visible and not panel.public_address_field.editable,"Relay mode disables the irrelevant manual public address")
	panel.server_field.text = ""
	panel.show_server_options = false
	panel._refresh()
	check(panel.join_button.disabled and panel.start_button.disabled,"Empty join code and disconnected match cannot start")
	panel._host()
	check(panel._member_count()==1 and panel.crew_status()=="1 / 4 verbunden", "A created room counts its actual local host exactly once")
	check(game.network.requested_url.is_empty() and panel.copy_button.visible,"Creating a room uses this PC and offers a shareable code")
	panel.restore_connection_preferences({"server":"wss://other.example/ws","connection_mode":"relay"})
	panel.connection_mode_button.pressed.emit()
	check(panel.direct_mode and panel.server_field.text.is_empty() and game.network.relay_url.is_empty(),"Restoring or toggling options never migrates an already-created direct host")
	check(not panel.public_address_field.editable and not panel.server_field.editable and not panel.code_field.editable,"Connection fields are read-only while hosting")
	check(game.network.room_code.replace("-","").length()==16 and game.network.lan_code==game.network.room_code,"Primary LAN invitation has exactly sixteen symbols")
	check(game.network.direct_code.replace("-","").length()==24 and JoinCode.decode(game.network.direct_code).invite=="23456789ABCDEFGH","Fallback direct code retains all twenty-four symbols and the invitation secret")
	check(panel.copy_direct_button.visible and not panel.copy_internet_button.visible and panel._primary_code_label()=="LAN-Code","LAN host shows its short invitation and direct fallback without offering an Internet code")
	panel.copy_button.pressed.emit()
	check(panel.copied==game.network.room_code and panel.copied.length()==19,"Primary copy keeps the complete short LAN invitation")
	panel._copy_lan_code()
	check(panel.copied==game.network.lan_code,"Explicit LAN copy uses the short LAN invitation")
	panel.copy_direct_button.pressed.emit()
	check(panel.copied==game.network.direct_code and panel.copied.length()==29,"Fallback copy preserves the full direct invitation")
	game.network.internet_code = JoinCode.invite("8.8.8.8",JoinCode.DEFAULT_PORT,"23456789ABCDEFGH")
	panel._refresh()
	check(panel.copy_internet_button.visible and panel.copy_button.text=="LAN-Code kopieren" and game.network.room_code==game.network.lan_code,"Internet availability adds a separate action and preserves the primary LAN invitation")
	panel.copy_internet_button.pressed.emit()
	check(panel.copied==game.network.internet_code and panel.copied.replace("-","").length()==24 and JoinCode.decode(panel.copied).address=="8.8.8.8","Internet action copies the complete public invitation")
	panel.copy_button.pressed.emit()
	check(panel.copied==game.network.lan_code,"Primary copy still selects LAN after an Internet invitation becomes available")
	game.network.short_room_code="ABC234"
	panel._refresh();panel.copy_button.pressed.emit()
	check(panel.copied=="ABC234" and panel._primary_code_label()=="Raumcode","Primary sharing copies exactly the server-confirmed six-character room code")
	check(not panel.copy_direct_button.visible and not panel.copy_internet_button.visible,"Short-code sharing keeps long fallback actions out of the main view")
	panel.show_server_options=true;panel._refresh()
	check(panel.copy_direct_button.visible and panel.copy_internet_button.visible,"Advanced server options preserve full direct and Internet fallback invitations")
	game.network.short_room_code="";panel.show_server_options=false;panel._refresh()
	for locale in ["de","en"]:
		L.set_locale(locale,false)
		panel.refresh_locale()
		check(panel.copy_button.tr(panel.copy_button.text)==("LAN-Code kopieren" if locale=="de" else "Copy LAN code"),locale+" primary copy label is localized")
		check(L.text(panel._primary_code_label())==("LAN-Code" if locale=="de" else "LAN code"),locale+" room label explicitly identifies the LAN invitation")
		check(panel.copy_direct_button.tr(panel.copy_direct_button.text)==("Direktcode kopieren" if locale=="de" else "Copy direct code"),locale+" fallback action is localized")
		check(panel.copy_internet_button.tr(panel.copy_internet_button.text)==("Internetcode kopieren" if locale=="de" else "Copy internet code"),locale+" Internet action is localized")
		check(panel._status_text()==("Raum bereit. Teile den Code mit deiner Crew." if locale=="de" else "Room ready. Share the code with your crew."),locale+" room status is translated before wrapping")
		check(panel._connection_hint_text()==("Im selben Netzwerk bereit. Routerfreigabe nicht angefordert." if locale=="de" else "Ready on the local network. Router port mapping was not requested."),locale+" connection hint is translated")
		for button in [panel.copy_button,panel.copy_direct_button,panel.copy_internet_button]:
			var width := UiArt.FONT.get_string_size(L.text(button.text),HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
			check(width<=button.size.x-16,locale+" copy label fits its existing button width")
		await capture(locale+"-lan-and-internet-lobby-fixture")
	L.set_locale("de",false)
	game.network.internet_code = ""
	panel._refresh()
	check(not panel.copy_internet_button.visible,"Internet action disappears as soon as its invitation is unavailable")
	var long_hint := "Vollständiger Hinweis ".repeat(12)+"ENDE"
	game.network.connection_hint = long_hint
	check(panel._connection_hint_text()==long_hint,"Connection hints are not truncated before translation and wrapping")
	game.network.connection_hint = "Im selben Netzwerk bereit. Routerfreigabe nicht angefordert."

	panel._start()
	check(game.network.starts==0,"Host cannot start without the second participant")
	panel._select("ivo")
	check(game.selected_characters==["ivo","branko"] and game.network.commands[-1].kind=="character","Host changes only their own character and synchronizes selection")
	game.network.peer_connected = true
	panel._refresh()
	check(not panel.start_button.disabled and not panel.scene_button.disabled,"Connected host can select a world and start")
	panel.scene_button.pressed.emit()
	check(hud.overlay=="scenario" and hud.selection_count==2,"Online host reuses the existing scenario chooser for two players")
	hud.overlay = "network"
	panel._start()
	check(game.network.starts==1,"Explicit host start calls the shared match API exactly once")
	await capture("de-lan-partner-connected-fixture")
	panel._saved_available=true
	panel._refresh()
	check(panel.resume_button.visible and not panel.resume_button.disabled and not panel.resume_button.get_rect().intersects(panel.start_button.get_rect()),"Saved host campaign has separate new-session and continuation buttons")
	for locale in ["de","en"]:
		L.set_locale(locale,false)
		panel.refresh_locale()
		for button in [panel.start_button,panel.resume_button]:
			var width:=UiArt.FONT.get_string_size(L.text(button.text),HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
			check(width<=button.size.x-16,locale+" saved-session action fits its button")
		await capture(locale+"-saved-campaign-lobby-fixture")
	game.selected_characters=["ivo","branko","mara","ivo"]
	game.network.fixture_slots=[1,2,3,4]
	for locale in ["de","en"]:
		L.set_locale(locale,false)
		panel.refresh_locale()
		check(panel._member_count()==4 and panel._capacity()==4 and panel.capacity_button.disabled==false,locale+" host lobby shows four independent crew slots")
		await capture(locale+"-four-player-lobby-fixture")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
			var rendered:=SubViewport.new()
			rendered.size=Vector2i(2560,1440)
			rendered.size_2d_override=Vector2i(1600,900)
			rendered.size_2d_override_stretch=true
			rendered.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			root.add_child(rendered)
			game.reparent(rendered)
			panel.position=Vector2(80,0)
			await capture(locale+"-four-player-lobby-qhd-fixture",rendered)
			check(rendered.get_texture().get_image().get_size()==Vector2i(2560,1440),locale+" QHD fixture is rendered at native2560x1440")
			game.reparent(root)
			panel.position=Vector2.ZERO
			rendered.queue_free()
	game.selected_characters=["ivo","branko"]
	game.network.fixture_slots=[]
	panel.resume_button.pressed.emit()
	check(game.network.resumes==1,"Continue invokes the production session continuation action")
	L.set_locale("de",false)
	game.network.leave()
	var full_invitation := JoinCode.invite("192.168.1.25",JoinCode.DEFAULT_PORT,"23456789ABCDEFGH")
	panel.code_field.text = full_invitation
	check(panel.code_field.text==full_invitation and panel.code_field.max_length>=full_invitation.length(),"Join field preserves all twenty-four symbols and separators when pasted")
	var custom_port_invitation := JoinCode.invite("192.168.1.25",28942,"23456789ABCDEFGH")
	panel.code_field.text = custom_port_invitation
	check(panel.code_field.text==custom_port_invitation,"Join field also preserves a full direct invitation with a custom port")
	panel.code_field.text = full_invitation
	for locale in ["en","de"]:
		L.set_locale(locale,false)
		panel.refresh_locale()
		check(panel.code_field.text==full_invitation,"Changing language retains the complete pasted invitation")
	panel.restore_connection_preferences({"server":""})
	panel._join()
	check(not panel.resume_button.visible,"Guest cannot see the host-only continuation action")
	check(game.network.room_code==full_invitation and game.network.local_player_id==2,"Full direct invitation reaches the join API unchanged")
	check(game.network.requested_url.is_empty(),"A full direct invitation keeps its encoded route despite the new online default")
	panel._select("mara")
	check(game.selected_characters==["ivo","mara"],"Guest selection changes P2 while preserving P1")
	check(panel.start_button.disabled and panel.scene_button.disabled,"Guest cannot start or replace the host's scenario")
	panel._start()
	check(game.network.starts==1,"Guest cannot bypass the disabled start button")
	for locale in ["de","en"]:
		L.set_locale(locale,false)
		for phase in ["connecting","lobby","reconnecting"]:
			game.network.active=true
			game.network.state=phase
			game.network._authenticated=false
			game.network.peer_connected=phase!="connecting"
			game.network.fixture_slots=[1,2]
			game.network.connection_hint="Direkte Verbindung zum Gastgeber wird aufgebaut."
			game.network.relay_url=""
			panel.server_field.text="wss://stale-preference.example/ws"
			panel._refresh()
			check(panel._member_count()==0 and panel.crew_status()==("Verbindung noch nicht bestätigt" if locale=="de" else "Connection not yet confirmed"),locale+" "+phase+" cannot count a cached host or provisional local seat")
			check(panel.crew_buttons.all(func(button): return button.disabled) and not panel.crew_rows[1].connected,locale+" "+phase+" roster is noninteractive before the welcome")
			check(panel.crew_buttons[0].text==L.text("Gastgeber wird verbunden …") and panel.crew_buttons[1].text==L.text("Dein Platz wird bestätigt …"),locale+" "+phase+" describes the two pending seats honestly")
			check(not panel.copy_button.visible and panel.character_buttons.all(func(button): return button.disabled) and panel.start_button.disabled,locale+" "+phase+" cannot offer room sharing, character changes or match start")
			var commands_before: int=game.network.commands.size()
			panel._select("ivo");panel._open_member(1)
			check(game.network.commands.size()==commands_before and not panel.member_menu.visible,locale+" "+phase+" callbacks cannot act on an unauthenticated host")
			check(panel.connection_route_text()==L.text("Direkte Verbindung"),locale+" "+phase+" route follows the actual direct session rather than the stale server field")
			check(panel.leave_button.text==L.text("Abbrechen") and not panel.code_field.editable,locale+" "+phase+" permits cancellation while keeping the active join fields fixed")
		game.network._short_resolution="lookup-pending"
		panel._refresh()
		check(panel.connection_route_text()==L.text("Verbindungsweg wird ermittelt …"),locale+" short-code lookup does not invent a connection route")
		game.network._short_resolution=""
		game.network.state="error";game.network.active=true
		game.network.error_message="Bitte den vollständigen Beitrittscode eingeben."
		panel._refresh()
		check(panel._member_count()==0 and panel.crew_status()==L.text("Kein aktiver Raum") and panel.crew_buttons.all(func(button):return button.disabled),locale+" failed join never reports one connected host")
		check(panel._connection_hint_text().is_empty(),locale+" an unrelated join error cannot retain an old connection-in-progress hint")
		game.network.error_message="Der Gastgeber konnte nicht kontaktiert werden."
		check(panel._connection_hint_text()==L.text("Der Gastgeber kann einen neuen Online-Raum über Relay erstellen. Direkte Internetverbindungen benötigen eine Router-Freigabe."),locale+" unreachable direct host has an actionable relay/router hint")
		check(not panel.connection_mode_button.disabled,locale+" failed join unlocks explicit mode selection for the next attempt")
		panel.restore_connection_preferences({"server":""});panel._toggle_connection_mode()
		check(panel.direct_mode and panel.server_field.text.is_empty(),locale+" a failed relay/direct attempt can explicitly select LAN for a new room")
		panel._toggle_connection_mode()
		check(not panel.direct_mode and panel.server_field.text=="wss://bunkercrew.vibechain.rocks/ws",locale+" a failed attempt can explicitly return to the online default")
		game.network.active=false;panel._refresh()
		check(panel._member_count()==0 and panel.crew_status()==L.text("Kein aktiver Raum"),locale+" inactive final failure also cannot count a cached host")
	game.network.active=true;game.network.state="lobby";game.network.peer_connected=true;game.network._authenticated=true
	game.network.fixture_slots=[1,2]
	panel._refresh()
	check(panel._member_count()==2 and not panel.crew_buttons[0].disabled and not panel.character_buttons[0].disabled,"Only an authenticated welcome enables the actual guest roster and character selection")
	game.network.fixture_slots=[]
	game.network.state = "reconnecting"
	panel._refresh()
	check(panel.character_buttons[0].disabled and panel.start_button.disabled,"Reconnection disables stale lobby actions")
	check(not panel.server_field.editable and not panel.public_address_field.editable and not panel.code_field.editable,"Reconnecting keeps all connection fields read-only")
	L.set_locale("en",false)
	check(panel._status_text()=="Connection lost. Reconnecting …","Reconnection status is translated")
	game.network.state = "error"
	game.network.error_message = "Bitte den vollständigen Beitrittscode eingeben."
	check(panel._status_text()=="Enter the complete join code.","Connection errors are translated before wrapping")
	check(panel._connection_hint_text().is_empty(),"Invalid-code errors suppress stale connecting hints without unrelated router advice")
	L.set_locale("de",false)
	game.started = true
	panel._leave()
	check(not game.network.active and game.restarts==1 and hud.overlay=="menu","Leaving a live session disconnects then returns to a clean menu")
	paused = false
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("NETWORK LOBBY: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func capture(label: String,rendered: Viewport=null) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/network"))
	var target: Viewport=rendered if rendered!=null else root
	target.get_texture().get_image().save_png("res://artifacts/network/"+label+".png")
