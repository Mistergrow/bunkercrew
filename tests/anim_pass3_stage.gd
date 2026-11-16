extends RefCounted
## Stage for tests/anim_pass3_capture.gd: the visual-review worker and infantry
## motions with a chosen crew identity / role and a dense frame step.
## args: environment, character (crew id), kind (infantry role), count, step.
const Action := preload("res://tests/visual_review_stage_action.gd")

static func _crew(c, spec: Dictionary, players: int = 1):
	var characters: Array = []
	var first := str(spec.args.get("character", "mara"))
	characters.append(first)
	for entry: Dictionary in CharacterCatalog.CHARACTERS:
		if characters.size() >= players: break
		if str(entry.id) != first: characters.append(str(entry.id))
	await c.play(players, str(spec.args.environment), {"hud": false, "characters": characters})
	if c.failed(): return null
	var worker = c.game.players[0]
	Action._place(worker, Vector2(Action._front(c) + 120.0, Action._ground(c)))
	await c.frames(30)
	c.track(worker, Vector2(0, -40), float(spec.args.get("zoom", 4.0)))
	return worker

static func _count(spec: Dictionary) -> int:
	return int(spec.args.get("count", spec.get("frames", 14)))

static func _step(spec: Dictionary) -> int:
	return int(spec.args.get("step", 2))

static func idle(c, spec: Dictionary) -> void:
	var worker = await _crew(c, spec)
	if worker == null: return
	await c.frames(int(spec.args.get("settle", 0)))
	await c.sequence(_count(spec), _step(spec))

static func walk(c, spec: Dictionary) -> void:
	var worker = await _crew(c, spec)
	if worker == null: return
	if bool(spec.args.get("log", false)):
		var visual = worker.get_node("PixelVisual")
		c.each_frame(func() -> void: c.note("x %.0f ceiling %.1f crouched %s pose %s kind %s" % [worker.global_position.x, visual.ceiling_height, visual.crouched, visual.pose_name, visual.locomotion.kind]))
	c.hold(worker.action("right"))
	await c.frames(int(spec.args.get("settle", 20)))
	await c.sequence(_count(spec), _step(spec))

static func carry(c, spec: Dictionary) -> void:
	var worker = await _crew(c, spec)
	if worker == null: return
	worker.add_item(str(spec.args.get("material", "steel")), worker.capacity())
	c.hold(worker.action("right"))
	await c.frames(int(spec.args.get("settle", 20)))
	await c.sequence(_count(spec), _step(spec))

static func mine(c, spec: Dictionary) -> void:
	var worker = await _crew(c, spec)
	if worker == null: return
	var bunker = c.game.scenario_bunker
	Action._place(worker, Vector2(float(bunker.room_left) + 108.0, ScenarioRoomCatalog.floor_y(0)))
	await c.frames(30)
	c.track(worker, Vector2(20, -40), float(spec.args.get("zoom", 4.0)))
	c.hold(worker.action("interact"))
	await c.frames(24)
	if not bool(worker.mining): c.fail("worker did not start mining at the shaft footing")
	await c.sequence(_count(spec), _step(spec))

static func shoot(c, spec: Dictionary) -> void:
	var worker = await _crew(c, spec)
	if worker == null: return
	c.aim(worker.global_position + Vector2(320, float(spec.args.get("aim_y", -70))))
	await c.frames(6)
	var fire_frames := int(spec.args.get("fire_frames", 30))
	c.hold(worker.action("fire"))
	await c.frames(fire_frames)
	c.release(worker.action("fire"))
	c.hold(worker.action("reload"))
	await c.frames(2)
	c.release(worker.action("reload"))
	if bool(spec.args.get("log", false)):
		var weapon = worker.get_node("WorkerWeapon")
		c.each_frame(func() -> void: c.note("aiming %s progress %.2f step %d dir %s recoil %.2f" % [weapon.aiming, weapon.reload_progress(), _step_of(weapon), str(weapon.aim_direction), weapon.recoil]))
	await c.sequence(_count(spec), _step(spec))

