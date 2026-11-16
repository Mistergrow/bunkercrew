extends RefCounted
## Actor, motion, combat and performance shots of the visual-review instrument.
## Workers are driven with their real input actions; enemies are the real
## scenes spawned through game._entity and left to their own behaviour.
const ShotList := preload("res://tests/visual_review_shots.gd")
const World := preload("res://tests/visual_review_stage_world.gd")

static func night_environment() -> String:
	return str(ShotList.contrasts(ScenarioCatalog.environments(true)).night.id)

static func _front(c) -> float:
	return float(c.game.scenario_bunker.room_right) + 120.0

static func _ground(c) -> float:
	return float(c.game.scenario_bunker.ground_y)

static func _enemy_scene(kind: String) -> String:
	if AirEnemyCatalog.is_air(kind): return "air_enemy"
	return "ground_infantry" if EnemyCatalog.is_human(kind) else "enemy"

static func _intro_wave(kind: String) -> int:
	var waves: Dictionary = AirEnemyCatalog.INTRO_WAVES if AirEnemyCatalog.is_air(kind) else EnemyCatalog.INTRO_WAVES
	return int(waves.get(kind, 1))

static func _profile(kind: String) -> Dictionary:
	return AirEnemyCatalog.profile(kind) if AirEnemyCatalog.is_air(kind) else EnemyCatalog.profile(kind)

static func _enemy(c, kind: String, at: Vector2):
	return c.spawn(_enemy_scene(kind), at, {"kind": kind, "wave": _intro_wave(kind)})

static func _solo(c, spec: Dictionary, players: int = 1):
	await c.play(players, str(spec.args.environment), {"hud": false})
	if c.failed(): return null
	var worker = c.game.players[0]
	return worker

static func _place(worker, at: Vector2, facing: float = 1.0) -> void:
	worker.global_position = at
	worker.velocity = Vector2.ZERO
	worker.facing = facing

static func _build_flak(c) -> bool:
	var station = c.game.flak_station
	if not is_instance_valid(station): return false
	station.unlock()
	if not bool(station.built) and station.has_method("_complete"): station._complete()
	return bool(station.built)

# ------------------------------------------------------------------ stills
static func workers(c, spec: Dictionary) -> void:
	var ids: Array = []
	for entry: Dictionary in CharacterCatalog.CHARACTERS: ids.append(str(entry.id))
	var count := mini(ids.size(), PartyConfig.MAX_PLAYERS)
	await c.play(count, str(spec.args.environment), {"hud": false})
	if c.failed(): return
	var cast: Array = c.game.players.duplicate()
	var present: Array = []
	for worker in cast: present.append(str(worker.character_id))
	var slot := 0
	for id: String in ids:
		if id in present: continue
		var extra = c.spawn("player", Vector2.ZERO, {"player_id": 1 + slot % count, "character_id": id})
		if extra == null: return
		if extra.has_method("configure_character"): extra.configure_character(id)
		cast.append(extra)
		slot += 1
	var left := _front(c) + 40.0
	for index in cast.size(): _place(cast[index], Vector2(left + index * 54.0, _ground(c)), 1.0)
	var shown: Array = []
	for worker in cast: shown.append(str(worker.character_id))
	c.note("workers left to right: " + ", ".join(PackedStringArray(shown)))
	if shown.size() != ids.size(): c.note("%d of %d catalog characters shown" % [shown.size(), ids.size()])
	c.camera_fit(Rect2(left - 30, _ground(c) - 90, (cast.size() - 1) * 54.0 + 60, 110), 24.0, 5.0, true)
	await c.frames(50)
	await c.still()

static func enemy_row(c, spec: Dictionary) -> void:
	await _solo(c, spec)
	if c.failed(): return
	var kinds: Array = spec.args.kinds
	var air := bool(spec.args.air)
	var cursor := _front(c) + 60.0
	var area := Rect2()
	var actors: Array = []
	for kind: String in kinds:
		var profile := _profile(kind)
		var box: Vector2 = profile.get("hitbox", Vector2(80, 60))
		var width := maxf(box.x * 1.5, 70.0) + 26.0
		var at := Vector2(cursor + width * 0.5, 120.0 if air else _ground(c))
		var actor = _enemy(c, kind, at)
		if actor == null: return
		if "show_status_labels" in actor: actor.show_status_labels = true
		actors.append(actor)
		cursor += width
	await c.frames(3)
	for actor in actors:
		# Hold the line-up in place; drawing and idle animation continue.
		actor.set_physics_process(false)
		var box: Vector2 = actor.profile.get("hitbox", Vector2(80, 60))
		var bounds := Rect2(actor.global_position - Vector2(box.x * 0.8, box.y * (0.8 if air else 1.5)), Vector2(box.x * 1.6, box.y * 1.7))
		area = bounds if area.size == Vector2.ZERO else area.merge(bounds)
	c.note("left to right: " + ", ".join(PackedStringArray(kinds)))
	c.camera_fit(area, 26.0, 4.0, not air)
	await c.frames(40)
	await c.still()

