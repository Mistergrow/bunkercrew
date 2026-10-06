extends SceneTree
## Actual scenes, campaign selection, workers, NPCs and physical field records.
## Ancestors/materials/wave endpoints are prepared; this is not a 240-wave run.
const Catalog := preload("res://scripts/solo_story_catalog.gd")
const Find := preload("res://scripts/solo_story_find.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game: Node
var checks := 0
var failures := 0
var summaries: Array[Dictionary] = []

class ForeignWorker extends Node2D:
	var game: Node
	func can_act() -> bool: return true

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 3) -> void:
	for unused in count: await process_frame

func _close_reader() -> void:
	game.hud.overlay = ""
	paused = false
	game.hud._process(0.0)
	await frames()

func _prepare(site: String) -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(5)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.solo_story.records.persistence_enabled = false
	game.network.set_process(false)
	game.social_bridge.set_process(false)
	var options := {"environment":str(CampaignCatalog.node(site).environment),"build_type":"bastion","position":"center"}
	check(game.campaign.begin_new(options,["mara"],1), site+": prepare a genuine unsaved campaign")
	# A completed-parent fixture authorizes this mission; future/optional sites
	# remain unreached. Its claims, currency and snapshot are internally valid.
	var parent := str(CampaignCatalog.node(site).parent)
	while not parent.is_empty():
		game.campaign.completed.push_front(parent)
		parent = str(CampaignCatalog.node(parent).parent)
	for id: String in game.campaign.completed:
		game.campaign.claimed_missions.append(game.campaign.campaign_id+":"+id)
	if not game.campaign.completed.is_empty(): game.campaign.current_node = str(game.campaign.completed[-1])
	game.campaign.total_salvage_earned = 30
	game.campaign.banked_salvage = 30
	if int(CampaignCatalog.node(site).cost) > 0:
		check(game.campaign.unlock_route(site), site+": use genuine optional-route authorization")
	check(game.campaign.select_destination(site) and not game.campaign.mission_start().is_empty(), site+": select and start the actual mission")
	game.story_mode = true
	game.start_scenario(1,options)
	game.rounds.running = false
	game.rounds.set_process(false)
	game.solo_story.set_process(false)
	game.story.set_process(false)
	game.expedition.set_process(false)
	game.set_process(false)
	for node: Node in game.find_children("*","Node",true,false): node.set_physics_process(false)
	game.rounds.phase = "build"
	game.rounds.wave = 1
	if not game.campaign.completed.is_empty():
		game.campaign.snapshots = {"1":CampaignBonus.snapshot_player(game.players[0])}
	await frames()
	check(CampaignState.valid_checkpoint(game.campaign.checkpoint()), site+": prepared route is a genuinely valid campaign checkpoint")
	check(game.solo_story.enabled and game.solo_story.site_id() == site, site+": real solo director attaches to its own campaign")
	check((site == CampaignCatalog.ENTRY) == game.story.enabled, site+": only entry owns the original tutorial wall/relay")
	check(game.solo_story.records.visited == [site] and str(Catalog.chapter(site).arrival_id) in game.solo_story.records.events, site+": actual scene arrival records only this chapter")
	check(game.solo_story.finds.size() == 2, site+": actual world creates its two authored finds")
	check(game.solo_story.npcs.size() == Catalog.profiles().filter(func(person: Dictionary) -> bool: return str(person.site) == site).size(), site+": only the actually authored survivor appears")
	check(not game.network.active and not game.microphone.capturing, site+": story starts no transport or microphone")