static func revive(c, spec: Dictionary) -> void:
	var worker = await _crew(c, spec, 2)
	if worker == null: return
	var helper = c.game.players[1]
	Action._place(helper, worker.global_position + Vector2(34, 0), -1.0)
	await c.frames(20)
	c.camera_at(worker.global_position + Vector2(14, -42), float(spec.args.get("zoom", 3.5)))
	var collapse := int(spec.args.get("collapse", 12))
	for index in collapse:
		if index == 1:
			worker.take_damage(float(worker.hp) + 500.0, Vector2.LEFT)
			if not worker.is_downed(): c.fail("worker did not collapse")
		await c.sequence_frame()
		await c.frames(_step(spec))
	c.hold(helper.action("interact"))
	var duration := float(worker.medical.aid_duration()) + 1.6 if is_instance_valid(worker.medical) else 6.0
	var rest := _count(spec) - collapse
	var step := ceili(duration * 60.0 / float(maxi(1, rest - 1)))
	for index in rest:
		await c.sequence_frame()
		if index < rest - 1: await c.frames(step)
	c.release(helper.action("interact"))

static func duck(c, spec: Dictionary) -> void:
	# A low lintel in open ground: the same art clearance probe as a gate.
	var worker = await _crew(c, spec)
	if worker == null: return
	var at: Vector2 = worker.global_position + Vector2(90, 0)
	var height := float(spec.args.get("clearance", 46.0))
	var lintel := StaticBody2D.new()
	lintel.collision_layer = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(70, 12)
	shape.shape = box
	lintel.add_child(shape)
	lintel.position = at + Vector2(0, -height - 6)
	c.game.add_child(lintel)
	var bar := ColorRect.new()
	bar.color = Color("3d4446")
	bar.size = Vector2(70, 12)
	bar.position = Vector2(-35, -6)
	lintel.add_child(bar)
	c.hold(worker.action("right"))
	await c.sequence(_count(spec), _step(spec))

static func infantry(c, spec: Dictionary) -> void:
	var actor = await Action._stage_enemy(c, spec, false)
	if actor == null: return
	Action._frame_enemy(c, actor, false)
	var mode := str(spec.args.get("mode", "die"))
	if mode == "move":
		await c.sequence(_count(spec), _step(spec))
		return
	var holder: Array = [actor]
	await c.sequence(_count(spec), _step(spec), func(index: int) -> void:
		if index != 1: return
		var target = holder[0]
		for attempt in 4:
			if is_instance_valid(target) and not bool(target.dead): c.game.combat_hit(target, float(target.max_hp) * 4.0, c.game.players[0])
		if is_instance_valid(target) and not bool(target.dead): c.fail("enemy survived the lethal hit"))
	if bool(spec.args.get("log", false)):
		for node in c.game.get_children():
			if node.is_in_group("pickups") or node.is_in_group("infantry_remains") or node.is_in_group("campaign_salvage"):
				c.note("%s %s z %d at %s visible %s" % [node.name, node.get_script().resource_path.get_file(), node.z_index, str(node.global_position), node.visible])

static func dance(c, spec: Dictionary) -> void:
	# Same staging as the visual-review dance shot (needs the movie writer).
	var worker = await _crew(c, spec)
	if worker == null: return
	var visual = worker.get_node_or_null("PixelVisual")
	if is_instance_valid(worker.progression) and worker.progression.has_method("award_damage"): worker.progression.award_damage(13500.0)
	c.game.rounds.set_process(false)
	c.game.rounds.running = true
	c.game.rounds.wave = 10
	c.game.rounds.phase = "attack"
	if c.game.audio.has_method("set_music_style"): c.game.audio.set_music_style("minimal_techno")
	for index in 60 * 45:
		await c.frames(1)
		if visual.pose_skeleton is Dictionary and visual.pose_skeleton.has("dance_style"): break
	await c.frames(int(spec.args.get("settle", 30)))
	c.note("dance style: " + str(visual.pose_skeleton.get("dance_style", "")))
	await c.sequence(_count(spec), _step(spec))

static func _step_of(weapon) -> int:
	weapon.update_attitude()
	return int(weapon._drawn_step)
