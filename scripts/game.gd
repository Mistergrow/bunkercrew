extends Node2D

const PLAYER = preload("res://scenes/player.tscn")
const PICKUP = preload("res://scenes/resource_pickup.tscn")
const ENEMY = preload("res://scenes/enemy.tscn")
const AIR_ENEMY = preload("res://scenes/air_enemy.tscn")
const NetInput := preload("res://scripts/network_input.gd")
const Content := preload("res://scripts/content_registry.gd")
var network
var social
var social_bridge
var campaign: CampaignState
var expedition
var air_raid_intro
var travel_cinematic
var player_count = 1
var started = false
var players: Array = []
var ladders: Array[Rect2] = [Rect2(218, 205, 44, 400), Rect2(320, 560, 44, 240)]
var core
var turret
var rounds
var hud
var scenery
var weather
var dressing
var audio
var microphone
var voice
var speech_bubbles
var story
var solo_story
var solo_tutorial
var dialogue
var story_mode := false
var upgrades
var expansion
var environment_growth
var dome
var combat_events
var combat_gore
var perimeter
var _gore_serial:=0
var workshop
var flak_station
var medic
var scenario_bunker: ScenarioBunker
var scenario_combat: ScenarioCombat
var scenario_options: Dictionary = {}
var world_left := 70.0
var selected_characters: Array[String] = ["mara", "branko", "ivo", "nora"]
var camera: Camera2D
var player_camera
var floor_levels: Array[float] = [245.0,430.0,600.0,800.0]
var depth_unlocked := false
var view_stage := 1
var world_right := 1400.0
var camera_target_zoom := 1.0
var camera_target_center := Vector2(720,450)
var elapsed = 0.0
var notice = ""
var notice_time = 0.0
var stats = {"mined": 0, "produced": 0, "built": 0, "kills": 0}
var _restart_pending := false

func _ready() -> void:
	var content_errors := Content.diagnostics()
	if not content_errors.is_empty():
		set_process(false)
		set_physics_process(false)
		var failure := preload("res://scripts/content_startup_error.gd").new()
		failure.diagnostics = content_errors
		add_child(failure)
		return
	campaign = CampaignState.new()
	InputSetup.install()
	ThemeDB.fallback_font = UiArt.FONT
	combat_gore = preload("res://scripts/combat_gore.gd").new()
	combat_gore.game = self
	add_child(combat_gore)
	combat_events = preload("res://scripts/combat_events.gd").new()
	combat_events.game = self
	add_child(combat_events)
	upgrades = preload("res://scripts/upgrade_system.gd").new()
	upgrades.game = self
	add_child(upgrades)
	camera = Camera2D.new()
	camera.position = Vector2(720,450)
	add_child(camera)
	player_camera = preload("res://scripts/player_camera.gd").new()
	player_camera.game = self
	camera.add_child(player_camera)
	weather = preload("res://scripts/weather.gd").new()
	weather.game = self
	weather.z_index = -5
	add_child(weather)
	rounds = preload("res://scripts/round_controller.gd").new()
	rounds.game = self
	add_child(rounds)
	rounds.finished.connect(_finished)
	rounds.phase_changed.connect(_round_phase_changed)
	audio = preload("res://scripts/audio.gd").new()
	add_child(audio)
	microphone = preload("res://scripts/microphone_check.gd").new()
	add_child(microphone)
	voice = preload("res://scripts/voice_chat.gd").new()
	voice.game = self
	add_child(voice)
	speech_bubbles = preload("res://scripts/worker_speech_bubbles.gd").new()
	speech_bubbles.name = "WorkerSpeechBubbles"
	speech_bubbles.game = self
	add_child(speech_bubbles)
	expedition = preload("res://scripts/expedition_controller.gd").new()
	expedition.game = self
	add_child(expedition)
	solo_story = preload("res://scripts/solo_story_controller.gd").new()
	solo_story.game = self
	add_child(solo_story)
	solo_tutorial = preload("res://scripts/solo_tutorial_controller.gd").new()
	solo_tutorial.game = self
	add_child(solo_tutorial)
	air_raid_intro = preload("res://scripts/air_raid_intro.gd").new()
	air_raid_intro.game = self
	add_child(air_raid_intro)
	travel_cinematic = preload("res://scripts/travel_cinematic_controller.gd").new()
	travel_cinematic.game = self
	add_child(travel_cinematic)
	hud = preload("res://scripts/hud.gd").new()
	hud.game = self
	add_child(hud)
	get_tree().paused = true
	network = get_tree().root.get_node_or_null("NetworkSession")
	if network==null:
		network = preload("res://scripts/network_session.gd").new()
		network.name = "NetworkSession"
		add_child(network)
	network.bind_game(self)
	social = get_node_or_null("/root/SocialHub")
	if is_instance_valid(social):
		social_bridge = preload("res://scripts/social_game_bridge.gd").new()
		social_bridge.game = self
		add_child(social_bridge)
	if get_tree().has_meta("session_preferences"):
		var preferences: Dictionary=get_tree().get_meta("session_preferences")
		get_tree().remove_meta("session_preferences")
		restore_session_preferences(preferences)
	if get_tree().has_meta("expedition_resume"):
		var departure: Dictionary = get_tree().get_meta("expedition_resume")
		get_tree().remove_meta("expedition_resume")
		expedition.restore.call_deferred(departure)
	elif get_tree().has_meta("match_restart"):
		var setup: Dictionary = get_tree().get_meta("match_restart")
		get_tree().remove_meta("match_restart")
		_resume_restart.call_deferred(setup)

