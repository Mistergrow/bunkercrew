extends SceneTree
const Catalog := preload("res://scripts/solo_story_catalog.gd")
const Dialogue := preload("res://scripts/story_dialogue_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(detail)

func _single(result: Array, id: String, detail: String) -> void:
	check(result.size() == 1 and str(result[0].id) == id, detail)

func _run() -> void:
	LocaleText.set_locale("de", false)
	var chapters_before: Dictionary = Catalog.CHAPTERS.duplicate(true)
	var entries_before: Array = Catalog.ENCOUNTERS.duplicate(true)
	var profiles_before: Array = Catalog.PROFILES.duplicate(true)
	var campaign_before: Array = CampaignCatalog.NODES.duplicate(true)
	var voices_before: Dictionary = Dialogue.LINES.duplicate(true)
	var sites: Array[String] = []
	var ids := Catalog.entry_ids()
	check(Catalog.CHAPTERS.size() == CampaignCatalog.NODES.size(), "Every actual campaign site has an authored chapter")
	check(ids.size() == 89, "Complete narrative has 89 encounter, find and follow-up records")
	var unique: Dictionary = {}
	for id: String in ids:
		check(not unique.has(id), "Each journal ID is globally unique: " + id)
		unique[id] = true
		var row := Catalog.entry(id)
		check(Catalog.CHAPTERS.has(str(row.site)) and row.event in Catalog.EVENTS and row.speaker in Catalog.SPEAKERS, "Every record references an actual site, event and narrator")
		check(not str(row.title).strip_edges().is_empty() and not str(row.body).strip_edges().is_empty() and str(row.title).length() <= 80 and str(row.body).length() <= 800, "Native story text is complete and bounded")
	check(Catalog.chapter("unknown").is_empty() and Catalog.entry("unknown").is_empty() and Catalog.profile("unknown").is_empty(), "Unknown identifiers never alias a real mission or person")
	check(Catalog.entries_for("unknown").is_empty() and Catalog.due("unknown", "arrival").is_empty(), "Unknown site callbacks are safely rejected")
	check(Catalog.due("last_shift", "not_real").is_empty(), "Unknown event cannot create a narrative claim")
	var find_count := 0
	var mains: Array[String] = []
	for location: Dictionary in CampaignCatalog.NODES:
		var site := str(location.id)
		sites.append(site)
		var chapter := Catalog.chapter(site)
		check(chapter.id == site and chapter.environment == location.environment and chapter.blueprint == location.blueprint, "Chapter follows the actual campaign environment and reward")
		check(not str(chapter.summary).is_empty() and not str(chapter.objective).is_empty(), "Chapter explains the route and existing objective")
		_single(Catalog.due(site, "arrival"), str(chapter.arrival_id), "Actual arrival callback starts its own chapter")
		check(Catalog.due(site, "arrival", {"arrived":false}).is_empty() and Catalog.due(site, "arrival", {"arrived":1}).is_empty(), "False or nonboolean arrival claims rejected")
		check(Catalog.due(site, "site_secured", {"completed":[]}).is_empty(), "Arrival alone never claims a secured site")
		_single(Catalog.due(site, "site_secured", {"completed":[site]}), str(chapter.completion_id), "Actual completed site schedules its truthful conclusion")
		check(Catalog.due(site, "site_secured", {"completed":[site,site]}).is_empty() and Catalog.due(site, "site_secured", {"completed":["invented"]}).is_empty(), "Corrupt completion evidence is refused")
		check(Catalog.due(site, "site_secured", {"completed":true}).is_empty(), "Wrong completion evidence type does not throw")
		for find_id: String in chapter.find_ids:
			find_count += 1
			check(Catalog.entry(find_id).event == "find", "Chapter links two actual location finds")
			_single(Catalog.due(site, "find", {"entry_id":find_id}), find_id, "Only the actually read find enters the journal")
			check(Catalog.due(site, "find", {"entry_id":"wrong"}).is_empty(), "Unvisited or different-location find is not awarded")
		if CampaignCatalog.site_kind(site) == "bunker":
			mains.append(site)
			for wave in [3,10,15]:
				_single(Catalog.due(site, "wave_cleared", {"wave":wave,"phase":"salvage","enemies_remaining":0}), site+":wave_"+str(wave), "Real cleared wave reveals its chapter progress")
				_single(Catalog.due(site, "wave_cleared", {"wave":wave+1,"phase":"build","enemies_remaining":0}), site+":wave_"+str(wave), "Next build wave points back to the wave actually repelled")
				check(Catalog.due(site, "wave_cleared", {"wave":wave,"phase":"attack","enemies_remaining":0}).is_empty(), "Active attack is not counted as completed")
				check(Catalog.due(site, "wave_cleared", {"wave":wave,"phase":"salvage","enemies_remaining":1}).is_empty(), "Living enemy blocks cleared-wave narrative")
			check(Catalog.due(site, "guards_cleared", {"enemies_remaining":0}).is_empty(), "Bunker does not borrow an outpost clearing scene")
		else:
			_single(Catalog.due(site, "guards_cleared", {"enemies_remaining":0}), site+":guards_clear", "Outpost clearing precedes actual control/archive handover")
			check(Catalog.due(site, "guards_cleared", {"enemies_remaining":1}).is_empty() and Catalog.due(site, "guards_cleared", {"enemies_remaining":false}).is_empty(), "Outpost clear requires integer zero actual guards")
			check(Catalog.due(site, "wave_cleared", {"wave":3,"phase":"salvage","enemies_remaining":0}).is_empty(), "Occupation outposts have no imaginary twenty-wave scenes")
	check(find_count == 24 and mains.size() == 8, "All twelve locations have two finds; eight are genuine defensive shifts")
	for stage in [3,5,7]:
		var result := Catalog.due("last_shift", "relay_completed", {"relay_stage":stage})
		check(result.size() == 1 and int(result[0].relay_stage) == stage, "Entry prologue keeps exact existing relay completion stages")
	check(Catalog.due("harbor", "relay_completed", {"relay_stage":3}).is_empty(), "Later chapters do not repeat the entry tutorial relay")
	for invalid in [-1,0,1,2,4,6,8,9,INF,NAN,"3",true]:
		check(Catalog.due("last_shift", "relay_completed", {"relay_stage":invalid}).is_empty(), "Invalid/uncompleted relay stage rejected")
	var expected := {
		"oskar":{"site":"quarry","min_wave":3,"cost":{"concrete":2}},
		"rika":{"site":"power_station","min_wave":3,"cost":{"steel":2}},
		"nora":{"site":"refinery_archive","min_wave":0,"cost":{"steel":2}},
		"selma":{"site":"dam_vault","min_wave":0,"cost":{"concrete":1}},
		"levin":{"site":"radar_archive","min_wave":0,"cost":{"ammo":1}},
	}
	check(Catalog.profiles().size() == expected.size(), "Exactly five authored local NPC profiles")
	for id: String in expected:
		var person := Catalog.profile(id)
		var spec: Dictionary = expected[id]
		check(person.site == spec.site and int(person.min_wave) == int(spec.min_wave) and person.cost == spec.cost, "Concrete rescue job uses agreed actual costs and cleared-wave gate")
		check(Catalog.chapter(str(person.site)).npc_ids.has(id), "Person is attached to their own location")
		check(not str(person.name).is_empty() and not str(person.role).is_empty() and not str(person.detail).is_empty() and not str(person.job_title).is_empty(), "Each NPC has a name, background, role and useful personal job")
		for field: String in ["intro","rescue","after"]:
			check(person[field] is Array and not person[field].is_empty(), "All NPCs have complete introduction/recruitment/follow-up dialogue")
			for line: String in person[field]: check(not line.strip_edges().is_empty(), "NPC dialogue cannot contain blank placeholders")
		for field: String in ["intro_id","rescue_id","after_id"]:
			check(unique.has(str(person[field])) and Catalog.entry(str(person[field])).site == person.site, "NPC dialogue references actual journal records")
		var context := {"npc_id":id,"recruited":true,"enemies_remaining":0,"phase":"salvage","wave":3}
		_single(Catalog.due(str(person.site), "npc_rescued", context), str(person.rescue_id), "Personal recruitment is allowed in safe salvage before whole-site completion")
		context.phase = "build"
		context.wave = 4
		_single(Catalog.due(str(person.site), "npc_rescued", context), str(person.rescue_id), "Three actual completed waves remain satisfied next build break")
		context.recruited = false
		check(Catalog.due(str(person.site), "npc_rescued", context).is_empty(), "Unfinished job cannot claim NPC recruitment")
		context.recruited = true
		context.enemies_remaining = 1
		check(Catalog.due(str(person.site), "npc_rescued", context).is_empty(), "A living guard blocks a recruitment claim")
		context.enemies_remaining = 0
		context.phase = "attack"
		check(Catalog.due(str(person.site), "npc_rescued", context).is_empty(), "Attack blocks safe interaction recruitment")
		context.stage = "defense"
		check(Catalog.due(str(person.site), "npc_rescued", context).is_empty() == (CampaignCatalog.site_kind(str(person.site)) != "outpost"), "Safe outpost zero-guard recruitment survives retained attack phase")
		context.erase("stage")
		context.phase = "build"
		context.wave = 3
		check(Catalog.due(str(person.site), "npc_rescued", context).is_empty() == (int(person.min_wave) == 3), "Wave-three build means only two repelled waves")
		context.cleared_wave = 3
		_single(Catalog.due(str(person.site), "npc_rescued", context), str(person.rescue_id), "Explicit validated cleared-wave evidence supports actual controller snapshots")
		context.npc_id = "other"
		check(Catalog.due(str(person.site), "npc_rescued", context).is_empty(), "Another person cannot claim this recruit")
		context.npc_id = id
		context.recruited = 1
		check(Catalog.due(str(person.site), "npc_rescued", context).is_empty(), "Numeric recruited flag rejected without a type error")
		context.recruited = true
		context.phase = "preparation"
		_single(Catalog.due(str(person.site), "npc_rescued", context), str(person.rescue_id), "Secured-bunker preparation permits a previously unfinished personal job")
		context.phase = "victory"
		context.stage = "preparation"
		_single(Catalog.due(str(person.site), "npc_rescued", context), str(person.rescue_id), "Actual expedition preparation remains safe when rounds retain victory phase")
		context.stage = "map"
		context.phase = "convoy"
		context.cleared_wave = 0
		context.completed = [str(person.site)]
		_single(Catalog.due(str(person.site), "npc_rescued", context), str(person.rescue_id), "Completed-site map return supports unfinished personal jobs without repeating waves")
		for completion in [[], [str(person.site),str(person.site)], true, "wrong"]:
			context.completed = completion
			check(Catalog.due(str(person.site), "npc_rescued", context).is_empty(), "Map contact requires reliable completed-site evidence")
		context.completed = [str(person.site)]
		context.phase = "attack"
		check(Catalog.due(str(person.site), "npc_rescued", context).is_empty(), "A map flag alone cannot authorize an active attack phase")
		_single(Catalog.due(str(person.site), "npc_after", {"npc_id":id,"recruited":true}), str(person.after_id), "Accepted recruit offers a concrete follow-up without another material debit")
		check(Catalog.due(str(person.site), "npc_after", {"npc_id":id,"recruited":false}).is_empty(), "Unrecruited NPC does not claim crew follow-up")
		person.cost.clear()
		person.intro.clear()
		check(Catalog.profile(id).cost == spec.cost and not Catalog.profile(id).intro.is_empty(), "Returned nested NPC costs/dialogue cannot mutate canonical jobs")
	for id: String in ["nora","selma","levin"]:
		check(CharacterCatalog.data(id).unlock_site == Catalog.profile(id).site, "Original missing-character rescue sites stay unchanged")
	for invalid in [null,false,0,"0",[],{},INF,NAN,-1,1000]:
		var context := {"wave":invalid,"phase":"salvage","enemies_remaining":0}
		check(Catalog.due("quarry", "wave_cleared", context).is_empty(), "Malformed wave input never leaks a narrative event")
		check(Catalog.due("quarry", "npc_rescued", {"npc_id":"oskar","recruited":true,"enemies_remaining":0,"phase":"build","cleared_wave":invalid}).is_empty(), "Malformed cleared-wave input never grants new character story")
	check(Catalog.epilogue([]).is_empty() and Catalog.epilogue(mains.slice(0,7)).is_empty(), "Unfinished route never gets a finale")
	check(Catalog.epilogue(mains).id == "main_route", "Eight secured bunkers grant only a truthful main-route conclusion")
	check(Catalog.epilogue(sites).id == "all_sites", "All twelve sites grant the complete-network conclusion")
	check(Catalog.epilogue(["unknown"]).is_empty() and Catalog.epilogue(["harbor","harbor"]).is_empty(), "Bad save evidence cannot manufacture campaign completion")
	var changed := Catalog.chapter("quarry")
	changed.npc_ids.clear()
	changed.find_ids.clear()
	check(Catalog.chapter("quarry").npc_ids == ["oskar"] and Catalog.chapter("quarry").find_ids.size() == 2, "Caller edits cannot change chapter metadata")
	var first := Catalog.due("last_shift", "arrival")
	first[0].body = "changed"
	check(Catalog.due("last_shift", "arrival")[0].body != "changed", "Scheduling results are independent copies; persistence belongs to controller")
	check(Catalog.CHAPTERS == chapters_before and Catalog.ENCOUNTERS == entries_before and Catalog.PROFILES == profiles_before, "All reads preserve canonical authored story")
	check(CampaignCatalog.NODES == campaign_before and Dialogue.LINES == voices_before, "Story text changes neither campaign gameplay nor existing voiced phrases")
	LocaleText.set_locale("en", false)
	check(Catalog.chapter("last_shift").title == "I · The first reply", "English chapter title is translated through real locale table")
	check(Catalog.profile("oskar").role == "Quarry carrier" and Catalog.profile("rika").role == "Electrician and radio operator", "Both new NPC roles are translated")
	check(Catalog.profile("oskar").intro[0].begins_with("I’m Oskar.") and Catalog.profile("rika").intro[0].begins_with("Rika. I can hear"), "Native NPC arrays are translated before display")
	check(Catalog.entry("radar_archive:rescue_levin").body.begins_with("The cover position"), "Personal rescue journal uses the full English text")
	check(Catalog.epilogue(sites).title == "Every site has answered.", "Finale is translated without new voice dependencies")
	check(Catalog.profile("rika").id == "rika" and Catalog.chapter("quarry").id == "quarry" and Catalog.profile("oskar").cost.has("concrete"), "English locale never changes machine IDs or material keys")
	LocaleText.set_locale("de", false)
	print("Solo story catalog: %d/%d checks passed" % [checks-failures, checks])
	quit(1 if failures > 0 else 0)
