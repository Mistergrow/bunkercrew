class_name CombatEvents
extends Node
## Personal combat feedback and local, cosmetic achievement records.
## XP lives on each worker; recovered technology remains shared by the bunker.
signal event(kind: String, data: Dictionary)
signal dance_progress_changed(character_id: String, level: int)

const AchievementCatalog := preload("res://scripts/achievement_catalog.gd")
const Delivery := preload("res://scripts/achievement_delivery.gd")
const DanceCatalog := preload("res://scripts/worker_dance_catalog.gd")
const ACHIEVEMENTS := AchievementCatalog.ENTRIES
var game: Node
var unlocked: Dictionary = {}
var earned_this_shift: Dictionary = {}
var save_path := "user://achievements.cfg"
var persistence_enabled := true
var _boss: WeakRef
var _hit_context: Dictionary = {}
var counters: Dictionary={"mined":0,"crafted":0}
var dance_levels: Dictionary = {}
var platform=Delivery.new()
var _dirty:=false
var _save_delay:=0.0
var _research_clock:=0.0
var team := TeamProgression.new()

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	persistence_enabled = not "--no-profile-save" in OS.get_cmdline_user_args()
	platform.changed.connect(_schedule_save)
	if persistence_enabled:
		load_records()

func _process(delta: float) -> void:
	team.game = game
	team.advance(delta)
	platform.advance(delta)
	if _dirty:
		_save_delay-=delta
		if _save_delay<=0: _save_records()
	_research_clock-=delta
	if _research_clock<=0:
		_research_clock=.5
		_watch_dance_progression()
		_watch_research()

func set_achievement_provider(provider: Object) -> bool:
	# Public integration entry point documented in docs/steam-achievements.md.
	return platform.set_provider(provider)

func _schedule_save() -> void:
	_dirty=true
	_save_delay=1.0

func _save_records() -> void:
	_dirty=false
	if not persistence_enabled: return
	var config:=ConfigFile.new()
	# Keep pre-existing sections/unknown IDs intact; the nine legacy IDs never
	# change, and acquiring the new catalog does not clear earned progress.
	var loaded:=config.load(save_path)
	if loaded not in [OK,ERR_FILE_NOT_FOUND]:
		push_warning(LocaleText.format("Erfolge konnten nicht gespeichert werden: %s",error_string(loaded)))
		return
	for id in unlocked: config.set_value("achievements",id,true)
	for key in counters: config.set_value("progress",key,int(counters[key]))
	for id: String in dance_levels:
		var saved = config.get_value("dance_levels",id,1)
		if saved is int and saved>=1 and saved<=PlayerProgression.MAX_LEVEL:
			dance_levels[id] = maxi(int(dance_levels[id]),saved)
		config.set_value("dance_levels",id,int(dance_levels[id]))
	for section in ["steam_pending","steam_confirmed"]:
		if config.has_section(section): config.erase_section(section)
	for id in platform.pending: config.set_value("steam_pending",id,true)
	for id in platform.confirmed: config.set_value("steam_confirmed",id,true)
	var result:=config.save(save_path)
	if result!=OK: push_warning(LocaleText.format("Erfolge konnten nicht gespeichert werden: %s",error_string(result)))

func load_records() -> void:
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	for entry in ACHIEVEMENTS:
		if config.get_value("achievements", entry.id, false) == true:
			unlocked[entry.id] = true
		if config.get_value("steam_confirmed",entry.steam,false)==true:
			platform.confirmed[entry.steam]=true
		elif unlocked.has(entry.id):
			platform.enqueue(entry.id)
	for key in counters:
		var value=config.get_value("progress",key,0)
		if value is int: counters[key]=clampi(value,0,1000000)
	for id: String in DanceCatalog.IDS:
		var saved = config.get_value("dance_levels",id,1)
		if not saved is int or saved<1 or saved>PlayerProgression.MAX_LEVEL: continue
		dance_levels[id] = maxi(int(dance_levels.get(id,1)),saved)
	_check_dance_achievement()

func record_character_dance_level(character_id: String,level: Variant) -> bool:
	# Only real character levels are retained. This never modifies run XP,
	# skill points, hit points, equipment, or the progression node itself.
	if character_id not in DanceCatalog.IDS or not level is int or level<1 or level>PlayerProgression.MAX_LEVEL: return false
	if level<=int(dance_levels.get(character_id,1)): return false
	dance_levels[character_id] = level
	_schedule_save()
	dance_progress_changed.emit(character_id,level)
	_check_dance_achievement()
	return true

func dance_level(character_id: String,live_level: int=1) -> int:
	if character_id not in DanceCatalog.IDS: return 1
	var valid_live := live_level if live_level>=1 and live_level<=PlayerProgression.MAX_LEVEL else 1
	return maxi(int(dance_levels.get(character_id,1)),valid_live)