func _build_legacy_world() -> void:
	scenery = preload("res://scripts/scenery.gd").new()
	scenery.game = self
	scenery.z_index = -10
	add_child(scenery)
	dressing = preload("res://scripts/level_dressing.gd").new()
	dressing.game = self
	add_child(dressing)
	_make_terrain()
	var front = preload("res://scripts/bunker_front.gd").new()
	front.game = self
	add_child(front)
	expansion = preload("res://scripts/expansion_controller.gd").new()
	expansion.game = self
	add_child(expansion)
	environment_growth = preload("res://scripts/environment_growth.gd").new()
	environment_growth.game = self
	add_child(environment_growth)
	dome = _entity("dome_controller", Vector2.ZERO)
	core = _entity("core", Vector2(150, 430))
	_entity("station", Vector2(463, 600), {"kind": "mixer"})
	_entity("station", Vector2(660, 800), {"kind": "furnace"})
	_entity("supply", Vector2(555, 600), {"kind": "sand", "amount": 12})
	_entity("supply", Vector2(675, 600), {"kind": "concrete", "amount": 8})
	_entity("supply", Vector2(580, 430), {"kind": "steel", "amount": 6})
	_entity("supply", Vector2(648, 245), {"kind": "ammo", "amount": 18})
	_entity("wall", Vector2(665, 430), {"initial_state": 4})
	_entity("wall", Vector2(755, 430), {"initial_state": 4})
	_entity("wall", Vector2(845, 430), {"initial_state": 0})
	turret = _entity("turret", Vector2(735, 245))
	workshop = _entity("field_workshop", Vector2(945, 1020))
	workshop.refresh_access()
	flak_station = _entity("flak_station", Vector2(515, 430))
	# Pockets flank a permanent route from the ladder to the furnace.
	# No mandatory production access may depend on clearing a mining tile.
	for row in range(3):
		for col in range(3):
			_entity("mine_block", Vector2(154 + col * 48, 680 + row * 48), {"kind": "ore" if (row + col) % 2 == 0 else "sand"})
	for row in range(3):
		for col in range(6):
			_entity("mine_block", Vector2(858 + col * 48, 680 + row * 48), {"kind": "ore" if col % 2 == 0 else "sand"})
	perimeter=preload("res://scripts/perimeter_controller.gd").new()
	add_child(perimeter)
	perimeter.bootstrap(self)
	_spawn_player(1)
	medic = _entity("field_medic", Vector2(205,430))

func _entity(scene_name: String, pos: Vector2, properties: Dictionary = {}):
	var n = load("res://scenes/" + scene_name + ".tscn").instantiate()
	n.position = pos
	n.game = self
	for key in properties:
		n.set(key, properties[key])
	add_child(n)
	return n

func _spawn_player(id: int) -> void:
	if id < 1 or id > PartyConfig.MAX_PLAYERS: return
	selected_characters = PartyConfig.normalize_characters(selected_characters)
	var p = PLAYER.instantiate()
	p.game = self
	p.player_id = id
	p.character_id = selected_characters[id-1]
	p.position = Vector2(305 + (id - 1) * 42, 430)
	if is_instance_valid(scenario_bunker):
		p.position=scenario_bunker.spawn_position(id)
	add_child(p)
	players.append(p)
	p.configure_character(selected_characters[id-1])
	combat_events.track_player(p)