static func stations(c, spec: Dictionary) -> void:
	await _solo(c, spec, 2)
	if c.failed(): return
	var bunker = c.game.scenario_bunker
	var left := float(bunker.room_left)
	var right := float(bunker.room_right)
	match str(spec.args.area):
		"production":
			c.camera_fit(Rect2(left + 90, _ground(c) - 150, right - left - 130, 165), 12.0, 4.0)
		"defense":
			if not _build_flak(c): c.note("flak tower could not be built in this build; roof shown without it")
			_place(c.game.players[0], Vector2(left + 420, 245.0))
			var top := float(c.game.flak_station.gun_position.y) - 60.0 if bool(c.game.flak_station.built) else 120.0
			c.camera_fit(Rect2(left, top, right - left + 40, 250.0 - top), 16.0, 4.0)
		"workshop":
			var built: int = await World.build_rooms(c)
			c.note("%d underground rooms built" % built)
			var floor_y := ScenarioRoomCatalog.floor_y(0)
			_place(c.game.players[0], Vector2(left + 380, floor_y))
			c.camera_fit(Rect2(left + 40, floor_y - 190, right - left - 80, 205), 12.0, 4.0)
	await c.frames(60)
	await c.still()

# ----------------------------------------------------------- worker motion
static func _stage_worker(c, spec: Dictionary, players: int = 1):
	var worker = await _solo(c, spec, players)
	if worker == null: return null
	_place(worker, Vector2(_front(c) + 120.0, _ground(c)))
	await c.frames(30)
	c.track(worker, Vector2(0, -40), 4.0)
	return worker

static func worker_idle(c, spec: Dictionary) -> void:
	var worker = await _stage_worker(c, spec)
	if worker == null: return
	await c.sequence(14, 6)

static func worker_walk(c, spec: Dictionary) -> void:
	var worker = await _stage_worker(c, spec)
	if worker == null: return
	c.hold(worker.action("right"))
	await c.frames(20)
	await c.sequence(14, 3)

static func worker_run(c, spec: Dictionary) -> void:
	var worker = await _stage_worker(c, spec)
	if worker == null: return
	c.hold(worker.action("right"))
	await c.frames(20)
	await c.sequence(14, 3, func(index: int) -> void:
		if index == 3: c.hold(worker.action("jump"))
		if index == 4: c.release(worker.action("jump")))

static func worker_carry(c, spec: Dictionary) -> void:
	var worker = await _stage_worker(c, spec)
	if worker == null: return
	worker.add_item("steel", worker.capacity())
	if worker.carried_count() == 0: c.fail("worker did not accept a load")
	c.hold(worker.action("right"))
	await c.frames(20)
	await c.sequence(14, 3)

static func worker_mine(c, spec: Dictionary) -> void:
	var worker = await _solo(c, spec)
	if worker == null: return
	var bunker = c.game.scenario_bunker
	_place(worker, Vector2(float(bunker.room_left) + 108.0, ScenarioRoomCatalog.floor_y(0)))
	await c.frames(30)
	c.track(worker, Vector2(20, -40), 4.0)
	c.hold(worker.action("interact"))
	await c.frames(24)
	if not bool(worker.mining): c.fail("worker did not start mining at the shaft footing")
	await c.sequence(14, 4)

static func worker_ladder(c, spec: Dictionary) -> void:
	var worker = await _solo(c, spec)
	if worker == null: return
	var ladder: Rect2 = c.game.ladders[0]
	for rect: Rect2 in c.game.ladders:
		if rect.size.y > ladder.size.y: ladder = rect
	_place(worker, Vector2(ladder.get_center().x, ScenarioRoomCatalog.floor_y(0)))
	await c.frames(30)
	c.track(worker, Vector2(0, -40), 3.5)
	c.hold(worker.action("up"))
	await c.frames(14)
	if not bool(worker.climbing): c.fail("worker did not enter the ladder")
	await c.sequence(14, 4)

static func worker_shoot(c, spec: Dictionary) -> void:
	var worker = await _stage_worker(c, spec)
	if worker == null: return
	c.aim(worker.global_position + Vector2(320, -70))
	await c.frames(6)
	await c.sequence(16, 8, func(index: int) -> void:
		if index == 1: c.hold(worker.action("fire"))
		if index == 6:
			c.release(worker.action("fire"))
			c.hold(worker.action("reload"))
		if index == 7: c.release(worker.action("reload")))
	var weapon = worker.get_node_or_null("WorkerWeapon")
	if is_instance_valid(weapon): c.note("ammunition after the sequence: %d loaded" % int(weapon.current_ammo()))

static func worker_hit(c, spec: Dictionary) -> void:
	var worker = await _stage_worker(c, spec)
	if worker == null: return
	await c.sequence(12, 2, func(index: int) -> void:
		if index == 2 and float(worker.take_damage(18.0, Vector2.LEFT)) <= 0.0: c.fail("the hit was not applied"))