func unlocked_dance_count() -> int:
	var count := 0
	for id: String in DanceCatalog.BUILTIN_IDS:
		for style: String in DanceCatalog.UNIQUE_STYLES[id]:
			if DanceCatalog.required_level(style)<=dance_level(id): count += 1
	return count

func session_records() -> Dictionary:
	return {"achievements":unlocked.keys(),"dance_levels":dance_levels.duplicate(),"counters":counters.duplicate()}

func restore_session_records(profile_records: Dictionary) -> void:
	# Scene reloads are profile reads, not newly earned cooperative rewards.
	# Restore monotonically and keep IDs validated just like load_records().
	var achievements: Variant=profile_records.get("achievements",[])
	if achievements is Array:
		for entry in ACHIEVEMENTS:
			if entry.id in achievements:
				unlocked[entry.id]=true
				platform.enqueue(entry.id)
	var levels: Variant=profile_records.get("dance_levels",{})
	if levels is Dictionary:
		for id: String in DanceCatalog.IDS:
			var level: Variant=levels.get(id,1)
			if level is int and level>=1 and level<=PlayerProgression.MAX_LEVEL:
				dance_levels[id]=maxi(int(dance_levels.get(id,1)),level)
	var activity: Variant=profile_records.get("counters",{})
	if activity is Dictionary:
		for key in counters:
			var value: Variant=activity.get(key,0)
			if value is int: counters[key]=maxi(int(counters[key]),clampi(value,0,1000000))
	_schedule_save()

func _check_dance_achievement() -> void:
	if unlocked_dance_count()==DanceCatalog.BUILTIN_IDS.size()*DanceCatalog.UNLOCK_LEVELS.size():
		unlock("all_dance_moves")

func _capture_player_dance_level(player: Node) -> void:
	if not is_instance_valid(player) or not "character_id" in player or not "progression" in player: return
	var progression = player.get("progression")
	if is_instance_valid(progression) and "level" in progression:
		record_character_dance_level(str(player.character_id),progression.level)

func _watch_dance_progression() -> void:
	# Campaign and network restore assign an existing progression snapshot after
	# track_player(). The existing half-second watch captures those real levels.
	if not is_instance_valid(game) or not "players" in game: return
	for player in game.players:
		if player is Node: _capture_player_dance_level(player)

func records() -> Array:
	var result: Array = []
	for entry in ACHIEVEMENTS:
		var item: Dictionary = entry.duplicate()
		item.unlocked = bool(unlocked.get(entry.id, false))
		item.progress=int(counters.get("mined" if entry.id=="miner_50" else "crafted",0)) if entry.id in ["miner_50","craft_five"] else 0
		item.goal=50 if entry.id=="miner_50" else (5 if entry.id=="craft_five" else 0)
		if entry.id=="all_dance_moves":
			item.progress = unlocked_dance_count()
			item.goal = DanceCatalog.BUILTIN_IDS.size()*DanceCatalog.UNLOCK_LEVELS.size()
		if bool(entry.hidden) and not item.unlocked:
			item.title="GEHEIMER ERFOLG"
			item.detail="Wird nach Freischaltung enthüllt."
		result.append(item)
	return LocaleText.data(result)

func unlock(id: String) -> bool:
	for entry in ACHIEVEMENTS:
		if entry.id != id:
			continue
		# Record the current round independently of the local saved profile. A
		# co-op partner may still need an achievement this machine earned before.
		earned_this_shift[id] = true
		if id=="victory": _victory_secrets()
		if bool(unlocked.get(id, false)):
			return false
		unlocked[id] = true
		platform.enqueue(id)
		_save_records()
		event.emit("achievement", {"id":id, "title":entry.title, "detail":entry.detail})
		return true
	return false

func track_player(player: Node) -> void:
	if not is_instance_valid(player) or not "progression" in player:
		return
	var handler := _personal_event.bind(player)
	if not player.progression.event.is_connected(handler): player.progression.event.connect(handler)
	_capture_player_dance_level(player)
	team.game = game
	team.participate(player)

func _personal_event(kind: String, data: Dictionary,source_player: Node=null) -> void:
	var payload := data.duplicate()
	if kind=="level_up": _capture_player_dance_level(source_player)
	if kind in ["hit", "kill"]:
		payload.merge(_hit_context, true)
	if kind == "kill":
		unlock("first_kill")
		if int(data.get("combo", 0)) >= 5:
			unlock("combo_five")
	elif kind == "level_up" and int(data.get("level", 1)) >= 5:
		unlock("level_five")
	elif kind == "armor":
		unlock("armor")
	event.emit(kind, payload)