func start_scenario(count: int, options: Dictionary) -> void:
	if started: return
	var keep_reduced_effects: bool = is_instance_valid(weather) and weather.reduced_effects
	scenario_options=ScenarioCatalog.validate(options)
	if is_instance_valid(audio): audio.set_environment(str(scenario_options.environment))
	ScenarioCatalog.last_selection=scenario_options.duplicate()
	if has_meta("medic_storage_provisioned"): remove_meta("medic_storage_provisioned")
	if has_meta("expedition_delivery"): remove_meta("expedition_delivery")
	preload("res://scripts/medic_storage.gd").clear_reserve(self)
	# Keep menus and session systems. Remove the complete original world before
	# placing the chosen blueprint; no hidden legacy floors or stations remain.
	var keep: Array=[camera,combat_events,combat_gore,upgrades,rounds,audio,microphone,voice,speech_bubbles,hud,network,expedition,solo_story,solo_tutorial,air_raid_intro,travel_cinematic,social_bridge]
	for child in get_children():
		if child in keep: continue
		remove_child(child)
		child.queue_free()
	combat_gore.clear()
	_gore_serial=0
	perimeter=null
	players.clear()
	ladders.clear()
	floor_levels.clear()
	scenery=null
	weather=null
	dressing=null
	expansion=null
	environment_growth=null
	dome=null
	core=null
	turret=null
	workshop=null
	flak_station=null
	medic=null
	story=null
	dialogue=null
	world_left=-250.0
	world_right=1690.0
	scenario_bunker=ScenarioBunker.new()
	scenario_bunker.game=self
	scenario_bunker.configure(str(scenario_options.build_type),str(scenario_options.position))
	scenario_combat=ScenarioCombat.new()
	scenario_combat.configure(str(scenario_options.position),world_left,world_right,430.0,scenario_bunker.room_left,scenario_bunker.room_right,scenario_bunker.core_x)
	scenery=ScenarioScenery.new()
	scenery.game=self
	scenery.environment_id=str(scenario_options.environment)
	scenery.z_index=-10
	add_child(scenery)
	dressing=Node2D.new()
	dressing.name="ScenarioDecorations"
	add_child(dressing)
	environment_growth=preload("res://scripts/environment_growth.gd").new()
	environment_growth.game=self
	add_child(environment_growth)
	add_child(scenario_bunker)
	expansion=scenario_bunker
	weather=preload("res://scripts/weather.gd").new()
	weather.game=self
	weather.z_index=-5
	add_child(weather)
	weather.set_reduced_effects(keep_reduced_effects)
	scenario_bunker.bootstrap()
	perimeter=preload("res://scripts/perimeter_controller.gd").new()
	add_child(perimeter)
	perimeter.bootstrap(self)
	dome=preload("res://scripts/dome_controller.gd").new()
	dome.game=self
	dome.configure_for_scenario(scenario_bunker.room_left,scenario_bunker.room_right,flak_station.gun_position.x)
	add_child(dome)
	_spawn_player(1)
	update_scenario_camera()
	start(count)
	dialogue=load("res://scripts/story_dialogue.gd").new()
	dialogue.game=self
	add_child(dialogue)
	expedition.start_defense()
	solo_story.begin()
	story=preload("res://scripts/story_director.gd").new()
	story.game=self
	add_child(story)
	# Only the entry bunker repeats its tutorial. Subsequent solo chapters have
	# their own encounters and objectives; cooperative story rules stay intact.
	story.begin(story_mode and not (solo_story.enabled and campaign.pending_node!=CampaignCatalog.ENTRY))
	notify(LocaleText.text("Unter dem Bunker: Erde abtragen, Stützen setzen, Räume ausbauen."))
	if story.enabled: notify(LocaleText.text("DAS LETZTE SIGNAL · Baue die markierte Mauer · Beton liegt in der Kiste daneben"))
	elif solo_story.enabled: notify(LocaleText.format("Das letzte Signal · %s · J Logbuch",str(solo_story.objective().title)))

func start(count: int = 1) -> void:
	if not started and not is_instance_valid(scenario_bunker) and not is_instance_valid(core):
		_build_legacy_world()
	if started:
		return
	player_count = clampi(count, 1, PartyConfig.MAX_PLAYERS)
	selected_characters = PartyConfig.normalize_characters(selected_characters)
	while players.size() < player_count:
		_spawn_player(players.size() + 1)
	for p in players:
		p.configure_character(selected_characters[p.player_id-1])
	started = true
	get_tree().paused = false
	hud.overlay = ""
	rounds.start_round(player_count)
	if is_instance_valid(audio):
		var music_seed: int=network._generation if is_instance_valid(network) and network.active else 0
		audio.begin_live_music(str(scenario_options.get("environment","sector07")),music_seed)
	notify(LocaleText.text("E: aufnehmen / halten: arbeiten · Tab: Material wählen · Q: ablegen · F1: Hilfe"))
	sound("start")