func _finds(site: String) -> void:
	var worker: Worker = game.players[0]
	var foreign := ForeignWorker.new()
	foreign.game = game
	game.add_child(foreign)
	var campaign_before: Dictionary = game.campaign.checkpoint()
	var inventory_before: Dictionary = worker.inventory.duplicate(true)
	var upgrade_before: Array = game.upgrades.owned.keys()
	for id: String in Catalog.chapter(site).find_ids:
		var find: Node2D = game.solo_story.finds[id]
		check(find.is_in_group("interactables") and find.is_in_group("solo_story_finds"), site+": authored find is a physical selectable object")
		worker.position = find.position+Vector2(200,0)
		check(not find.interact(worker,0.0) and id not in game.solo_story.records.events, site+": remote find is not awarded")
		worker.position = find.position+Vector2(12,0)
		foreign.position = worker.position
		check(not game.solo_story.read_find(id,foreign,find), site+": foreign actor cannot read a local find")
		check(not game.solo_story.read_find("unknown",worker,find), site+": invalid find ID cannot alias a real record")
		find.visible = false
		check(not find.interact(worker,0.0) and not game.solo_story.read_find(id,worker,find), site+": hidden object cannot open a reader")
		find.visible = true
		worker.hurt_stun = 1.0
		check(not find.interact(worker,0.0), site+": an incapacitated worker cannot read a find")
		worker.hurt_stun = 0.0
		var counterfeit := Find.new()
		counterfeit.game = game
		counterfeit.director = game.solo_story
		counterfeit.entry_id = id
		counterfeit.site_id = site
		counterfeit.position = find.position
		game.add_child(counterfeit)
		check(not game.solo_story.read_find(id,worker,counterfeit), site+": duplicate object without controller ownership is refused")
		counterfeit.queue_free()
		if site == CampaignCatalog.ENTRY and id == str(Catalog.chapter(site).find_ids[0]):
			worker.preferred_focus = find
			worker._update_interaction(0.0)
			var press := InputEventKey.new()
			press.physical_keycode = KEY_E
			press.keycode = KEY_E
			press.pressed = true
			Input.parse_input_event(press)
			await frames(1)
			worker._update_interaction(1.0/60.0)
			check(id in game.solo_story.records.events and game.hud.overlay == "story_journal", site+": genuine E key opens its selected native reader")
			await _close_reader()
			worker._update_interaction(1.0/60.0)
			check(game.hud.overlay.is_empty(), site+": keeping E held cannot reopen a closed reader")
			press.pressed = false
			Input.parse_input_event(press)
			worker._update_interaction(0.0)
			check(id in game.solo_story.records.events, site+": actual E event passes through the real worker interaction route")
			check(find.interact(worker,0.0), site+": release allows an intentional later reread")
		else:
			check(find.interact(worker,0.0), site+": nearby worker reads the actual visible object")
		check(id in game.solo_story.records.events and game.hud.overlay == "story_journal" and paused, site+": physical read writes the exact entry and opens native journal")
		check(str(game.hud.solo_story_navigation.get("entry","")) == id, site+": reader is directed to the exact found record")
		var previous: Dictionary = game.solo_story.records.capture()
		check(not find.interact(worker,0.0) and game.solo_story.records.capture() == previous, site+": open reader blocks another interaction")
		await _close_reader()
		check(find.interact(worker,0.0) and game.solo_story.records.capture() == previous, site+": rereading is allowed without duplicate journal entries")
		await _close_reader()
	check(game.campaign.checkpoint() == campaign_before and worker.inventory == inventory_before and game.upgrades.owned.keys() == upgrade_before, site+": finds grant no resources, XP, research or mission rewards")
	var queued: Worker = game.PLAYER.instantiate()
	queued.game = game
	queued.player_id = 1
	queued.position = worker.position
	game.add_child(queued)
	game.players.append(queued)
	queued.queue_free()
	var last_id := str(Catalog.chapter(site).find_ids[-1])
	check(not game.solo_story.read_find(last_id,queued,game.solo_story.finds[last_id]), site+": a queued own worker cannot perform a final read")
	game.players.erase(queued)
	foreign.queue_free()

func _waves(site: String) -> void:
	var director: Node = game.solo_story
	if CampaignCatalog.site_kind(site) == "outpost":
		game.rounds.phase = "attack"
		director._process(0.21)
		check(site+":guards_clear" in director.records.events, site+": actual zero-guard outpost records clearing before objective handover")
		check(str(Catalog.chapter(site).completion_id) not in director.records.events, site+": guard clearing does not forge a secured site")
		return
	game.rounds.wave = 3
	game.rounds.phase = "build"
	director._process(0.21)
	check(director._cleared_wave == 2 and site+":wave_3" not in director.records.events, site+": wave-three build does not claim three repelled waves")
	game.rounds.phase = "salvage"
	var blocker: Node2D = game.ENEMY.instantiate()
	blocker.game = game
	blocker.position = Vector2(game.world_right-30,430)
	game.add_child(blocker)
	blocker.set_physics_process(false)
	director._process(0.21)
	check(site+":wave_3" not in director.records.events, site+": a real living enemy blocks false cleared-wave narrative")
	blocker.queue_free()
	await frames()
	director._process(0.21)
	check(director._cleared_wave == 3 and site+":wave_3" in director.records.events, site+": actual zero-enemy salvage endpoint records wave three")
	var count: int = director.records.events.size()
	director._process(0.21)
	check(director.records.events.size() == count, site+": repeated process callbacks do not duplicate the milestone")