func credit_hit(enemy: Node2D, applied: float, player: Node, killed: bool, at: Vector2) -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.progression) or not is_finite(applied) or applied<=0: return
	team.game = game
	var reward := team.combat_share(player)
	if reward.players.is_empty(): return
	var next_combo := mini(PlayerProgression.MAX_COMBO,int(player.progression.combo)+1) if player.progression.combo_time>0 else 1
	var shared := applied*PlayerProgression.XP_PER_DAMAGE
	if killed: shared += PlayerProgression.XP_PER_KILL*(1.0+(next_combo-1)*PlayerProgression.COMBO_BONUS_STEP)
	_hit_context = {"position":at, "amount":applied, "enemy_id":enemy.get_instance_id()}
	var personal_share: float=float(reward.share) if player in reward.players else 0.0
	player.progression.award_damage(applied,personal_share)
	if killed:
		player.progression.award_kill(personal_share)
		if enemy.get_meta("final_boss", false): unlock("boss")
	_hit_context.clear()
	for teammate in reward.players:
		if teammate != player: teammate.progression.award_team(shared*float(reward.share),"team")

func record_role(player: Node, action: String, amount: float) -> float:
	team.game = game
	return team.award_role(player,action,amount)

func record_activity(player: Node) -> void:
	team.game = game
	team.participate(player)

func record_drive(player: Node, vehicle: Node2D, distance: float) -> void:
	team.game = game
	team.record_drive(player,vehicle,distance)

func record_craft(player: Node, recipe_id: String) -> void:
	record_role(player,"craft",4.0)
	counters.crafted=mini(1000000,int(counters.crafted)+1)
	_schedule_save()
	if int(counters.crafted)>=5: unlock("craft_five")
	event.emit("craft", {"player_id":player.player_id, "recipe":recipe_id})
	if recipe_id.begins_with("armor"):
		unlock("armor")

func record_mined(amount: int, player: Node = null) -> void:
	if amount<=0 or amount>100: return
	if is_instance_valid(player): record_activity(player)
	counters.mined=mini(1000000,int(counters.mined)+amount)
	_schedule_save()
	if int(counters.mined)>=50: unlock("miner_50")

func record_campaign_event(kind: String, data: Dictionary={}) -> void:
	match kind:
		"route_complete":
			unlock("convoy_route")
			var fuel=data.get("fuel",-1)
			if (fuel is float or fuel is int) and float(fuel)>=0 and float(fuel)<1: unlock("last_drop")
		"occupation_complete":
			unlock("base_capture")
			if data.get("cargo_count",0) is int and int(data.get("cargo_count",0))>=18: unlock("loaded_arrival")
		"roadside_complete":
			unlock("roadside")
			if str(data.get("weapon","")) in CampaignCatalog.EPIC_WEAPONS: unlock("epic_weapon")
		"campaign_complete": unlock("all_routes")

func _watch_research() -> void:
	if not is_instance_valid(game): return
	var upgrades=game.get("upgrades")
	if not is_instance_valid(upgrades) or not "owned" in upgrades: return
	var basis:=0
	for entry in UpgradeSystem.NODES:
		if not upgrades.has_upgrade(entry.id): continue
		unlock("research_first")
		if int(entry.branch)==0: basis+=1
		if int(entry.branch)==3: unlock("convoy_upgrade")
	if basis>=3: unlock("base_engineer")

func _victory_secrets() -> void:
	if not is_instance_valid(game): return
	var session = game.get("network")
	# Only the host knows the complete damage history. Guests receive the
	# authoritative achievement IDs through the existing event/snapshot path.
	if is_instance_valid(session) and session.active and not session.is_host: return
	var rounds=game.get("rounds")
	if is_instance_valid(rounds) and int(rounds.wave)<20: return
	if "players" in game and game.players.size()==1: unlock("solo_victory")
	var core=game.get("core")
	if is_instance_valid(core) and not bool(core.get_meta("achievement_core_damaged",false)) and core.hp>=core.max_hp: unlock("pristine_core")

func _exit_tree() -> void:
	if _dirty: _save_records()
	platform.set_provider(null)

func record_deploy(player: Node, kind: String) -> void:
	record_activity(player)
	unlock("turret" if kind == "sentry_kit" else "trap")
	event.emit("deploy", {"player_id":player.player_id, "kind":kind, "position":player.global_position})

func announce_boss(enemy: Node2D, title: String, final_boss: bool = false) -> void:
	_boss = weakref(enemy)
	enemy.set_meta("boss_title", title)
	event.emit("boss", {"title":title, "subtitle":"ENDGEGNER / SIGNAL 20" if final_boss else LocaleText.format("SCHWERER KONTAKT / WELLE %02d", enemy.wave), "portrait":enemy.kind, "final_boss":final_boss})

func boss_status() -> Dictionary:
	if _boss == null:
		return {}
	var enemy = _boss.get_ref()
	if not is_instance_valid(enemy) or enemy.dead:
		return {}
	return {"title":enemy.get_meta("boss_title", "SCHWERER KONTAKT"), "hp":enemy.hp, "max_hp":enemy.max_hp, "phase":int(enemy.get_meta("boss_phase",1)), "final_boss":bool(enemy.get_meta("final_boss",false))}
