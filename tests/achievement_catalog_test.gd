extends SceneTree
const Catalog := preload("res://scripts/achievement_catalog.gd")
const Delivery := preload("res://scripts/achievement_delivery.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks:=0
var failures:=0

class Provider extends RefCounted:
	signal achievements_stored(token: int, success: bool)
	var ready:=false
	var accepted:=true
	var requests: Array=[]
	func achievement_ready() -> bool: return ready
	func store_achievements(ids: Array[String],token: int) -> bool:
		requests.append({"ids":ids,"token":token})
		return accepted

class Research extends Node:
	var owned: Dictionary={}
	func has_upgrade(id: String) -> bool: return owned.has(id)

class Fixture extends Node:
	var upgrades: Node
	var core: Node
	var players: Array=[1,2]
	func sound_at(_kind: String,_at: Vector2) -> void: pass
	func on_core_destroyed() -> void: pass

class Crafter extends Node:
	var player_id:=1

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("ACHIEVEMENT %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok: failures+=1

func run() -> void:
	var public_count:=0
	var secret_count:=0
	var steam_ids: Array=[]
	var ids: Array=[]
	for entry in Catalog.ENTRIES:
		if entry.hidden: secret_count+=1
		else: public_count+=1
		check(not ids.has(entry.id) and not steam_ids.has(entry.steam) and entry.steam.begins_with("LS_"),entry.id+" stable unique local/platform IDs")
		ids.append(entry.id)
		steam_ids.append(entry.steam)
	check(public_count==21 and secret_count==5,"exactly21 public plus5 secret achievements")
	for id in ["first_kill","combo_five","level_five","armor","trap","turret","wave_five","boss","victory"]:
		check(ids.has(id),"legacy saved ID retained: "+id)
	var fixture:=Fixture.new()
	root.add_child(fixture)
	var events:=CombatEvents.new()
	events.game=fixture
	fixture.add_child(events)
	events.set_process(false)
	var research:=Research.new()
	fixture.add_child(research)
	fixture.upgrades=research
	var core:=BunkerCore.new()
	core.game=fixture
	fixture.add_child(core)
	fixture.core=core
	var records:=events.records()
	check(records.size()==26 and records.filter(func(item): return item.hidden).all(func(item): return item.title==LocaleText.text("GEHEIMER ERFOLG")),"all locked secret titles hidden")
	check(records.filter(func(item): return item.hidden).all(func(item): return item.detail==LocaleText.text("Wird nach Freischaltung enthüllt.")),"all locked secret conditions hidden")
	events.unlock("last_drop")
	check(events.records().filter(func(item): return item.id=="last_drop")[0].title==LocaleText.text("AUF DEN LETZTEN TROPFEN"),"unlock reveals secret title")
	check(not events.unlock("not_real") and not events.unlock("last_drop"),"unknown/duplicate unlock cannot add records")
	events.record_mined(49)
	check(not events.unlocked.has("miner_50"),"mining threshold not granted early")
	events.record_mined(1)
	check(events.unlocked.has("miner_50") and events.counters.mined==50,"mining counter unlocks at50 physical units")
	events.record_mined(-3)
	check(events.counters.mined==50,"negative mined quantities ignored")
	var crafter:=Crafter.new()
	fixture.add_child(crafter)
	for unused in 5: events.record_craft(crafter,"medkit")
	check(events.unlocked.has("craft_five") and events.counters.crafted==5,"five completed crafting events unlock field workshop")
	research.owned={"bunker_workshop":true,"core_resilience":true,"repair_tools":true,"convoy_mg":true}
	events._watch_research()
	check(events.unlocked.has("research_first") and events.unlocked.has("base_engineer") and events.unlocked.has("convoy_upgrade"),"owned technology unlocks research/base/vehicle milestones")
	events.record_campaign_event("route_complete",{"fuel":2.0})
	check(events.unlocked.has("convoy_route"),"actual route completion unlocks journey")
	events.record_campaign_event("occupation_complete",{"cargo_count":18})
	check(events.unlocked.has("base_capture") and events.unlocked.has("loaded_arrival"),"capture event distinguishes loaded arrival")
	events.record_campaign_event("roadside_complete",{"weapon":"veteran_rifle"})
	check(events.unlocked.has("roadside") and events.unlocked.has("epic_weapon"),"secured weapon stop unlocks its two milestones")
	events.record_campaign_event("campaign_complete")
	check(events.unlocked.has("all_routes"),"main-route completion unlocks secret finale")
	events.unlock("victory")
	check(events.unlocked.has("pristine_core") and not events.unlocked.has("solo_victory"),"undamaged co-op victory grants pristine core but no solo award")
	events.unlocked.erase("pristine_core")
	core.take_damage(10)
	core.hp=core.max_hp
	events.unlock("victory")
	check(not events.unlocked.has("pristine_core"),"repairing earlier core damage never fakes pristine victory")
	fixture.players=[1]
	events.unlock("victory")
	check(events.unlocked.has("solo_victory"),"later solo victory still evaluated after old victory already earned")
	var path: String="user://achievement-regression-%d.cfg"%OS.get_process_id()
	var config:=ConfigFile.new()
	config.set_value("achievements","first_kill",true)
	config.set_value("future_section","preserve",77)
	config.save(path)
	var migrated:=CombatEvents.new()
	migrated.save_path=path
	migrated.persistence_enabled=true
	migrated.load_records()
	check(migrated.unlocked.has("first_kill") and migrated.platform.pending.has("LS_FIRST_KILL"),"legacy local award migrated into optional platform queue")
	migrated.counters.mined=31
	migrated.unlock("armor")
	config.load(path)
	check(config.get_value("future_section","preserve",0)==77 and config.get_value("achievements","first_kill",false),"saving new achievements preserves legacy sections and awards")
	var reloaded:=CombatEvents.new()
	reloaded.save_path=path
	reloaded.load_records()
	check(reloaded.counters.mined==31 and reloaded.platform.pending.has("LS_ARMOR"),"progress and delivery queue survive reload")
	var queue=Delivery.new()
	queue.enqueue("first_kill")
	queue.enqueue("first_kill")
	queue.enqueue("invalid")
	check(queue.pending.size()==1,"platform queue deduplicates and rejects unknown IDs")
	queue.advance(120)
	check(queue.pending.size()==1,"offline play retains pending award without a provider")
	var provider:=Provider.new()
	check(queue.set_provider(provider),"optional adapter contract accepted")
	queue.advance(1)
	check(provider.requests.is_empty(),"delivery waits for platform stats readiness")
	provider.ready=true
	provider.accepted=false
	queue.advance(1)
	check(queue.pending.size()==1 and queue.inflight.is_empty(),"rejected store remains pending")
	provider.accepted=true
	queue.advance(61)
	check(queue.pending.size()==1 and queue.inflight.size()==1,"request acceptance never clears durable pending queue")
	provider.achievements_stored.emit(queue.token-1,true)
	check(queue.pending.size()==1,"stale acknowledgement cannot confirm current batch")
	provider.achievements_stored.emit(queue.token,false)
	check(queue.pending.size()==1 and queue.inflight.is_empty(),"failed server acknowledgement retries later")
	queue.advance(61)
	provider.achievements_stored.emit(queue.token,true)
	check(queue.pending.is_empty() and queue.confirmed.has("LS_FIRST_KILL"),"successful server callback alone confirms award")
	queue.enqueue("first_kill")
	check(queue.pending.is_empty(),"confirmed award is not resubmitted every frame")
	queue.enqueue("armor")
	queue.advance(61)
	queue.advance(26)
	check(queue.pending.has("LS_ARMOR") and queue.inflight.is_empty(),"missing callback times out with award intact")
	queue.set_provider(null)
	migrated.free()
	reloaded.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await Cleanup.free_scene(fixture,self)
	print("ACHIEVEMENTS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