func join_coop() -> void:
	if is_instance_valid(air_raid_intro) and air_raid_intro.active: return
	if is_instance_valid(solo_story) and solo_story.enabled:
		notify(LocaleText.text("Diese Geschichte gehört deiner Solo-Crew. Starte für Mitspieler eine Koop-Schicht im Hauptmenü."))
		return
	if is_instance_valid(network) and network.active:
		return
	if player_count >= PartyConfig.MAX_PLAYERS or not started:
		return
	var reserved := campaign.reserved_crew_snapshot(player_count+1,selected_characters[player_count]) if campaign.active else {}
	if not reserved.is_empty() and not campaign.activate_reserved_crew(player_count+1,selected_characters[player_count]):
		notify(campaign.last_error)
		return
	player_count += 1
	_spawn_player(player_count)
	var joined = players.back()
	var slot := str(player_count)
	if campaign.active:
		campaign.player_count=player_count
		campaign.character_ids=selected_characters.duplicate()
		if not reserved.is_empty():
			CampaignBonus.restore_player(joined,campaign)
		elif not campaign.completed.is_empty():
			# Joining adds the new partner; it must not bank the current driver's
			# uncommitted progress from a defense that can still be lost.
			campaign.snapshots[slot]=CampaignBonus.snapshot_player(joined)
		if reserved.is_empty() and not campaign.expedition.departure.is_empty():
			campaign.expedition.departure.snapshots[slot]=CampaignBonus.snapshot_player(joined)
		if expedition.stage in ["travel","stop","occupation"] and is_instance_valid(expedition.vehicle):
			joined.position=expedition.vehicle.position+Vector2(-125,0)
			if expedition.stage in ["travel","stop"]: expedition.vehicle.board_any(joined)
	notify(LocaleText.text("P2 ist dabei · Pfeiltasten + Enter oder Controller") if player_count==2 else LocaleText.format("P%d ist dabei · Controller %d", [player_count,player_count-1]))

func _process(delta: float) -> void:
	if started:
		elapsed += delta
	notice_time = maxf(0, notice_time - delta)

func camera_settings() -> Dictionary:
	return player_camera.settings()

func set_camera_mode(value: String) -> void:
	player_camera.set_mode(value)

func set_camera_zoom(value: float) -> void:
	player_camera.set_zoom(value)

func reset_camera_view() -> void:
	player_camera.reset_view()

func _physics_process(_delta: float) -> void:
	if is_instance_valid(network) and network.active and not network.is_host:
		return
	if started:
		for player in players:
			if NetInput.just_pressed(player,"deploy") and player.can_act():
				workshop.deploy(player)

func _round_phase_changed() -> void:
	if rounds.wave >= 6 or (rounds.wave == 5 and rounds.phase == "salvage"):
		flak_station.unlock()
	if rounds.phase == "salvage":
		if rounds.wave >= 5:
			combat_events.unlock("wave_five")
		set_view_stage(1 + int(rounds.wave / Balance.EXPANSION_INTERVAL))
	elif rounds.phase == "build":
		set_view_stage(1 + int((rounds.wave - 1) / Balance.EXPANSION_INTERVAL))

func set_view_stage(stage: int) -> void:
	stage = clampi(stage, 1, 4)
	if is_instance_valid(scenario_bunker):
		view_stage=maxi(view_stage,stage)
		depth_unlocked=view_stage>=2
		scenario_bunker.on_view_stage(view_stage)
		if view_stage>=4 and is_instance_valid(dome): dome.unlock()
		update_scenario_camera()
		return
	if stage <= view_stage:
		return
	if stage >= 2:
		unlock_depth()
	if stage >= 3:
		view_stage = 3
		world_right = 1740.0
		# Frame both the flak platform and the deepest floor above the fixed HUD.
		camera_target_zoom = 0.50
		camera_target_center = Vector2(820,650)
		expansion.unlock_deeper()
		environment_growth.open_exterior()
	if stage >= 4:
		view_stage = 4
		world_right = 1840.0
		camera_target_zoom = 0.48
		camera_target_center = Vector2(850,630)
		dome.unlock()
		environment_growth.open_dome_yard()
		notify(LocaleText.text("KUPPELBAU FREI · T: FESTUNG · Stahl, Panzerstahl und Glas zum äußeren Baupult"))

func unlock_depth() -> void:
	if is_instance_valid(scenario_bunker):
		set_view_stage(2)
		return
	if depth_unlocked:
		return
	depth_unlocked = true
	view_stage = maxi(view_stage, 2)
	camera_target_zoom = 0.62
	camera_target_center = Vector2(760,525)
	expansion.unlock()
	environment_growth.open_glassworks()
	notify(LocaleText.text("GLASWERK + TIEFBAU FREI · Schacht in der Mine öffnen · Sand + Kalkstein → Glas"))

func update_scenario_camera() -> void:
	if not is_instance_valid(scenario_bunker): return
	var stage:=clampi(maxi(view_stage,scenario_bunker.excavation_depths),1,4)
	camera_target_zoom=[1.0,0.78,0.63,0.48][stage-1]
	camera_target_center=Vector2(720,[450.0,500.0,600.0,740.0][stage-1])

func valid_focus(player, target) -> bool:
	return _valid_focus_player(player) and _reachable_focus_point(player, target, player.global_position - Vector2(0, 20)).is_finite()

func _valid_focus_player(player) -> bool:
	if not is_instance_valid(player) or not player is Node2D or player.is_queued_for_deletion() or not player.is_inside_tree():
		return false
	return player.get("game") == self and player.get_world_2d() == get_world_2d()

