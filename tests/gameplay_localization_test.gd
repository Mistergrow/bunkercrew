extends SceneTree
## Existing objects switch languages without changing their gameplay identifiers.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var game
var worker

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	LocaleText.set_locale("de",false)
	var worlds_de:=ScenarioCatalog.environments()
	var characters_de: Dictionary=CharacterCatalog.data("ivo")
	var raw_recipes: Dictionary=Balance.RECIPES.duplicate(true)
	var raw_enemies: Dictionary=EnemyCatalog.PROFILES.duplicate(true)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.story_mode=true
	game.start_scenario(2,{"environment":"mountain_pass","position":"left","build_type":"bastion"})
	freeze(game)
	paused=false
	worker=game.players[0]
	worker.inventory={"steel":2,"concrete":2,"ammo":1}
	worker.selected_kind="steel"
	var supplies: Array=get_nodes_in_group("supplies")
	var steel_crate
	for crate in supplies:
		if crate.kind=="steel": steel_crate=crate
	var stations: Array=[]
	for kind: String in Balance.RECIPES:
		var station: ProductionStation=RecipeStation.new() if kind in ["glass","alloy","ammo_press"] else ProductionStation.new()
		station.game=game
		station.kind=kind
		game.add_child(station)
		freeze(station)
		stations.append(station)
	var field_gun: RoofTurret=FieldDefense.GroundGun.new()
	field_gun.game=game
	game.add_child(field_gun)
	freeze(field_gun)
	var core_de: String=game.core.prompt(worker)
	var stock_de: String=steel_crate.prompt(worker)
	var mission_de: String=game.story.objective()
	var machine_titles_de: Array=[]
	for station in stations: machine_titles_de.append(station.interaction_title())
	LocaleText.set_locale("en",false)
	check(game.core.prompt(worker).begins_with("Bunker core"),"Existing bunker core changes to English")
	check(steel_crate.prompt(worker).contains("Stockpile") and steel_crate.controls_hint(worker).contains("store"),"Existing supply and selected deposit controls change to English")
	check(game.story.objective().contains("forms"),"Existing story objective translates before wrapping")
	check(game.story.relay.prompt(worker).contains("FIELD RADIO"),"Radio state uses a complete translated template")
	check(game.turret.prompt(worker).contains("Roof turret") and field_gun.prompt(worker).contains("Field turret"),"Turret identities do not depend on replacing German words")
	check(game.turret.prompt(worker).contains("rounds"),"Turret rounds use translated formatting")
	check(worker.get_node("WorkerWeapon").weapon_name()=="SERVICE RIFLE","Existing player's weapon name changes live")
	check(worker.action("interact")=="p1_interact","Translation does not modify InputMap IDs")
	for index in stations.size():
		var station=stations[index]
		check(station.interaction_title()!=machine_titles_de[index],"Existing %s station changes its name" % station.kind)
		check(station.prompt(worker).contains("materials"),"Idle %s instructions are English" % station.kind)
		station.output_amount=2
		check(station.prompt(worker).contains("ready to collect"),"Output prompt for %s is English" % station.kind)
		station.output_amount=0
		station.working=true
		check(station.prompt(worker).contains("Producing"),"Working prompt for %s is English" % station.kind)
		station.working=false
		check(station.recipe().inputs==raw_recipes[station.kind].inputs and station.output_kind()==raw_recipes[station.kind].output,"Recipe IDs and costs remain stable for %s" % station.kind)
	var steel_station=stations[1]
	check(steel_station.recipe_text().contains(" or ") and not steel_station.input_status().contains("Eisenerz"),"Alternate furnace ingredients translate before joining")
	stations[0].binder=0
	check(stations[0].prompt(worker).contains("Binder depleted"),"Rare depleted-binder state is translated")
	check(Balance.resource_quantity("ammo",1)=="1 Ammo crate" and Balance.resource_quantity("ammo",2)=="2 Ammo crates","Ammo crate singular and plural are complete translated nouns")
	for kind: String in Balance.RESOURCE_NAMES:
		check(not Balance.resource_quantity(kind,3).is_empty(),"Quantity formatting covers %s" % kind)
	game.upgrades.points=0
	check(game.upgrades.requirement("bunker_workshop")=="2 TECH POINTS NEEDED","Plural technology shortage uses a complete English sentence")
	game.upgrades.points=1
	check(game.upgrades.requirement("bunker_workshop")=="1 TECH POINT NEEDED","Singular technology shortage has no German suffixes")
	game.story.stage=6
	check(game.story.objective().contains("five seconds") and game.story.relay.prompt(worker).contains("five seconds"),"Both final-send instructions use the same English duration")
	worker.medical.state="critical"
	check(worker.medical.status_text().begins_with("CRITICAL"),"Critical medical state switches live")
	worker.medical.state="healthy"
	worker.medical.bleeding=2
	worker.medical.fractured=true
	check(worker.medical.status_text().contains("BLEEDING II") and worker.medical.status_text().contains("BROKEN LEG"),"Combined wounds have no untranslated fragments")
	worker.medical.bleeding=0
	worker.medical.fractured=false
	var worlds_en:=ScenarioCatalog.environments()
	check(worlds_en.size()==worlds_de.size(),"Language does not alter the available worlds")
	for index in worlds_en.size():
		var english: Dictionary=worlds_en[index]
		var german: Dictionary=worlds_de[index]
		check(english.id==german.id and english.path==german.path,"World %s retains its ID and artwork" % english.id)
		check(english.title!=german.title and english.detail!=german.detail,"World %s translates its title and description" % english.id)
		check(ScenarioCatalog.validate({"environment":english.id}).environment==english.id,"World %s remains selectable in English" % english.id)
	for raw: Dictionary in CampaignCatalog.NODES:
		var translated:=CampaignCatalog.node(raw.id)
		check(translated.id==raw.id and translated.parent==raw.parent and translated.environment==raw.environment,"Campaign route %s keeps machine-readable identifiers" % raw.id)
		var expected_title: bool=translated.title=="BUNKERCREW" if raw.id==CampaignCatalog.ENTRY else translated.title!=raw.title
		check(expected_title and translated.detail!=raw.detail,"Campaign route %s translates its description and preserves the brand name" % raw.id)
	for raw: Dictionary in game.combat_events.ACHIEVEMENTS:
		check(LocaleText.text(raw.title)!=raw.title and LocaleText.text(raw.detail)!=raw.detail,"Achievement %s is translated" % raw.id)
	for id: String in EnemyCatalog.CLASS_ORDER:
		var profile: Dictionary=EnemyCatalog.profile(id)
		check(LocaleText.text(profile.label)!=profile.label or profile.label=="BASTION","Enemy %s has an English display label" % id)
	check(CharacterCatalog.data("ivo").id==characters_de.id and CharacterCatalog.data("ivo").detail!=characters_de.detail,"Character traits translate without changing character IDs")
	check(Balance.RECIPES==raw_recipes and EnemyCatalog.PROFILES==raw_enemies,"Localization never mutates shared gameplay constants")
	var boss_events: Dictionary={}
	game.combat_events.event.connect(func(kind: String,payload: Dictionary):
		if kind in ["boss","boss_phase"]: boss_events[kind]=payload.duplicate(true))
	game.spawn_enemy(20,11,12)
	var boss=game.get_tree().get_first_node_in_group("enemies")
	freeze(boss)
	check(boss_events.get("boss",{}).get("final_boss",false),"Actual final-boss announcement uses an explicit identity flag")
	check(boss.get_meta("boss_title")=="MUTTERMASCHINE","Boss metadata keeps its canonical source in an English game")
	boss.hp=boss.max_hp*.49
	boss._physics_process(0)
	check(boss_events.get("boss_phase",{}).get("final_boss",false),"Actual final-boss phase change retains the explicit identity flag")
	LocaleText.set_locale("de",false)
	game.story.stage=0
	stations[0].binder=Balance.BINDER_STOCK
	check(game.core.prompt(worker)==core_de and steel_crate.prompt(worker)==stock_de,"English-to-German switch restores existing core and stock prompts")
	check(game.story.objective()==mission_de,"English-to-German switch restores the existing story objective")
	for index in stations.size():
		check(stations[index].interaction_title()==machine_titles_de[index],"Existing %s machine returns to German" % stations[index].kind)
	check(field_gun.prompt(worker).contains("Feldgeschütz") and worker.get_node("WorkerWeapon").weapon_name()=="DIENSTGEWEHR","Existing turret and worker return to German")
	check(await Cleanup.free_scene(game,self),"Localized scene releases its resources")
	paused=false
	print("GAMEPLAY LOCALIZATION: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
