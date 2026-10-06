extends "res://tests/online_ui_review_test.gd"
## Real paused Aschewerk and chat signal delivery; session is an offline probe.
const FEED_OUTPUT := "res://artifacts/hardening-followup/online-ui/pause-chat/"

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	AudioServer.set_bus_mute(0,true)
	view=SubViewport.new();view.size=Vector2i(1440,900);view.size_2d_override=Vector2i(1440,900);view.size_2d_override_stretch=true;view.gui_embed_subwindows=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;view.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate();view.add_child(game);await frames(6)
	actual_network=game.network;actual_social=game.social
	game.audio.persistence_enabled=false;game.combat_events.persistence_enabled=false;game.campaign.persistence_enabled=false
	game.start_scenario(2,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running=false;game.rounds.set_process(false);game.story.set_process(false)
	await frames()
	paused=true
	session=CrewSession.new();view.add_child(session);game.network=session
	host(2);session.state="playing";session.match_paused=true
	var chat: Control=game.hud.chat_panel
	chat.bind_network(session);chat.feed_visible=true
	game.hud.overlay="pause";game.hud.last_overlay="!";await frames()
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	var observations: Array[Dictionary]=[]
	for resolution in [Vector2i(960,600),Vector2i(1440,900)]:
		view.size=resolution
		for locale: String in ["de","en"]:
			L.set_locale(locale,false);game.hud._locale_changed(locale);await frames()
			chat._feed.clear();session.chat_history.clear()
			for id in range(1,5):
				var row := {"id":id,"player_id":2,"name":"Alex Ω","text":"We keep the machines supplied and defend the bunker together. Bring the spare steel from the depot; the next wave is almost here. Message %d."%id,"preset":"","time":145.0,"private":false}
				session.chat_history.append(row);session.chat_received.emit(row)
			await frames()
			var visible: Array=chat._visible_feed() if chat.has_method("_visible_feed") else chat._feed
			var bottom: float=game.hud.screen_rect().position.y+56.0
			for entry: Dictionary in visible: bottom+=34+mini(2,entry.lines.size())*16+6
			var collision := bottom>200
			check(game.hud.overlay=="pause" and chat.available() and not chat.composing,"Prepared real online pause renders an available chat feed")
			check(session.chat_history.size()==4 and chat._feed.size()==4,"All four delivered messages remain in complete history and feed storage")
			if baseline:
				check(collision,"Baseline reproduces feed coverage of the shift heading")
			else:
				check(not collision and visible.size()==2,"Long pause feed remains entirely above the shift heading")
				check(int(visible[0].row.id)==3 and int(visible[1].row.id)==4,"Pause presents the newest two delivered messages")
				game.hud.overlay="network";await frames()
				check(chat._visible_feed().size()==4,"Outside pause the full live feed remains available")
				game.hud.overlay="pause";await frames()
			observations.append({"resolution":[resolution.x,resolution.y],"locale":locale,"visible_messages":visible.size(),"feed_bottom_logical":bottom,"shift_heading_logical":212,"overlaps_shift_heading":collision})
			if "--capture" in OS.get_cmdline_user_args(): await capture("before" if baseline else "after",false,FEED_OUTPUT)
	game.network=actual_network;game.social=actual_social;chat.bind_network(actual_network)
	check(not actual_network.active and not game.microphone.capturing,"The real transport and microphone remain inactive")
	check(await Cleanup.free_scene(game,self),"Prepared paused scene releases all audio and world nodes")
	view.queue_free();await frames()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FEED_OUTPUT))
	var report := "baseline" if baseline else "native" if "--capture" in OS.get_cmdline_user_args() else "headless"
	FileAccess.open(FEED_OUTPUT+report+"-verification.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"captures":captures,"prepared_states":"Actual paused two-player Aschewerk, real chat_received signal, four long messages, explicit offline session probe, no sockets/profile writes."},"\t"))
	print("PAUSE CHAT FEED: %d/%d checks passed"%[checks-failures,checks]);quit(1 if failures else 0)