static func worker_revive(c, spec: Dictionary) -> void:
	var worker = await _stage_worker(c, spec, 2)
	if worker == null: return
	var helper = c.game.players[1]
	_place(helper, worker.global_position + Vector2(34, 0), -1.0)
	await c.frames(20)
	c.camera_at(worker.global_position + Vector2(14, -42), 3.5)
	# Six frames 5 apart for the collapse, then ten across the revive.
	for index in 6:
		if index == 1:
			worker.take_damage(float(worker.hp) + 500.0, Vector2.LEFT)
			if not worker.is_downed(): c.fail("worker did not collapse")
		await c.sequence_frame()
		await c.frames(5)
	c.hold(helper.action("interact"))
	var duration := float(worker.medical.aid_duration()) + 1.6 if is_instance_valid(worker.medical) else 6.0
	var step := ceili(duration * 60.0 / 9.0)
	for index in 10:
		await c.sequence_frame()
		if index < 9: await c.frames(step)
	c.release(helper.action("interact"))
	c.note("second phase frames are %d simulated frames apart" % step)
	if worker.is_downed(): c.note("worker was still down at the end of the sequence")

static func worker_dance(c, spec: Dictionary) -> void:
	var worker = await _stage_worker(c, spec)
	if worker == null: return
	var visual = worker.get_node_or_null("PixelVisual")
	if not c.need(visual, "pose_skeleton"): return
	# Dances follow audible kicks of the live music. tools/visual_review.py runs
	# this shot under Godot's movie writer, which mixes audio in step with the
	# fixed 60 fps simulation; the dance moves unlock with crew experience.
	if is_instance_valid(worker.progression) and worker.progression.has_method("award_damage"): worker.progression.award_damage(13500.0)
	# The live score only drives a steady kick at combat intensity: present a
	# running wave-10 attack (as the music-dance capture does) without spawning.
	c.game.rounds.set_process(false)
	c.game.rounds.running = true
	c.game.rounds.wave = 10
	c.game.rounds.phase = "attack"
	if c.game.audio.has_method("set_music_style"): c.game.audio.set_music_style("minimal_techno")
	var dancing := false
	for index in 60 * 45:
		await c.frames(1)
		if visual.pose_skeleton is Dictionary and visual.pose_skeleton.has("dance_style"):
			dancing = true
			break
	if not dancing:
		var music = c.game.audio.get("live_music") if is_instance_valid(c.game.audio) else null
		var state := "no live music node"
		if is_instance_valid(music):
			var beat: Dictionary = music.rhythm_frame() if music.has_method("rhythm_frame") else {}
			state = "session %s, native %s, enabled %s, frame active %s, kicks %s" % [music.get("session_active"), music.get("native_active"), music.get("music_enabled"), beat.get("active"), beat.get("kick_count")]
		c.fail("worker did not start dancing within 45 simulated seconds (%s)" % state)
		return
	await c.frames(30)
	c.note("dance style: " + str(visual.pose_skeleton.get("dance_style", "")))
	await c.sequence(14, 4)

# ------------------------------------------------------------ enemy motion
static func _stage_enemy(c, spec: Dictionary, near_wall: bool, far: bool = false):
	var worker = await _solo(c, spec)
	if worker == null: return null
	var kind := str(spec.args.kind)
	var profile := _profile(kind)
	var bunker = c.game.scenario_bunker
	# Open ground between the courtyard and the outer perimeter site.
	var at := Vector2(_front(c) + 200.0, _ground(c))
	if near_wall: at.x = float(bunker.room_right) + float(profile.get("reach", 80.0)) * 0.7
	# A walk needs room: start beyond the class's reach so it is still advancing
	# when the sequence is taken (a grenadier otherwise stops within 20 frames).
	if far: at.x = minf(at.x + float(profile.get("reach", 80.0)) + 360.0, float(c.game.world_right) - 40.0)
	if bool(spec.args.air): at = Vector2(float(c.game.world_right) + 50.0, 110.0)
	var actor = _enemy(c, kind, at)
	if actor == null: return null
	if bool(spec.args.air):
		# Aircraft fly their own entry; wait until this one has arrived.
		for index in 900:
			await c.frames(1)
			if bool(actor.entered) and index > 120: break
	else:
		await c.frames(20)
	return actor

static func _frame_enemy(c, actor, air: bool, wide: bool = false) -> void:
	var box: Vector2 = actor.profile.get("hitbox", Vector2(80, 60))
	var size := maxf(box.x, box.y)
	# Zoom from the class size so small and large machines fill a similar share.
	var zoom := clampf(260.0 / size, 1.5, 4.0) * (0.75 if wide else 1.0)
	if air: c.track(actor, Vector2(-30, 60 if wide else 0), zoom)
	else: c.track(actor, Vector2(-40 if wide else 0, -maxf(box.y * 0.6, 30.0)), zoom)

static func enemy_move(c, spec: Dictionary) -> void:
	var actor = await _stage_enemy(c, spec, false, true)
	if actor == null: return
	_frame_enemy(c, actor, bool(spec.args.air))
	await c.sequence(14, 4)