func _npc(site: String, profile: Dictionary) -> void:
	var worker: Worker = game.players[0]
	var director: Node = game.solo_story
	var id := str(profile.id)
	var already_unlocked := CharacterCatalog.is_unlocked(id)
	var npc: Node2D = director.npcs[id]
	check(npc.character_id == id and npc.site_id == site and npc.is_in_group("solo_story_npcs"), id+": genuine visible survivor exists at the authored site")
	var foreign := ForeignWorker.new()
	foreign.game = game
	game.add_child(foreign)
	foreign.position = npc.position
	check(not director.open_encounter(id,foreign,npc), id+": foreign worker cannot contact an NPC")
	worker.position = npc.position+Vector2(200,0)
	check(not npc.interact(worker,0.0) and not director.open_encounter(id,worker,npc), id+": contact requires physical proximity")
	worker.position = npc.position+Vector2(12,0)
	npc.visible = false
	check(not director.open_encounter(id,worker,npc), id+": direct controller contact also requires a visible NPC")
	npc.visible = true
	check(not director.open_encounter("unknown",worker,npc), id+": unknown identity cannot substitute a real survivor")
	worker.inventory.clear()
	game.rounds.phase = "attack" if CampaignCatalog.site_kind(site) == "outpost" else "build"
	check(npc.interact(worker,0.0) and id in director.records.met, id+": genuine close interaction records explicit contact")
	if already_unlocked:
		check(director.encounter_view().can_recruit, id+": a known starter can confirm contact without paying a rescue cost")
	else:
		check(not director.recruit(id) and not CharacterCatalog.is_unlocked(id), id+": missing carried job materials cannot unlock a character")
	for kind: String in profile.cost: worker.inventory[kind] = int(profile.cost[kind])+1
	var blocker: Node2D = game.ENEMY.instantiate()
	blocker.game = game
	blocker.position = npc.position+Vector2(250,0)
	game.add_child(blocker)
	blocker.set_physics_process(false)
	var before: Dictionary = worker.inventory.duplicate()
	check(not director.recruit(id) and worker.inventory == before and CharacterCatalog.is_unlocked(id)==already_unlocked, id+": actual nearby threat blocks admission without consuming costs or changing entitlement")
	blocker.queue_free()
	await frames()
	var campaign_before: Dictionary = game.campaign.checkpoint()
	check(director.recruit(id), id+": safe authored job with exact carried resources admits the real crew member")
	check(CharacterCatalog.is_unlocked(id) and id in director.records.recruited and str(profile.rescue_id) in director.records.events, id+": entitlement, journal and personal rescue record agree")
	for kind: String in profile.cost: check(int(worker.inventory[kind]) == (int(profile.cost[kind])+1 if already_unlocked else 1), id+": a known starter keeps materials; a first rescue consumes the authored cost once")
	check(game.campaign.checkpoint() == campaign_before and game.players.size() == 1, id+": rescue creates no extra worker or mission reward")
	before = worker.inventory.duplicate()
	check(not director.recruit(id) and worker.inventory == before, id+": repeated admission cannot charge resources twice")
	await _close_reader()
	check(npc.interact(worker,0.0) and str(profile.after_id) in director.records.events, id+": later physical conversation records the authored follow-up")
	await _close_reader()
	foreign.queue_free()