func _reachable_focus_point(player: Node2D, target, center: Vector2) -> Vector2:
	if not is_instance_valid(target) or not target is Node2D or target.is_queued_for_deletion() or not target.is_inside_tree():
		return Vector2.INF
	# SceneTree groups also contain actors and targets from other game worlds.
	if target.get_world_2d() != get_world_2d():
		return Vector2.INF
	if ("game" in target and target.get("game") != self) or (not "game" in target and not is_ancestor_of(target)):
		return Vector2.INF
	if target is CanvasItem and not target.is_visible_in_tree():
		return Vector2.INF
	var point: Vector2
	if target.is_in_group("mine_blocks") and target.has_method("surface_near"):
		point = target.surface_near(center)
		if not point.is_finite() or center.distance_squared_to(point) > 88.0 * 88.0:
			return Vector2.INF
	else:
		point = target.interaction_point() if target.has_method("interaction_point") else target.global_position - Vector2(0, 20)
		if not point.is_finite() or absf(center.y - point.y) > 68 or center.distance_squared_to(point) > 83.0 * 83.0:
			return Vector2.INF
	# Expensive reachability rays and inventory checks matter only in range.
	if target.has_method("can_interact") and not target.can_interact(player):
		return Vector2.INF
	return point

func _focus_score(player, target, point: Vector2, center: Vector2) -> float:
	var distance := center.distance_to(point)
	var score := distance
	# Survey panels never steal held mining from earth beside the shaft.
	if target is ScenarioRoomSite and not target.excavated():
		score += 120.0
	if is_instance_valid(story) and target == story.relay and story.stage in [2, 4, 6]:
		score -= 110.0
	if (point.x - center.x) * player.facing < -12:
		score += 14.0
	if target.is_in_group("medical_targets"):
		# Rescue remains available beside cargo and working machines.
		score -= 180.0 if target.medical.incapacitated() else (90.0 if target.medical.bleeding > 0 or target.medical.fractured else 18.0)
	if target.is_in_group("stations") and distance < 64:
		var needed := 0
		var ingredients: Array = target.input_kinds() if target.has_method("input_kinds") else [target.input_kind()]
		for ingredient in ingredients:
			needed += int(player.inventory.get(ingredient, 0))
		if target.kind == "furnace":
			needed += int(player.inventory.get("scrap", 0))
		if needed > 0 or target.output_amount > 0 or target.working:
			score -= 75.0
	elif target.is_in_group("pickups"):
		# Active stations keep priority; held mining retains its own target.
		score -= 40.0
	if target.is_in_group("convoy_vehicles") and target.get("journey_state") is Dictionary and target.journey_state.get("phase","")=="repair":
		# Covering fire creates loot near the wheel. It must not steal the next
		# tool handoff; urgent medical rescue retains its stronger priority.
		score -= Balance.CONVOY_REPAIR_FOCUS_PRIORITY
	return score

func focus_candidates(player) -> Array:
	var candidates: Array = []
	if not _valid_focus_player(player):
		return candidates
	var center: Vector2 = player.global_position - Vector2(0, 20)
	for target in get_tree().get_nodes_in_group("interactables"):
		var point := _reachable_focus_point(player, target, center)
		if not point.is_finite():
			continue
		candidates.append([target, _focus_score(player, target, point, center), candidates.size()])
	# Equal priorities keep SceneTree order in both cycling and direct selection.
	candidates.sort_custom(func(a, b): return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))
	return candidates.map(func(entry): return entry[0])

func get_focus(player):
	if not _valid_focus_player(player):
		return null
	var center: Vector2 = player.global_position - Vector2(0, 20)
	var best_target
	var best_score := INF
	for target in get_tree().get_nodes_in_group("interactables"):
		var point := _reachable_focus_point(player, target, center)
		if not point.is_finite():
			continue
		var score := _focus_score(player, target, point, center)
		if score < best_score:
			best_score = score
			best_target = target
	return best_target

func drop_material(player, kind: String, amount: int) -> bool:
	if amount <= 0 or int(player.inventory.get(kind,0)) < amount:
		return false
	var point = safe_drop_point(player)
	if point == Vector2.INF:
		notify(LocaleText.text("Zum Ablegen auf einen freien Boden treten."))
		return false
	if not player.take_item(kind,amount):
		return false
	spawn_pickup(kind,amount,point)
	sound_at("pickup",point)
	return true

