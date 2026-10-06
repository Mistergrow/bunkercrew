extends SceneTree
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Session := preload("res://scripts/network_session.gd")
const PeerState := preload("res://scripts/network_peer_state.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const Registry := preload("res://scripts/content_registry.gd")
const Roster := preload("res://scripts/crew_roster.gd")
var checks := 0
var failures := 0

class LobbyHud extends RefCounted:
	var scenario_options := ScenarioCatalog.validate({})
	var story_selected := false

class LobbyWorld extends Node:
	var selected_characters: Array[String] = ["mara","branko","ivo","nora"]
	var started := false
	var player_count := 1
	var hud := LobbyHud.new()
	var voice: Node
	var social: Node
	var notifications: Array[String] = []
	func notify(message: String) -> void: notifications.append(message)

class SessionProbe extends Session:
	var packets: Array[Dictionary] = []
	func _send(message: Dictionary,reliable := true,target_id: int=0) -> bool:
		packets.append({"message":Protocol.decode(Protocol.encode(message)),"reliable":reliable,"target":target_id})
		return not packets.back().message.is_empty()

func _initialize() -> void: run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("CHARACTER PARTY FAIL: "+label)

func link(session: SessionProbe,slot: int,authenticated: bool=true) -> void:
	var state: Dictionary = PeerState.create(0.0)
	state.slot = slot
	state.wire = slot*101
	state._authenticated = authenticated
	session._slots[slot] = state
	session._peers[state.wire] = state

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless" or "--capture" not in OS.get_cmdline_user_args(): return
	for unused in 3: await process_frame
	await RenderingServer.frame_post_draw
	var folder := "res://artifacts/character-identity-20261005/party"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	check(root.get_texture().get_image().save_png(folder+"/"+label+".png")==OK,"native party capture saves")

func run() -> void:
	Roster.persistence_enabled = false
	Roster._loaded = true
	Roster.unlocked.clear()
	LocaleText.set_locale("de",false)
	var defaults := PartyConfig.unique_characters([])
	check(defaults==["mara","branko","ivo","nora"],"fresh profiles can fill all four slots with four different starters")
	for id: String in defaults: check(CharacterCatalog.is_unlocked(id),id+" is selectable before any rescue")
	for id: String in ["levin","selma","oskar","rika"]: check(not CharacterCatalog.is_unlocked(id),id+" retains its rescue entitlement")
	check(PartyConfig.unique_characters(["mara","mara","mara","mara"])==defaults,"an old duplicate lobby gets distinct new-match choices")
	check(PartyConfig.unique_characters(["mara","mara","branko","ivo"])==["mara","nora","branko","ivo"],"replacement reserves valid characters already chosen in later slots")
	check(PartyConfig.normalize_characters(["mara","mara","ivo","mara"])==["mara","mara","ivo","mara"],"raw saved-world normalization preserves old actor identities")
	check(PartyConfig.unique_characters(["rika","rika","selma","selma"])==["rika","mara","selma","branko"],"unique guest recruits survive while repeated choices get available starters")
	root.size = Vector2i(1440,900)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.combat_events.persistence_enabled = false
	game.selected_characters.assign(["mara","mara","ivo","mara"])
	game.hud._open_character_selection(4)
	for unused in 3: await process_frame
	var panel: CharacterSelectPanel = game.hud.character_panel
	check(game.selected_characters==defaults,"real local selection cleans a legacy lobby before a new game")
	panel.select_slot(0)
	panel.select_character("nora")
	check(game.selected_characters==["nora","branko","ivo","mara"],"selecting a teammate swaps both actual slots")
	panel.select_character("rika")
	check(game.selected_characters==["nora","branko","ivo","mara"],"local swap cannot grant a locked recruit")
	panel.set_player_count(2)
	panel.select_slot(1)
	panel.select_character("ivo")
	panel.set_player_count(4)
	check(game.selected_characters==["nora","ivo","branko","mara"],"shrinking and expanding the party preserves a unique set")
	await capture("selection-de")
	LocaleText.set_locale("en",false)
	panel._refresh()
	await capture("selection-en")
	panel.begin_session()
	for unused in 3: await physics_frame
	check(game.started and game.players.size()==4,"real four-player game starts from the new selection")
	var actor_ids: Array[String] = []
	for player: Worker in game.players:
		actor_ids.append(player.character_id)
		check(player.character_id not in actor_ids.slice(0,actor_ids.size()-1),"each spawned actor owns a different character")
	check(actor_ids==game.selected_characters,"spawned characters exactly match chosen slots")
	game.rounds.running = false
	await capture("four-player-game")
	await Cleanup.free_scene(game,self)
	LocaleText.set_locale("de",false)
	var world := LobbyWorld.new()
	var session := SessionProbe.new()
	world.add_child(session)
	session.game = world
	session.active = true
	session.is_host = true
	session.state = "lobby"
	session.set_process(false)
	root.add_child(world)
	link(session,2,false)
	link(session,3)
	world.selected_characters = ["mara","branko","nora","ivo"]
	check(session.character_owner("nora",1)==3,"sparse authenticated guest occupies its actual slot")
	check(session.character_owner("branko",1)==0,"an unauthenticated seat cannot reserve a character")
	check(session.character_owner("nora",3)==0,"a player can keep their own character")
	session._handle_command("character",{"id":"nora"},1)
	check(world.selected_characters==["mara","branko","nora","ivo"] and not world.notifications.is_empty(),"host cannot steal an authenticated teammate's identity")
	session._handle_command("character",{"id":"branko"},3)
	check(world.selected_characters[2]=="branko","guest can choose a free starter despite an unauthenticated seat")
	session._context_peer = 303
	session._handle_command("character",{"id":"mara"},3)
	check(world.selected_characters[2]=="branko","authoritative race rejection preserves the established owner")
	check(session.packets.any(func(packet): return packet.message.get("kind")=="notice" and packet.message.get("text")=="Diese Figur ist bereits in der Crew. Wähle eine andere."),"rejected guest receives a valid protocol notice")
	check(session.packets.back().message.get("kind")=="lobby" and session.packets.back().message.characters==world.selected_characters,"rejection sends the authoritative roster back to restore prediction")
	session._context_peer = 0
	session._handle_command("character",{"id":"oskar"},3)
	check(world.selected_characters[2]=="oskar" and not CharacterCatalog.is_unlocked("oskar"),"host preserves a guest's rescued identity without importing their entitlement")
	var before := world.selected_characters.duplicate()
	for invalid_slot in [-1,0,2,5]: session._handle_command("character",{"id":"rika"},invalid_slot)
	check(world.selected_characters==before,"out-of-range and unauthenticated slots cannot change the crew")
	session.state = "connecting"
	session._handle_command("character",{"id":"rika"},1)
	check(world.selected_characters==before,"character selection requires a confirmed lobby")
	session.state = "lobby"
	session._slots.erase(2)
	session._peers.erase(202)
	world.selected_characters[1] = "mara"
	session._invite_secret = "23456789ABCDEFGH"
	var newcomer: Dictionary = PeerState.create(0.0)
	newcomer.wire = 404
	session._peers[404] = newcomer
	session._enter_peer(404)
	session._accept_hello({"version":Protocol.VERSION,"build":Protocol.BUILD,"world_revision":Protocol.WORLD_REVISION,"content_fingerprint":Registry.fingerprint(),"invite":session._invite_secret,"resume":"","name":"New Guest"})
	session._leave_peer()
	check(session.is_player_connected(2) and world.selected_characters[1]=="branko","real hello assigns a free starter when a newly occupied slot had a duplicate")
	check(session.packets.any(func(packet): return packet.message.get("kind")=="welcome" and packet.message.get("player_id")==2 and packet.message.characters[1]=="branko"),"welcome announces the same unique character the host reserved")
	session._slots.clear()
	session._peers.clear()
	session.active = false
	await Cleanup.free_scene(world,self)
	print("CHARACTER PARTY IDENTITY: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