func _mode_guards(site: String) -> void:
	var director: Node = game.solo_story
	var before: Dictionary = director.records.capture()
	game.story_mode = false
	check(director.wants_campaign(game.campaign), site+": same-campaign sidecar resumes solo story without needing a session preference")
	var another := CampaignState.new("",false)
	check(another.begin_new(game.scenario_options,["mara"],1) and not director.wants_campaign(another), site+": unrelated free campaign does not inherit this story session")
	game.player_count = 2
	check(not director.offline_solo() and not director.wants_campaign(game.campaign), site+": local multiplayer has no solo story authority")
	game.player_count = 1
	game.network.active = true
	game.network.state = "lobby"
	check(not director.offline_solo() and not director.wants_campaign(game.campaign), site+": online state cannot admit local-only NPCs or finds")
	game.network.active = false
	game.network.state = "offline"
	check(director.records.capture() == before, site+": gating queries never mutate narrative records")
	var chapter := Catalog.chapter(site)
	director.site_secured(site)
	check(str(chapter.completion_id) not in director.records.events, site+": unsecured mission cannot emit a conclusion")
	var claim: Dictionary
	if CampaignCatalog.site_kind(site) == "outpost":
		claim = game.campaign.complete_outpost(game.campaign.mission_id,0,true,game.players,game.upgrades,{})
	else:
		claim = game.campaign.complete_mission(game.campaign.mission_id,Balance.TOTAL_WAVES,game.players,game.upgrades,{})
	check(not claim.is_empty() and CampaignState.valid_checkpoint(game.campaign.checkpoint()), site+": actual finite mission-completion API produces a valid secured ledger")
	director.site_secured(site)
	check(str(chapter.completion_id) in director.records.events, site+": verified completed site gets its exact conclusion")
	var count: int = director.records.events.size()
	director.site_secured(site)
	check(director.records.events.size() == count, site+": repeated mission callback preserves exactly-once narrative")
	if site == "mountain_pass":
		var journal: Array = director.journal_entries()
		var pass_entries: Array = journal.filter(func(row: Dictionary) -> bool: return str(row.id) == "mountain_pass")
		check(pass_entries.size() == 1 and pass_entries[0].details.any(func(row: Dictionary) -> bool: return str(row.get("id","")) == "main_route"), "Eight verified main-site records expose the route ending without claiming optional archives")
		var before_ending: Dictionary = director.records.capture()
		director.journal_entries()
		check(director.records.capture() == before_ending, "Reading the ending grants no journal state, mission rewards or rescued people")

func _completed_contact_resume() -> void:
	CrewRoster.unlocked.clear()
	await _prepare("quarry")
	var worker: Worker = game.players[0]
	var director: Node = game.solo_story
	var npc: Node2D = director.npcs.oskar
	worker.position = npc.position+Vector2(12,0)
	worker.inventory.clear()
	check(npc.interact(worker,0.0), "Prepare genuine Oskar contact before leaving the secured site")
	await _close_reader()
	var completed: Dictionary = game.campaign.complete_mission(game.campaign.mission_id,Balance.TOTAL_WAVES,game.players,game.upgrades,{})
	check(not completed.is_empty() and CampaignState.valid_checkpoint(game.campaign.checkpoint()), "A prepared defended endpoint produces a real valid garage checkpoint")
	var preferences: Dictionary = game.session_preferences()
	var checkpoint: Dictionary = game.campaign.checkpoint()
	check("oskar" in preferences.solo_story.met and "oskar" not in preferences.solo_story.recruited, "Session preferences preserve contact separately from an unfinished job")
	await _dispose()
	for mode: String in ["preparation","map"]:
		game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		await frames(5)
		game.audio.persistence_enabled = false
		game.combat_events.persistence_enabled = false
		game.campaign.persistence_enabled = false
		game.solo_story.records.persistence_enabled = false
		game.restore_session_preferences(preferences)
		check(game.solo_story.records.capture() == preferences.solo_story and not game.story_mode, mode+": scene handoff restores the exact in-memory story sidecar")
		var payload_checkpoint: Dictionary = checkpoint.duplicate(true)
		payload_checkpoint.expedition.stage = mode
		var payload := {"checkpoint":payload_checkpoint,"mode":"preparation","options":ScenarioCatalog.validate({"environment":"basalt_quarry","build_type":"bastion","position":"center"})}
		check(game.expedition.restore(payload), mode+": genuine expedition restore accepts the valid garage checkpoint")
		game.rounds.set_process(false)
		game.solo_story.set_process(false)
		game.story.set_process(false)
		game.expedition.set_process(false)
		game.network.set_process(false)
		game.social_bridge.set_process(false)
		game.set_process(false)
		for node: Node in game.find_children("*","Node",true,false): node.set_physics_process(false)
		await _close_reader()
		director = game.solo_story
		check(director.enabled and game.story_mode and not game.story.enabled and director._cleared_wave == Balance.TOTAL_WAVES, mode+": completed-site restore retains solo chapter without repeating the tutorial")
		check(director.npcs.has("oskar") and director.finds.size() == 2, mode+": restored garage physically preserves its unfinished contact and finds")
		npc = director.npcs.oskar
		worker = game.players[0]
		worker.position = npc.position+Vector2(12,0)
		worker.inventory.clear()
		worker.inventory.concrete = 2
		var already: bool = CharacterCatalog.is_unlocked("oskar")
		check(npc.interact(worker,0.0) and director.encounter_view().can_recruit, mode+": secured-site safe contact does not require defending its waves again")
		var before: Dictionary = game.campaign.checkpoint()
		if not already:
			var roster_path := CrewRoster.save_path
			CrewRoster.save_path = "res://artifacts/solo-story/runtime/absent-%d/crew.cfg" % OS.get_process_id()
			CrewRoster.persistence_enabled = true
			check(not director.recruit("oskar") and not CharacterCatalog.is_unlocked("oskar") and int(worker.inventory.concrete) == 2, "Failed durable roster commit preserves every carried job material")
			CrewRoster.persistence_enabled = false
			CrewRoster.save_path = roster_path
			var narrative_before: Dictionary = director.records.capture()
			var narrative_path: String = director.records.save_path
			director.records.save_path = "res://artifacts/solo-story/runtime/absent-%d/story.json" % OS.get_process_id()
			director.records.persistence_enabled = true
			check(director.recruit("oskar") and CharacterCatalog.is_unlocked("oskar") and int(worker.inventory.get("concrete",0)) == 0, "Failed narrative write retains the successfully admitted entitlement and its one real cost")
			check(director.records.capture() == narrative_before, "Failed optional sidecar transaction rolls back only uncommitted narrative fields")
			director.records.persistence_enabled = false
			director.records.save_path = narrative_path
		check(director.recruit("oskar") and "oskar" in director.records.recruited and str(Catalog.profile("oskar").rescue_id) in director.records.events, mode+": actual restored contact records personal recruitment")
		check(int(worker.inventory.get("concrete",0)) == (2 if already else 0), mode+": cross-scene confirmation charges only the first durable entitlement")
		check(game.campaign.checkpoint() == before, mode+": later contact does not repeat the mission's resource or blueprint reward")
		await _dispose()
	CrewRoster.unlocked.clear()