static func enemy_attack(c, spec: Dictionary) -> void:
	var actor = await _stage_enemy(c, spec, true)
	if actor == null: return
	var charging := false
	for index in 60 * 40:
		await c.frames(1)
		if not is_instance_valid(actor) or bool(actor.dead):
			c.fail("enemy was destroyed before it attacked")
			return
		if float(actor.windup) > 0.0 or float(actor.get("worker_windup") if "worker_windup" in actor else 0.0) > 0.0:
			charging = true
			break
	if not charging:
		c.fail("enemy did not begin an attack within 40 simulated seconds")
		return
	var profile: Dictionary = actor.profile
	var span := float(profile.get("windup", 0.5)) + float(profile.get("burst", 1)) * float(profile.get("burst_gap", 0.2)) + 0.5
	var step := clampi(ceili(span * 60.0 / 13.0), 2, 12)
	c.note("frames are %d simulated frames apart, from the start of the wind-up" % step)
	_frame_enemy(c, actor, bool(spec.args.air), true)
	await c.sequence(14, step)

static func enemy_damage(c, spec: Dictionary) -> void:
	var actor = await _stage_enemy(c, spec, false)
	if actor == null: return
	_frame_enemy(c, actor, bool(spec.args.air))
	var holder: Array = [actor]
	await c.sequence(14, 2, func(index: int) -> void:
		if index == 2 and (not is_instance_valid(holder[0]) or float(c.game.combat_hit(holder[0], float(holder[0].max_hp) * 0.3, c.game.players[0])) <= 0.0): c.fail("the hit was not applied"))

static func enemy_die(c, spec: Dictionary) -> void:
	var actor = await _stage_enemy(c, spec, false)
	if actor == null: return
	_frame_enemy(c, actor, bool(spec.args.air), bool(spec.args.air))
	# The actor is freed after death; the callback holds it through an array.
	var holder: Array = [actor]
	await c.sequence(14, 5, func(index: int) -> void:
		if index != 1: return
		var target = holder[0]
		for attempt in 4:
			if is_instance_valid(target) and not bool(target.dead): c.game.combat_hit(target, float(target.max_hp) * 4.0, c.game.players[0])
		if is_instance_valid(target) and not bool(target.dead): c.fail("enemy survived the lethal hit"))

static func station_working(c, spec: Dictionary) -> void:
	var worker = await _solo(c, spec)
	if worker == null: return
	var machine: Node2D = null
	for station in c.get_nodes_in_group("stations"):
		if station.get("game") == c.game and station.has_method("input_kind") and "working" in station:
			machine = station
			break
	if machine == null:
		c.fail("no production station found")
		return
	var point: Vector2 = machine.interaction_point() if machine.has_method("interaction_point") else machine.global_position
	_place(worker, Vector2(point.x, _ground(c)))
	for kind in machine.input_kinds(): worker.add_item(str(kind), 4)
	await c.frames(10)
	c.hold(worker.action("interact"))
	for index in 600:
		await c.frames(1)
		if bool(machine.working): break
	c.release(worker.action("interact"))
	if not bool(machine.working): c.fail("station did not start working after loading")
	c.note("station: " + str(machine.get("kind")))
	c.camera_at(machine.global_position + Vector2(0, -55), 3.0)
	await c.frames(10)
	await c.sequence(14, 5)

# ----------------------------------------------------------------- combat
static func _stage_duel(c, spec: Dictionary, distance: float):
	var worker = await _stage_worker(c, spec)
	if worker == null: return null
	var kind := ""
	for candidate: String in EnemyCatalog.GROUND_CLASSES:
		if EnemyCatalog.is_human(candidate) or EnemyCatalog.is_vehicle(candidate): continue
		if kind.is_empty() or float(EnemyCatalog.profile(candidate).hp) > float(EnemyCatalog.profile(kind).hp): kind = candidate
	var target = _enemy(c, kind, worker.global_position + Vector2(distance, 0))
	if target == null: return null
	await c.frames(12)
	# The sturdiest machine stands as the target; it does not walk into the muzzle.
	target.set_physics_process(false)
	var box: Vector2 = target.profile.get("hitbox", Vector2(80, 60))
	c.aim(target.global_position - Vector2(0, box.y * 0.5))
	c.camera_at(worker.global_position + Vector2(distance * 0.5, -55), clampf(c.root.get_visible_rect().size.x / (distance + 260.0), 1.2, 3.0))
	await c.frames(20)
	return worker

static func rifle_single(c, spec: Dictionary) -> void:
	var worker = await _stage_duel(c, spec, 300.0)
	if worker == null: return
	await c.sequence(14, 1, func(index: int) -> void:
		if index == 1: c.hold(worker.action("fire"))
		if index == 2: c.release(worker.action("fire")))

static func mg_sustained(c, spec: Dictionary) -> void:
	var worker = await _stage_duel(c, spec, 300.0)
	if worker == null: return
	c.hold(worker.action("fire"))
	await c.frames(12)
	await c.sequence(14, 3)

