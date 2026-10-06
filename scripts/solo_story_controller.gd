extends Node
## Solo-only authored encounters over real campaign progress. No network payloads,
## combat actors, free supplies or duplicate mission rewards are created here.
const Catalog := preload("res://scripts/solo_story_catalog.gd")
const Records := preload("res://scripts/solo_story_state.gd")
const Npc := preload("res://scripts/solo_story_npc.gd")
const Find := preload("res://scripts/solo_story_find.gd")
const Roster := preload("res://scripts/crew_roster.gd")
const L := preload("res://scripts/locale_text.gd")
const InputLabels := preload("res://scripts/input_labels.gd")
var game: Node
var enabled := false
var records := Records.new()
var npcs: Dictionary = {}
var finds: Dictionary = {}
var active_encounter := ""
var _encounter_worker: Node
var _encounter_npc: Node2D
var _clock := 0.0
var _cleared_wave := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	records.load_records()

func offline_solo() -> bool:
	return is_instance_valid(game) and game.player_count==1 and (not is_instance_valid(game.network) or not game.network.active)

func wants_campaign(state: CampaignState) -> bool:
	return offline_solo() and state.player_count==1 and state.active and (game.story_mode or records.matches(state.campaign_id))

func has_pending_recruits() -> bool:
	for profile: Dictionary in Catalog.PROFILES:
		if not CharacterCatalog.is_unlocked(str(profile.id)): return true
	return false

func site_id() -> String:
	if not is_instance_valid(game.campaign) or not game.campaign.active: return ""
	return str(game.campaign.pending_node) if game.expedition.stage=="defense" else str(game.campaign.current_node)

func begin() -> void:
	enabled = wants_campaign(game.campaign)
	active_encounter = ""
	_encounter_worker = null
	_encounter_npc = null
	npcs.clear()
	finds.clear()
	_cleared_wave = 0
	if not enabled: return
	game.story_mode = true
	if not records.begin(game.campaign.campaign_id):
		enabled = false
		game.notify(records.last_error)
		return
	if game.expedition.stage not in ["defense","preparation","map"]: return
	if site_id() in game.campaign.completed: _cleared_wave = Balance.TOTAL_WAVES
	_arrive(site_id())

func _arrive(site: String) -> void:
	if not CampaignCatalog.contains(site): return
	if not records.mark("visited",site):
		game.notify(records.last_error)
		return
	var chapter := Catalog.chapter(site)
	for index in chapter.find_ids.size():
		var find := Find.new()
		find.game = game
		find.director = self
		find.entry_id = str(chapter.find_ids[index])
		find.site_id = site
		find.variant = index
		var bunker = game.scenario_bunker
		find.position = Vector2(bunker.room_left+62.0 if index==0 else bunker.room_right-64.0,bunker.ground_y)
		game.add_child(find)
		finds[find.entry_id] = find
	for entry: Dictionary in Catalog.profiles():
		if str(entry.site)!=site: continue
		var npc := Npc.new()
		npc.game = game
		npc.director = self
		npc.character_id = str(entry.id)
		npc.site_id = site
		var bunker = game.scenario_bunker
		var left_side: bool = is_instance_valid(bunker) and bunker.position_mode=="right"
		var x: float = bunker.room_left-40.0 if left_side else bunker.room_right+40.0
		npc.position = Vector2(x,bunker.ground_y)
		npc.facing = 1.0 if left_side else -1.0
		game.add_child(npc)
		npcs[entry.id] = npc
	_emit("arrival")

func _process(delta: float) -> void:
	if not enabled or not offline_solo() or not game.started or game._restart_pending: return
	if get_tree().paused or not game.hud.overlay.is_empty(): return
	_clock += delta
	if _clock<.2: return
	_clock = 0.0
	if game.expedition.stage!="defense": return
	if _living_enemies()==0:
		if game.rounds.phase=="salvage":
			_cleared_wave = maxi(_cleared_wave,int(game.rounds.wave))
			_emit("wave_cleared",{"wave":int(game.rounds.wave)})
		elif game.rounds.phase=="build":
			_cleared_wave = maxi(_cleared_wave,int(game.rounds.wave)-1)
			_emit("wave_cleared",{"wave":_cleared_wave})
		if game.expedition.outpost_pending(): _emit("guards_cleared",{"enemies_remaining":0})

func _living_enemies() -> int:
	var count := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.get("game")==game and float(enemy.get("hp"))>0: count += 1
	return count

func relay_completed(stage: int) -> void:
	if enabled: _emit("relay_completed",{"relay_stage":stage})

func site_secured(site: String) -> void:
	if not enabled or site!=site_id() or site not in game.campaign.completed: return
	_emit("site_secured",{"completed":game.campaign.completed.duplicate()})