func _dispose() -> void:
	game.network.active = false
	paused = false
	check(await Cleanup.free_scene(game,self), "Actual scene and audio handles release after each chapter fixture")
	game = null

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	root.size = Vector2i(1440,900)
	AudioServer.set_bus_mute(0,true)
	CrewRoster.persistence_enabled = false
	CrewRoster._loaded = true
	CrewRoster.unlocked.clear()
	LocaleText.set_locale("de",false)
	for location: Dictionary in CampaignCatalog.NODES:
		var site := str(location.id)
		await _prepare(site)
		# Outpost guard elimination is a prepared endpoint. No guards are silently
		# credited as kills, loot, XP or an objective victory by this fixture.
		for enemy: Node in get_nodes_in_group("enemies"):
			if enemy.get("game") == game: enemy.queue_free()
		await frames()
		await _finds(site)
		await _waves(site)
		for profile: Dictionary in Catalog.profiles():
			if str(profile.site) == site: await _npc(site,profile)
		_mode_guards(site)
		summaries.append({"site":site,"events":game.solo_story.records.events.duplicate(),"met":game.solo_story.records.met.duplicate(),"recruited":game.solo_story.records.recruited.duplicate()})
		await _dispose()
	await _completed_contact_resume()
	CrewRoster.unlocked.clear()
	var report := {"checks":checks,"failures":failures,"chapters":summaries,"prepared_states":["Actual main scenes and genuine route/mission APIs; completed ancestors, consistent claims/currency and real worker snapshots form valid checkpoints independently per chapter.","Round spawning/physics is paused; wave build/salvage endpoints and a genuine living blocker validate controller provenance.","Outpost guards are removed as a prepared cleared endpoint; the test claims no real combat victory, kill, loot or XP.","End-of-mission wave20/outpost objective evidence is deliberately provided to genuine completion APIs; this does not claim a full combat playthrough.","Five personal job costs are explicitly put in the worker inventory; nearby NPC/find interactions and real roster admits run unchanged.","The entry find additionally uses a native E key event and real Worker._update_interaction; closing while held cannot reopen it.","Exact in-memory session preferences and valid expedition checkpoint restore preparation/map worlds; later recruitment, failed durable writes and retry costs are tested through production APIs.","One isolated unsaved process, no transport/UPnP/microphone, muted master; scenes retired through SceneCleanup."],"limits":["This is a controller/world regression, not a complete 240-wave playthrough, rendered gallery or performance benchmark."]}
	var output_path := "res://artifacts/solo-story/runtime/runtime-test.json"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))==OK,"Clean checkout can create its runtime report directory")
	var output := FileAccess.open(output_path,FileAccess.WRITE)
	check(output!=null,"Runtime report file opens in a clean checkout")
	if output!=null: output.store_string(JSON.stringify(report,"\t"))
	print("Solo story runtime: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