func safe_drop_point(player) -> Vector2:
	var space = get_world_2d().direct_space_state
	# Prefer the facing side; never throw through walls or over the roof edge.
	for offset in [38.0,24.0,-30.0,0.0,-50.0,56.0]:
		var x: float = player.global_position.x + offset*player.facing
		var ray = PhysicsRayQueryParameters2D.create(Vector2(x,player.global_position.y-29),Vector2(x,player.global_position.y+35),1|2)
		var floor_hit = space.intersect_ray(ray)
		if floor_hit.is_empty() or floor_hit.normal.y > -0.5:
			continue
		var point: Vector2 = floor_hit.position - Vector2(0,1)
		var shape = RectangleShape2D.new()
		shape.size = Vector2(26,22)
		var probe = PhysicsShapeQueryParameters2D.new()
		probe.shape = shape
		probe.transform = Transform2D(0,point-Vector2(0,12))
		probe.collision_mask = 1|2
		if not space.intersect_shape(probe,1).is_empty():
			continue
		# Floor beneath the body is reachable even if the forward option was blocked.
		var reach = PhysicsRayQueryParameters2D.create(player.global_position-Vector2(0,14),point-Vector2(0,12),1|2)
		if not space.intersect_ray(reach).is_empty():
			continue
		return point
	return Vector2.INF

func spawn_pickup(kind: String, amount: int, pos: Vector2) -> void:
	if amount <= 0:
		return
	_place_pickup.call_deferred(kind,amount,pos)

func _place_pickup(kind: String, amount: int, pos: Vector2) -> void:
	# A restart can remove this scene before a death's deferred drops are placed.
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if not is_instance_valid(get_node_or_null("PickupMaintenance")):
		var maintenance := preload("res://scripts/pickup_maintenance.gd").new()
		maintenance.name="PickupMaintenance"
		add_child(maintenance)
	# Repeated single drops form one readable pile instead of hiding each other.
	for existing in get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(existing) or existing.is_queued_for_deletion() or existing.amount <= 0:
			continue
		if existing.game!=self or existing.amount>=Balance.PICKUP_STACK_MAX: continue
		if existing.kind != kind or absf(existing.global_position.y-pos.y) > 12 or existing.global_position.distance_to(pos) > 32:
			continue
		var ray = PhysicsRayQueryParameters2D.create(pos-Vector2(0,10),existing.global_position-Vector2(0,10),1|2)
		ray.hit_from_inside = true
		if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		var moved: int = mini(amount,Balance.PICKUP_STACK_MAX-existing.amount)
		existing.amount += moved
		amount-=moved
		existing.queue_redraw()
		if amount==0: return
	while amount>0:
		var drop = PICKUP.instantiate()
		drop.game = self
		drop.kind = kind
		drop.amount = mini(amount,Balance.PICKUP_STACK_MAX)
		drop.position = pos
		add_child(drop)
		amount-=drop.amount

func air_defense_ready() -> bool:
	if is_instance_valid(perimeter) and perimeter.air_defense_ready(): return true
	return is_instance_valid(flak_station) and flak_station.built and is_instance_valid(flak_station.turret) and not flak_station.turret.is_queued_for_deletion() and flak_station.turret.hp > 0

func defer_air_spawn(wave: int, index: int, total: int) -> bool:
	return is_instance_valid(air_raid_intro) and air_raid_intro.before_spawn(wave,index,total)

func spawn_enemy(wave: int, index: int = -1, total: int = 0) -> void:
	var final_boss := wave == Balance.TOTAL_WAVES and total > 0 and index == total-1
	var kind := "strider"
	var roster: Array=[]
	if index >= 0:
		# Building mid-wave never introduces aircraft without the prior warning.
		# A disabled tower replaces remaining air slots with ordinary ground units.
		var allow_air: bool = air_defense_ready() and is_instance_valid(rounds) and rounds.air_wave_enabled
		roster = EnemyCatalog.wave_roster(wave,total,allow_air)
		if not roster.is_empty():
			kind = roster[index % roster.size()]
	if AirEnemyCatalog.is_air(kind):
		var active_air := 0
		for aircraft in get_tree().get_nodes_in_group("air_enemies"):
			if aircraft.get("game") == self and not aircraft.is_queued_for_deletion() and not aircraft.get("dead"):
				active_air += 1
		if active_air >= AirEnemyCatalog.MAX_ACTIVE:
			# Keep the announced wave population finite while preserving ground pressure.
			kind = "strider"
	var human: bool=EnemyCatalog.is_human(kind)
	var scene: PackedScene = preload("res://scenes/boss_enemy.tscn") if final_boss else (preload("res://scenes/ground_infantry.tscn") if human else (AIR_ENEMY if AirEnemyCatalog.is_air(kind) else ENEMY))
	var enemy = scene.instantiate()
	enemy.game = self
	enemy.wave = wave
	enemy.kind = kind
	if index >= 0:
		enemy.elite = EnemyCatalog.is_elite(wave,index,total)
	enemy.position = Vector2(maxf(1400,world_right+50), 430)
	var approach_index:=index
	if human:
		var team_slots: Array[int]=[]
		for slot in roster.size():
			if EnemyCatalog.is_human(roster[slot]): team_slots.append(slot)
		approach_index=team_slots[0]
		enemy.squad_slot=team_slots.find(index)
	if scenario_combat!=null:
		scenario_combat.configure_enemy(enemy,wave,approach_index)
	add_child(enemy)
	if EnemyCatalog.is_elite(wave,index,total):
		combat_events.announce_boss(enemy,{5:"WACHBRECHER",10:"DER PFÖRTNER",15:"EISENFAUST",20:"MUTTERMASCHINE"}.get(wave,"SCHWERER KONTAKT"),final_boss)