static func turret_fire(c, spec: Dictionary) -> void:
	var worker = await _solo(c, spec)
	if worker == null: return
	var gun = c.game.turret
	if not c.need(gun, "enter"): return
	var kinds: Array = []
	for candidate: String in EnemyCatalog.GROUND_CLASSES:
		if not EnemyCatalog.is_human(candidate) and not EnemyCatalog.is_vehicle(candidate) and kinds.size() < 3: kinds.append(candidate)
	var targets: Array = []
	for index in kinds.size(): targets.append(_enemy(c, kinds[index], Vector2(gun.global_position.x + 330.0 + index * 90.0, _ground(c))))
	gun.enter(worker)
	await c.frames(12)
	for target in targets: target.set_physics_process(false)
	c.aim(targets[0].global_position - Vector2(0, 30))
	c.camera_fit(Rect2(gun.global_position.x - 90, gun.global_position.y - 90, 330.0 + kinds.size() * 90.0 + 60, _ground(c) - gun.global_position.y + 110), 16.0, 3.0)
	c.hold(worker.action("fire"))
	await c.frames(14)
	if not is_instance_valid(worker.mounted_turret): c.fail("worker is not on the roof gun")
	await c.sequence(14, 2)

static func flak_fire(c, spec: Dictionary) -> void:
	var worker = await _solo(c, spec)
	if worker == null: return
	if not _build_flak(c):
		c.fail("flak tower could not be built through flak_station in this build")
		return
	var tower = c.game.flak_station.turret
	var kinds: Array = Array(AirEnemyCatalog.CLASS_ORDER).slice(0, 2)
	var targets: Array = []
	for index in kinds.size(): targets.append(_enemy(c, kinds[index], Vector2(float(c.game.world_right) + 50.0 + index * 80.0, 100.0)))
	# The player mans the roof gun while the unattended tower guards the sky;
	# the game's own follow camera frames that gunner.
	var gun = c.game.turret
	if is_instance_valid(gun) and gun.has_method("enter"): gun.enter(worker)
	c.camera_game()
	var fired := false
	var before := int(tower.ammo)
	var first_shot := 0
	var waited := 0
	# From the tower's first shot, wait until an aircraft is on screen: the
	# engagement the player watches (tracers, airbursts, hits) happens there.
	while waited < 60 * 40:
		await c.frames(1)
		waited += 1
		if not fired and int(tower.ammo) < before:
			fired = true
			first_shot = waited
		if not fired: continue
		var seen := false
		for target in targets:
			if is_instance_valid(target) and not bool(target.dead) and c.view_rect().has_point(target.global_position): seen = true
		if seen: break
	if not fired:
		c.fail("flak did not open fire within 40 simulated seconds")
		return
	c.note("sequence starts %.2f s after the tower's first shot, with an aircraft on screen; game camera at %.2f px per world unit" % [(waited - first_shot) / 60.0, c.game.player_camera.presented_scale().y])
	await c.sequence(16, 10)
	var downed := 0
	for target in targets:
		if not is_instance_valid(target) or bool(target.dead): downed += 1
	c.note("%d of %d aircraft down at the last frame" % [downed, targets.size()])

static func impact(c, spec: Dictionary) -> void:
	var worker = await _stage_worker(c, spec)
	if worker == null: return
	var at: Vector2 = worker.global_position + Vector2(150, -44)
	_place(worker, worker.global_position + Vector2(-400, 0))
	c.camera_at(at + Vector2(-20, -6), 4.0)
	await c.frames(10)
	await c.sequence(12, 2, func(index: int) -> void:
		if index == 1:
			c.game.impact(at, str(spec.args.material), Vector2.LEFT, 1.2)
			c.game.impact(at + Vector2(26, 30), str(spec.args.material), Vector2.UP, 1.0))

static func explosion(c, spec: Dictionary) -> void:
	var worker = await _stage_worker(c, spec)
	if worker == null: return
	var at: Vector2 = worker.global_position + Vector2(260, 0)
	c.camera_at(at + Vector2(-60, -80), 2.0)
	await c.frames(10)
	await c.sequence(16, 4, func(index: int) -> void:
		if index == 1: c.game.impact(at, "explosion", Vector2.UP, 1.6))

# ------------------------------------------------------------- full wave
## Wave with the most enemy families on the field, never the final boss wave.
static func mixed_wave(players: int) -> int:
	var best := 1
	var best_score := -1
	for wave in range(1, Balance.TOTAL_WAVES):
		var total := ceili(Balance.WAVE_COUNTS[wave - 1] * Balance.wave_multiplier(players))
		var seen: Dictionary = {}
		for kind: String in EnemyCatalog.wave_roster(wave, total, true):
			seen["air" if AirEnemyCatalog.is_air(kind) else ("human" if EnemyCatalog.is_human(kind) else ("vehicle" if EnemyCatalog.is_vehicle(kind) else "mech"))] = true
		var score := seen.size() * 100 + total
		if score >= best_score:
			best_score = score
			best = wave
	return best