func _emit(event: String,context: Dictionary = {}) -> void:
	var site := site_id()
	if site not in records.visited: return
	var data := context.duplicate()
	data.completed = game.campaign.completed.duplicate()
	data.enemies_remaining = _living_enemies()
	data.phase = game.rounds.phase
	data.cleared_wave = _cleared_wave
	if not data.has("stage"): data.stage = game.expedition.stage
	for entry: Dictionary in Catalog.due(site,event,data):
		if str(entry.id) in records.events: continue
		if not records.mark("events",str(entry.id)):
			game.notify(records.last_error)
			return
		game.notify(L.format("Logbuch: %s · %s",[str(entry.title),InputLabels.menu(game,"story_journal")]))

func journal_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Dictionary in CampaignCatalog.NODES:
		var id := str(node.id)
		var discovered := id in records.visited
		var chapter := Catalog.chapter(id)
		var details: Array[Dictionary] = []
		if discovered:
			for event_id: String in records.events:
				var entry := Catalog.entry(event_id)
				if str(entry.site)==id: details.append({"id":event_id,"title":str(entry.title),"body":str(entry.body)})
			for person: Dictionary in Catalog.profiles():
				if str(person.site)==id and str(person.id) in records.met:
					details.append({"title":str(person.name),"body":str(person.detail)})
			if id=="mountain_pass":
				var ending := Catalog.epilogue(game.campaign.completed)
				if not ending.is_empty(): details.append(ending)
		var status := L.text("Gesichert") if id in game.campaign.completed else L.text("Entdeckt") if discovered else L.text("Noch nicht erreicht")
		result.append({"id":id,"title":str(chapter.title) if discovered else L.text("Unbekannte Station"),"status":status,"summary":str(chapter.summary) if discovered else L.text("Folge der Kampagnenroute. Hinweise werden erst vor Ort ins Logbuch aufgenommen."),"details":details})
	return result

func read_find(id: String,worker: Node,find: Node2D) -> bool:
	if not enabled or not offline_solo() or not game.hud.overlay.is_empty(): return false
	if not is_instance_valid(worker) or worker.is_queued_for_deletion() or worker not in game.players or not worker.can_act(): return false
	if not is_instance_valid(find) or find.is_queued_for_deletion() or finds.get(id)!=find or find.site_id!=site_id(): return false
	if not find.is_visible_in_tree() or worker.global_position.distance_to(find.global_position)>64.0: return false
	var entry := Catalog.entry(id)
	if entry.is_empty() or str(entry.site)!=site_id() or str(entry.event)!="find": return false
	_emit("find",{"entry_id":id})
	if id not in records.events: return false
	game.hud.solo_story_navigation = {"mode":"journal","site":site_id(),"entry":id,"focus":"reader","scroll":{}}
	game.hud._open_solo_story("journal")
	return true

func objective() -> Dictionary:
	if not enabled: return {}
	var site := site_id()
	var chapter := Catalog.chapter(site)
	if game.expedition.stage in ["travel","stop","occupation","failed"]:
		return {"title":L.text("Die nächste Verbindung"),"body":game.expedition.status_text(),"site":site}
	var body := str(chapter.objective)
	if site in game.campaign.completed:
		body=L.text("Ort gesichert · Bereite den Transporter vor oder besuche offene Crewkontakte auf der Einsatzkarte.")
	for person: Dictionary in Catalog.profiles():
		if str(person.site)!=site or str(person.id) in records.recruited: continue
		var hint := encounter_hint(str(person.id))
		if site not in game.campaign.completed and _cleared_wave<int(person.min_wave):
			hint=L.format("Optional: %s nach %d abgewehrten Wellen in einer sicheren Pause ansprechen.",[str(person.name),int(person.min_wave)])
		elif site not in game.campaign.completed:
			hint=L.format("Optionaler Crewkontakt: %s",hint)
		body+="\n"+hint
		break
	return {"title":str(chapter.title),"body":body,"site":site}

func target_position() -> Vector2:
	if game.expedition.outpost_pending() and is_instance_valid(game.core):
		return game.core.interaction_point()-Vector2(0,76)
	for id: String in npcs:
		var npc: Node2D = npcs[id]
		if is_instance_valid(npc) and id not in records.recruited: return npc.global_position-Vector2(0,76)
	return Vector2(INF,INF)

func encounter_hint(id: String) -> String:
	var profile := Catalog.profile(id)
	if profile.is_empty(): return ""
	var worker: Node=game.players[0] if not game.players.is_empty() else null
	var interact := InputLabels.action(worker,"interact")
	if id in records.recruited: return L.format("Crewkontakt · %s sprechen · %s",[interact,InputLabels.menu(game,"story_journal")])
	return L.format("Überlebende · %s sprechen · Benötigt: %s",[interact,_cost_text(profile.cost)])