func combat_hit(enemy: Node, amount: float, worker: Node = null) -> float:
	# Attribute only health actually removed, once, at the authoritative hit site.
	# Muzzle flashes, misses, terrain and overkill never create experience.
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not enemy.is_in_group("enemies") or not enemy.has_method("take_damage") or not is_finite(amount) or amount <= 0:
		return 0.0
	if enemy.dead or enemy.hp <= 0:
		return 0.0
	var before: float = enemy.hp
	var at: Vector2 = enemy.global_position-Vector2(0,enemy.body_height)
	enemy.take_damage(amount)
	var applied := maxf(0.0,before-float(enemy.hp))
	if applied>0 and not enemy.is_in_group("human_enemies"):
		combat_contact(enemy,applied,enemy.dead)
	if applied > 0 and is_instance_valid(worker) and worker in players:
		combat_events.credit_hit(enemy,applied,worker,enemy.dead,at)
	return applied

func combat_contact(target: Node2D, applied: float, incapacitated: bool) -> void:
	if not is_instance_valid(combat_gore) or not is_instance_valid(target): return
	if is_instance_valid(network) and network.active and not network.is_host: return
	var actor_id: String=str(target.get_meta("network_entity_id",""))
	if is_instance_valid(network) and network.world!=null:
		actor_id=network.world._id(target)
	elif actor_id.is_empty():
		actor_id="player:%d"%target.player_id if target.is_in_group("players") else "local:%d"%target.get_instance_id()
		target.set_meta("network_entity_id",actor_id)
	var data: Dictionary=combat_gore.make_event(target,applied,incapacitated)
	if not preload("res://scripts/combat_gore_protocol.gd").valid_data(data): return
	_gore_serial+=1
	combat_gore.present(data,target,actor_id)
	if is_instance_valid(network): network.queue_event("gore",{"serial":_gore_serial,"actor":actor_id,"data":data})

func fx(pos: Vector2, color: Color = Art.AMBER, count: int = 8) -> void:
	if is_instance_valid(network): network.queue_event("fx",{"at":pos,"color":color,"count":count})
	var effect = preload("res://scripts/effect.gd").new()
	effect.position = pos
	effect.color = color
	effect.count = count
	effect.reduced = is_instance_valid(weather) and weather.reduced_effects
	add_child(effect)

func impact(pos: Vector2, impact_material: String, direction: Vector2 = Vector2.LEFT, power: float = 1.0) -> void:
	if impact_material=="explosion":
		preload("res://scripts/scenery_damage.gd").explosion(self,pos+direction.normalized()*2.0,72.0*power,48.0*power)
	if is_instance_valid(network): network.queue_event("impact",{"at":pos,"material":impact_material,"direction":direction,"power":power})
	var burst = preload("res://scripts/impact_burst.gd").new()
	burst.position = pos
	burst.surface_material = impact_material
	burst.direction = direction
	burst.power = power
	burst.reduced = is_instance_valid(weather) and weather.reduced_effects
	add_child(burst)

func sound(kind: String) -> void:
	if is_instance_valid(network): network.queue_event("sound",{"kind":kind})
	if is_instance_valid(audio):
		audio.play_sound(kind)

func sound_at(kind: String,at: Vector2) -> void:
	if not at.is_finite(): return
	if is_instance_valid(network): network.queue_event("sound",{"kind":kind,"at":at})
	if is_instance_valid(audio): audio.play_sound_at(kind,at)

func notify(message: String) -> void:
	notice = message
	notice_time = 5.0

func on_core_destroyed() -> void:
	if is_instance_valid(rounds):
		rounds.defeat()

func _finished(won: bool) -> void:
	if is_instance_valid(story): story.finish(won)
	if won:
		if rounds.wave>=Balance.TOTAL_WAVES and CampaignCatalog.site_kind(campaign.pending_node)=="bunker": combat_events.unlock("victory")
		expedition.on_victory()
	elif campaign.active:
		campaign.fail_mission()
	hud.overlay = "campaign_victory" if won and CampaignCatalog.all_complete(campaign.completed) else ("victory" if won else "defeat")
	if is_instance_valid(network) and network.active:
		network.match_paused = true
	get_tree().paused = true