static func stage_wave(c, environment: String, hud: bool, players: int) -> void:
	await c.play(players, environment, {"hud": hud, "hold_rounds": false, "quiet": true})
	if c.failed(): return
	var wave := mixed_wave(players)
	var flak := _build_flak(c)
	# The one-time solo air-raid cutscene would replace the battlefield.
	var intro = c.game.get("air_raid_intro")
	if is_instance_valid(intro) and "seen" in intro: intro.seen = true
	if c.game.campaign != null and "air_raid_intro_seen" in c.game.campaign: c.game.campaign.air_raid_intro_seen = true
	c.game.rounds.wave = wave
	c.game.rounds.begin_warning()
	await c.frames(2)
	c.game.rounds.time_left = 0.0
	await c.frames(4)
	if str(c.game.rounds.phase) != "attack":
		c.fail("the attack phase did not begin (phase %s)" % str(c.game.rounds.phase))
		return
	var worker = c.game.players[0]
	var gun = c.game.turret
	if is_instance_valid(gun) and gun.has_method("enter"):
		gun.enter(worker)
		c.aim(Vector2(float(gun.global_position.x) + 330.0, _ground(c) - 30.0))
		c.hold(worker.action("fire"))
	if not hud:
		var bunker = c.game.scenario_bunker
		# The whole front from the bunker to the spawn edge, aircraft lanes included.
		c.camera_fit(Rect2(float(bunker.room_left) - 60.0, -40.0, float(c.game.world_right) - float(bunker.room_left) + 60.0, 700.0), 0.0, 2.0)
	c.note("wave %d of %d, %d enemies, %d players, flak %s" % [wave, Balance.TOTAL_WAVES, int(c.game.rounds.wave_total), players, "built" if flak else "not built"])

## Frame-time probe staging (perf.*): the fixed wide framing 20 s into the
## wave. Kept unchanged so probe results stay comparable between passes.
static func _wave(c, spec: Dictionary) -> void:
	await stage_wave(c, str(spec.args.environment), false, 4)
	if c.failed(): return
	await c.frames(60 * 20)
	var alive := 0
	for enemy in c.get_nodes_in_group("enemies"):
		if enemy.get("game") == c.game and not bool(enemy.get("dead")): alive += 1
	c.note("%d enemies alive, core at %d%%, overlay '%s'" % [alive, roundi(float(c.game.core.hp) / float(c.game.core.max_hp) * 100.0), str(c.game.hud.overlay)])

## +1 when the machines come from the right of the bunker (the scenario's own
## approach side), -1 from the left. "Both sides" stages the right flank.
static func _outward(c) -> float:
	var scenario = ScenarioCombat.for_game(c.game)
	return -1.0 if scenario != null and str(scenario.position_mode) == "right" else 1.0

static func _hostiles(c) -> Array:
	var result: Array = []
	for enemy in c.get_nodes_in_group("enemies"):
		if enemy.get("game") == c.game and is_instance_valid(enemy) and not bool(enemy.get("dead")): result.append(enemy)
	return result

## What a gunner keeps the pointer on: the nearest machine on the attack side
## (ground first, the roof gun cannot lift far), its body centre.
static func _gun_target(c, gun: Node2D, outward: float) -> Variant:
	var best: Node2D = null
	var best_air := true
	for enemy: Node2D in _hostiles(c):
		if (enemy.global_position.x - gun.global_position.x) * outward < 40.0: continue
		var air: bool = enemy.is_in_group("air_enemies")
		var nearer: bool = best == null or (best_air and not air) or (air == best_air and gun.global_position.distance_to(enemy.global_position) < gun.global_position.distance_to(best.global_position))
		if nearer:
			best = enemy
			best_air = air
	if best == null: return Vector2(gun.global_position.x + 330.0 * outward, _ground(c) - 30.0)
	var height: float = float(best.get("body_height")) if best.get("body_height") != null else 30.0
	return best.global_position - Vector2(0, height * 0.5)

## A late wave as a couch crew fights it: P1 on the roof gun tracking the
## nearest machine, P2 firing down from the roof beside it, P3 holding the
## outer gate and P4 the inner fence line, all with their real input actions.
## The flak tower is built and runs on its own. The game's own camera frames
## the crew and keeps them above the four-player HUD, which is therefore shown
## (hidden, it would leave an unexplained band of rock); nothing is drawn for
## the capture.
static func stage_defense(c, environment: String, players: int) -> void:
	await stage_wave(c, environment, false, players)
	if c.failed(): return
	c.game.hud.visible = true
	var bunker = c.game.scenario_bunker
	var outward := _outward(c)
	var front := float(bunker.room_right) if outward > 0.0 else float(bunker.room_left)
	var crew: Array = c.game.players
	var gun = c.game.turret
	# stage_wave already seated P1 on the roof gun; the trigger hook below
	# takes the trigger over. A crew that held 18 waves brings the gunner a
	# full load of ammunition crates: the gun reloads from them (its own
	# refill path) instead of running dry halfway through the attack.
	if is_instance_valid(gun):
		crew[0].add_item("ammo", crew[0].capacity())
		c.aim_follow(func() -> Variant: return _gun_target(c, gun, outward))
	var fences: Array = []
	for site in c.get_nodes_in_group("walls"):
		if site.get("game") == c.game and site.get_script() != null and site.get_script().resource_path.get_file() == "perimeter_site.gd": fences.append((site.global_position.x - front) * outward)
	fences.sort()
	var inner_fence: float = fences[0] if not fences.is_empty() else 260.0
	var roof: float = float(gun.global_position.y) if is_instance_valid(gun) else float(c.game.floor_levels[0])
	var posts := [Vector2(front - 70.0 * outward, roof), Vector2(front + 60.0 * outward, _ground(c)), Vector2(front + (inner_fence - 40.0) * outward, _ground(c))]
	var roles := ["roof", "gate", "fence"]
	for index in range(1, mini(crew.size(), 4)):
		var worker = crew[index]
		_place(worker, posts[index - 1], outward)
		c.note("P%d at the %s post (%d, %d)" % [worker.player_id, roles[index - 1], int(posts[index - 1].x), int(posts[index - 1].y)])
	await c.frames(2)
	# The roof rifle tilts down onto the approach before it opens fire.
	if crew.size() > 1:
		c.hold(crew[1].action("aim_down"))
		await c.frames(10)
		c.release(crew[1].action("aim_down"))
	# Trigger discipline: each defender fires only while a machine on the attack
	# side is within reach of their weapon (the gun's longer reach for P1), so
	# the crew does not burn its magazines and reserves into empty ground.
	var reach := [900.0, 560.0, 480.0, 480.0]
	c.each_frame(func() -> void:
		for index in mini(crew.size(), reach.size()):
			var worker = crew[index]
			if not is_instance_valid(worker): continue
			var engaged := false
			for enemy: Node2D in _hostiles(c):
				var ahead: float = (enemy.global_position.x - worker.global_position.x) * outward
				if ahead > 0.0 and ahead < float(reach[index]) and (index == 0 or not enemy.is_in_group("air_enemies")):
					engaged = true
					break
			var action: String = worker.action("fire")
			if engaged and not c._held.has(action): c.hold(action)
			elif not engaged and c._held.has(action): c.release(action))
	c.camera_game()