func _cost_text(cost: Dictionary) -> String:
	var pieces := PackedStringArray()
	for kind: String in cost: pieces.append(L.format("%d %s",[int(cost[kind]),L.text(str(Balance.RESOURCE_NAMES.get(kind,kind)))]))
	return ", ".join(pieces)

func open_encounter(id: String,worker: Node,npc: Node2D) -> bool:
	if not enabled or not offline_solo() or not game.hud.overlay.is_empty() or not _valid_contact(id,worker,npc): return false
	if not records.mark("met",id):
		game.notify(records.last_error)
		return false
	active_encounter = id
	_encounter_worker = worker
	_encounter_npc = npc
	if id in records.recruited: _emit("npc_after",{"npc_id":id,"recruited":true})
	game.hud._open_solo_story("encounter")
	return true

func _valid_contact(id: String,worker: Node,npc: Node2D) -> bool:
	var profile := Catalog.profile(id)
	return not profile.is_empty() and str(profile.site)==site_id() and is_instance_valid(worker) and not worker.is_queued_for_deletion() and worker in game.players and worker.can_act() and is_instance_valid(npc) and not npc.is_queued_for_deletion() and npc.is_visible_in_tree() and npcs.get(id)==npc and npc.site_id==site_id() and worker.global_position.distance_to(npc.global_position)<=64.0

func _recruit_reason(id: String) -> String:
	if not enabled or not offline_solo() or not _valid_contact(id,_encounter_worker,_encounter_npc): return L.text("Sprich die Person vor Ort an.")
	if id in records.recruited: return L.text("Dieses Crewmitglied ist bereits aufgenommen.")
	var profile := Catalog.profile(id)
	if _living_enemies()>0: return L.text("Sichere zuerst die Umgebung. Es sind noch Maschinen in der Nähe.")
	if game.expedition.stage not in ["defense","preparation","map"]: return L.text("Während der Fahrt kann niemand aufgenommen werden.")
	if not game.expedition.outpost_pending() and game.rounds.phase not in ["build","salvage","victory","convoy"]: return L.text("Warte auf eine sichere Bau- oder Bergungspause.")
	if site_id() not in game.campaign.completed and _cleared_wave<int(profile.min_wave): return L.format("Wehre zunächst %d Wellen an diesem Ort ab.",int(profile.min_wave))
	if not CharacterCatalog.is_unlocked(id):
		for kind: String in profile.cost:
			if int(_encounter_worker.inventory.get(kind,0))<int(profile.cost[kind]): return L.format("Bringe zur Person: %s.",_cost_text(profile.cost))
	return ""

func encounter_view() -> Dictionary:
	var profile := Catalog.profile(active_encounter)
	if profile.is_empty() or active_encounter not in records.met: return {}
	var joined := active_encounter in records.recruited
	var reason := _recruit_reason(active_encounter)
	var paragraphs: Array[String] = []
	paragraphs.assign(profile.rescue if joined else profile.intro)
	if joined:
		paragraphs.append_array(profile.after)
	elif CharacterCatalog.is_unlocked(active_encounter):
		paragraphs.append(L.text("Dieses Crewmitglied steht dir bereits zur Verfügung. Bestätige den Kontakt für diese Reise; weitere Materialien sind nicht nötig."))
	else:
		paragraphs.append(L.format("Für die Bergung brauchen wir: %s. Die Materialien werden bei der Aufnahme verbraucht.",_cost_text(profile.cost)))
	return {"id":active_encounter,"name":str(profile.name),"character":active_encounter,"subtitle":str(profile.detail),"paragraphs":paragraphs,"can_recruit":reason.is_empty(),"reason":reason}

func recruit(id: String) -> bool:
	if id!=active_encounter or not _recruit_reason(id).is_empty(): return false
	var profile := Catalog.profile(id)
	var already_unlocked := CharacterCatalog.is_unlocked(id)
	if not Roster.unlock(id):
		game.notify(L.text("Die Crewaufnahme konnte nicht gespeichert werden. Deine Materialien bleiben bei dir."))
		return false
	# Every condition was checked synchronously above. No frame, timer or callback
	# may interleave between the roster commit and this finite inventory transfer.
	if not already_unlocked:
		for kind: String in profile.cost: _encounter_worker.take_item(kind,int(profile.cost[kind]))
	if not records.mark("recruited",id):
		# The roster is the durable entitlement. A missing journal write cannot
		# remove it or charge again on retry; the next choice only records contact.
		game.notify(records.last_error)
		return true
	_emit("npc_rescued",{"npc_id":id,"recruited":true})
	game.sound_at("build",_encounter_npc.global_position)
	game.notify(L.format("%s ist in der Bunkercrew · Bei der Figurenwahl verfügbar",str(profile.name)))
	return true