func restart() -> bool:
	if _restart_pending or is_queued_for_deletion(): return false
	if is_instance_valid(network) and network.active:
		if not network.is_host or not started or network._loading or network.state!="playing": return false
		return network.restart_match()
	if not started: return return_to_menu()
	if is_instance_valid(expedition) and expedition.transitioning: return false
	var setup := {
		"count":player_count,"characters":selected_characters.duplicate(),
		"story":story_mode,"legacy":not is_instance_valid(scenario_bunker),
		"options":scenario_options.duplicate(),
		"campaign":expedition.restart_payload() if is_instance_valid(expedition) else {},
	}
	_restart_pending = true
	get_tree().set_meta("session_preferences",session_preferences())
	get_tree().set_meta("match_restart",setup)
	get_tree().paused = false
	get_tree().reload_current_scene.call_deferred()
	return true

func _resume_restart(setup: Dictionary) -> void:
	selected_characters = PartyConfig.normalize_characters(setup.get("characters",[]))
	story_mode = bool(setup.get("story",false))
	var checkpoint: Dictionary = setup.get("campaign",{})
	if not checkpoint.is_empty():
		expedition.restore(checkpoint)
	elif bool(setup.get("legacy",false)):
		start(int(setup.get("count",1)))
	else:
		start_scenario(int(setup.get("count",1)),setup.get("options",{}))

func return_to_menu() -> bool:
	if _restart_pending or is_queued_for_deletion(): return false
	_restart_pending = true
	get_tree().set_meta("session_preferences",session_preferences())
	if is_instance_valid(network) and network.active: network.leave()
	for key in ["expedition_resume","match_restart"]:
		if get_tree().has_meta(key): get_tree().remove_meta(key)
	get_tree().paused = false
	get_tree().reload_current_scene.call_deferred()
	return true

func session_preferences() -> Dictionary:
	# Keep local choices in memory as well as on disk. A mission transition must
	# retain the latest slider values and permanent cosmetics even without saves.
	return {
		"camera":player_camera.settings(),
		"audio":{
			"music":audio.music_volume,"sfx":audio.sfx_volume,"voice":audio.voice_volume,
			"live":audio.live_music_enabled,"style":audio.music_style,
			"reduced_motion":audio.rhythm_motion_reduced,"calibration":audio.music_calibration_seconds,
			"dance_intensity":audio.dance_intensity,"dance_profiles":audio.dance_profiles.duplicate(true),
		},
		"reduced_effects":is_instance_valid(weather) and weather.reduced_effects,
		"records":combat_events.session_records(),
		"solo_story":solo_story.records.capture() if is_instance_valid(solo_story) else {},
		"solo_tutorial":solo_tutorial.session_records() if is_instance_valid(solo_tutorial) else {},
		"offline_crew_archive":campaign.offline_crew_archive.duplicate(true),
	}

func restore_session_preferences(preferences: Dictionary) -> void:
	var view: Dictionary=preferences.get("camera",{})
	player_camera.set_mode(str(view.get("mode","follow")))
	player_camera.set_zoom(float(view.get("zoom",player_camera.DEFAULT_ZOOM)))
	var channels: Dictionary=preferences.get("audio",{})
	audio.set_music_volume(float(channels.get("music",audio.music_volume)))
	audio.set_sfx_volume(float(channels.get("sfx",audio.sfx_volume)))
	audio.set_voice_volume(float(channels.get("voice",audio.voice_volume)))
	audio.set_live_music_enabled(bool(channels.get("live",audio.live_music_enabled)))
	audio.set_music_style(str(channels.get("style",audio.music_style)))
	audio.set_rhythm_motion_reduced(bool(channels.get("reduced_motion",audio.rhythm_motion_reduced)))
	audio.set_music_calibration(float(channels.get("calibration",audio.music_calibration_seconds)))
	audio.set_dance_configuration(float(channels.get("dance_intensity",audio.dance_intensity)),channels.get("dance_profiles",audio.dance_profiles))
	weather.set_reduced_effects(bool(preferences.get("reduced_effects",false)))
	combat_events.restore_session_records(preferences.get("records",{}))
	var story_records: Variant = preferences.get("solo_story",{})
	if story_records is Dictionary and is_instance_valid(solo_story): solo_story.records.restore(story_records)
	if is_instance_valid(solo_tutorial): solo_tutorial.restore_session_records(preferences.get("solo_tutorial",{}))
	var parked: Variant = preferences.get("offline_crew_archive",{})
	if OfflineCampaignArchive.valid(parked): campaign.offline_crew_archive=parked.duplicate(true)

func _make_terrain() -> void:
	# Permanent floor slabs. Ladders let workers pass through them while climbing.
	for rect in [Rect2(75,245,675,18), Rect2(75,430,1365,22), Rect2(75,600,700,22), Rect2(75,800,1120,26), Rect2(58,245,16,580), Rect2(1195,622,24,204)]:
		add_terrain(rect)

func add_terrain(rect: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)
	add_child(body)
	return body