## Machines on screen that are in the fight: they have opened fire or wound
## up, close on the bunker (the threat overlay's approach distance) or fly.
static func _engaged(c) -> int:
	var view: Rect2 = c.view_rect()
	var bunker = c.game.scenario_bunker
	var count := 0
	for enemy: Node2D in _hostiles(c):
		if not view.has_point(enemy.global_position): continue
		var fired := int(enemy.get("attack_count") if enemy.get("attack_count") != null else 0) > 0 or float(enemy.get("windup") if enemy.get("windup") != null else 0.0) > 0.0
		var close := maxf(float(bunker.room_left) - enemy.global_position.x, enemy.global_position.x - float(bunker.room_right)) < 520.0
		if fired or close or enemy.is_in_group("air_enemies"): count += 1
	return count

## Plays the wave until at least `wanted` machines are engaged on screen (or the
## limit passes) so the capture shows the fight, not the approach.
static func _defense_moment(c, wanted: int = 3, limit: float = 100.0) -> void:
	var waited := 0
	while waited < int(limit * 60.0):
		await c.frames(15)
		waited += 15
		if c.failed(): return
		if _engaged(c) >= wanted: break
	var scale: Vector2 = c.game.player_camera.presented_scale()
	c.note("%.1f simulated seconds into the attack, %d machines engaged on screen, %d alive, %d killed, game camera %s at %.2f px per world unit" % [waited / 60.0, _engaged(c), _hostiles(c).size(), int(c.game.stats.get("kills", 0)), str(c.game.player_camera.mode), scale.y])
	c.note("core at %d%%" % roundi(float(c.game.core.hp) / float(c.game.core.max_hp) * 100.0))

static func wave_still(c, spec: Dictionary) -> void:
	await stage_defense(c, str(spec.args.environment), 4)
	if c.failed(): return
	await _defense_moment(c)
	await c.still()

static func wave_sequence(c, spec: Dictionary) -> void:
	await stage_defense(c, str(spec.args.environment), 4)
	if c.failed(): return
	await _defense_moment(c)
	await c.sequence(16, 8)

# ------------------------------------------------- golden reference scenes
# The three fixed quality references of the style bible (§8). Unlike the wide
# couch-crew wave shots they use two players, so the game's own camera frames
# the fight at the zoom a pair actually plays at; HUD and weather stay on.

static func golden_combat(c, spec: Dictionary) -> void:
	await stage_defense(c, str(spec.args.environment), 2)
	if c.failed(): return
	await _ground_fight(c)
	if int(spec.get("frames", 1)) > 1: await c.sequence(int(spec.frames), 6)
	else: await c.still()

static func golden_dark(c, spec: Dictionary) -> void:
	await stage_defense(c, str(spec.args.environment), 2)
	if c.failed(): return
	if not _build_flak(c): c.note("flak tower could not be built in this build")
	await _ground_fight(c)
	if int(spec.get("frames", 1)) > 1: await c.sequence(int(spec.frames), 4)
	else: await c.still()

## Plays on until at least two ground machines have closed to within 700 units
## of the bunker front, then frames the roof gun and those machines at the game
## camera's own two-player scale (2 screen px per world unit at 1080p). The
## follow camera alone keeps the machines outside the frame (they fire from
## their reach), and a reference must show the fight, not only edge markers.
static func _ground_fight(c, limit: float = 120.0) -> void:
	var waited := 0
	var close: Array = []
	var outward := _outward(c)
	var bunker = c.game.scenario_bunker
	var front := float(bunker.room_right) if outward > 0.0 else float(bunker.room_left)
	while waited < int(limit * 60.0):
		await c.frames(15)
		waited += 15
		if c.failed(): return
		close.clear()
		for enemy: Node2D in _hostiles(c):
			var ahead: float = (enemy.global_position.x - front) * outward
			if not enemy.is_in_group("air_enemies") and ahead > 0.0 and ahead < 700.0: close.append(enemy)
		if close.size() >= 2: break
	var gun = c.game.turret
	var area := Rect2(gun.global_position - Vector2(80, 110), Vector2(160, 0)) if is_instance_valid(gun) else Rect2(Vector2(front, _ground(c) - 200.0), Vector2.ZERO)
	for enemy: Node2D in close: area = area.expand(enemy.global_position + Vector2(60.0 * outward, 20.0))
	area = area.expand(Vector2(area.position.x, _ground(c) + 30.0))
	# 2 device px per world unit at 1080p is a canvas zoom of 2 / 1.2.
	c.camera_fit(area, 24.0, 2.0 / 1.2, true)
	await c.frames(20)
	c.note("%.1f simulated seconds into the attack, %d ground machines within 700 units, %d killed" % [waited / 60.0, close.size(), int(c.game.stats.get("kills", 0))])

static func golden_interior(c, spec: Dictionary) -> void:
	await _solo(c, spec, 2)
	if c.failed(): return
	var built: int = await World.build_rooms(c)
	c.note("%d underground rooms built" % built)
	var bunker = c.game.scenario_bunker
	var left := float(bunker.room_left)
	var right := float(bunker.room_right)
	var floor_y := ScenarioRoomCatalog.floor_y(0)
	var crew: Array = c.game.players
	_place(crew[0], Vector2(left + 380, floor_y))
	if crew.size() > 1: _place(crew[1], Vector2(left + 250, floor_y), -1.0)
	# A carried load, so the player cards show an inventory.
	crew[0].add_item("scrap", mini(6, int(crew[0].capacity())))
	c.game.hud.visible = true
	c.camera_fit(Rect2(left + 40, floor_y - 190, right - left - 80, 205), 12.0, 4.0)
	await c.frames(60)
	await c.still()

## Kill-cost probe (perf.kills.*): one machine of each family (infantry, walker,
## vehicle, aircraft), three rounds, defeated one after another through their
## own take_damage path every 40 frames while the frame times are measured. It
## reports the first kill of each family against its repeats, which a wave probe
## with one or two kills in its window cannot.
static func kill_probe(c, spec: Dictionary) -> void:
	await _solo(c, spec)
	if c.failed(): return
	var families := [_earliest_of(EnemyCatalog.HUMAN_CLASSES, EnemyCatalog.INTRO_WAVES), "", _earliest_of(EnemyCatalog.VEHICLE_CLASSES, EnemyCatalog.INTRO_WAVES),
		_earliest_of(AirEnemyCatalog.INTRO_WAVES.keys(), AirEnemyCatalog.INTRO_WAVES)]
	for candidate: String in EnemyCatalog.GROUND_CLASSES:
		if families[1] == "" and not EnemyCatalog.is_human(candidate) and not EnemyCatalog.is_vehicle(candidate): families[1] = candidate
	var targets: Array = []
	var cursor := _front(c) + 80.0
	for round_index in 3:
		for kind: String in families:
			if kind == "": continue
			var air := AirEnemyCatalog.is_air(kind)
			var actor = _enemy(c, kind, Vector2(cursor, 140.0 if air else _ground(c)))
			if actor == null: return
			targets.append(actor)
			cursor += 110.0
	await c.frames(3)
	for actor in targets: actor.set_physics_process(false)
	c.note("families: " + ", ".join(PackedStringArray(families.filter(func(kind: String) -> bool: return kind != ""))))
	c.camera_fit(Rect2(_front(c), 60.0, cursor - _front(c) + 80.0, _ground(c) - 20.0), 16.0, 3.0)
	await c.frames(30)
	var clock := [0]
	c.each_frame(func() -> void:
		clock[0] += 1
		if clock[0] % 40 != 20: return
		var index: int = clock[0] / 40
		if index < targets.size() and is_instance_valid(targets[index]):
			# The defeat itself (wreck, drop, blast) is timed apart from the
			# frames that follow it, which measure() records.
			var started := Time.get_ticks_usec()
			targets[index].take_damage(1000000.0)
			c.note("kill %d (%s): defeat call %.1f ms" % [index + 1, str(targets[index].get("kind")) if is_instance_valid(targets[index]) else "?", (Time.get_ticks_usec() - started) / 1000.0]))
	c.extra["performance"] = await c.measure(float(targets.size() * 40 + 40) / 60.0)
	c.each_frame(Callable())
	await c.still()

static func _earliest_of(kinds: Array, waves: Dictionary) -> String:
	var best := ""
	for kind: String in kinds:
		if best.is_empty() or int(waves.get(kind, 99)) < int(waves.get(best, 99)): best = kind
	return best

static func wave_probe(c, spec: Dictionary) -> void:
	await _wave(c, spec)
	if c.failed(): return
	c.extra["performance"] = await c.measure(10.0)
	await c.still()
