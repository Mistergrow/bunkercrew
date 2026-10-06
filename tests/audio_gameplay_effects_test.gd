extends SceneTree
## Actual weapons, swept contacts, damage receivers and the real audio voice pool.
## Targets and loaded magazines are prepared; sound routing still uses game.sound.
const CLEANUP := preload("res://tests/scene_cleanup.gd")

class ObservedGame extends "res://scripts/game.gd":
	var sound_requests: Array[String] = []
	func sound(kind: String) -> void:
		sound_requests.append(kind)
		super.sound(kind)
	func sound_at(kind: String,at: Vector2) -> void:
		sound_requests.append(kind)
		super.sound_at(kind,at)

var game: ObservedGame
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func reset_sounds() -> void:
	game.sound_requests.clear()
	game.audio.cooldowns.clear()
	for voice in game.audio.voices:
		voice.stop()

func playing(kind: String) -> int:
	var count := 0
	for voice in game.audio.voices:
		if voice.playing and voice.get_meta("kind", "") == kind:
			check(voice.stream in game.audio.variants[kind], "%s uses a real bank recording" % kind)
			count += 1
	return count

func clear_shots() -> void:
	for node in game.get_children():
		if node is WorkerShot or node is BunkerProjectile or node is FlakProjectile or node is HostileAirProjectile:
			node.set_physics_process(false)
			node.queue_free()

func frames() -> void:
	await physics_frame
	await physics_frame

func rifle_contact(point: Vector2) -> void:
	var shot := WorkerShot.new()
	shot.game = game
	shot.credit_worker = game.players[0]
	shot.position = point
	game.add_child(shot)
	shot.set_physics_process(false)
	shot._physics_process(0.3)

func hostile_contact(point: Vector2, damage: float) -> void:
	# Allied roof rounds protect the crew's own dome. A real hostile dart
	# exercises damage and shattering through the actual swept-contact path.
	var shot := HostileAirProjectile.new()
	shot.game = game
	shot.damage = damage
	shot.velocity = Vector2.RIGHT * 1350.0
	shot.position = point
	game.add_child(shot)
	shot.set_physics_process(false)
	shot._physics_process(0.3)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("Use --no-profile-save --no-upnp and an isolated XDG_DATA_HOME")
		quit(1)
		return
	game = ObservedGame.new()
	root.add_child(game)
	current_scene = game
	game.start(1)
	game.combat_events.persistence_enabled = false
	game.rounds.running = false
	game.rounds.set_process(false)
	game.audio.set_process(false)
	game.audio.set_sfx_volume(0.65)
	game.turret.set_physics_process(false)
	var worker = game.players[0]
	worker.set_physics_process(false)
	worker.position = Vector2(2600, 200)
	worker.inventory.clear()
	var weapon: WorkerWeapon = worker.get_node("WorkerWeapon")
	weapon.set_physics_process(false)
	weapon._update_origin()
	weapon.aim_direction = Vector2.RIGHT
	var expected_fire := {"rifle":"shot", "shotgun":"shotgun", "arcgun":"arc"}
	for weapon_kind: String in expected_fire:
		if weapon_kind in ["shotgun", "arcgun"]: game.upgrades.owned[weapon_kind] = true
		weapon.weapon_kind = weapon_kind
		weapon.loaded[weapon_kind] = weapon.magazine_size()
		weapon.cooldown = 0
		weapon.reload_timer = 0
		var ammunition := weapon.current_ammo()
		reset_sounds()
		check(weapon.fire(), "%s fires through the real handheld weapon" % weapon_kind)
		var projectiles := game.get_children().filter(func(node): return node is WorkerShot and not node.is_queued_for_deletion())
		check(projectiles.size() == int(WorkerWeapon.WEAPONS[weapon_kind].pellets) and weapon.current_ammo() == ammunition - int(WorkerWeapon.WEAPONS[weapon_kind].cost), "%s preserves projectile count and ammunition cost" % weapon_kind)
		check(game.sound_requests == [expected_fire[weapon_kind]] and playing(expected_fire[weapon_kind]) == 1, "%s starts one distinct firing sample for its complete discharge" % weapon_kind)
		clear_shots()
		await process_frame
	var roof: RoofTurret = game.turret
	roof.position = Vector2(2800, 400)
	roof.ammo = 5
	roof.cooldown = 0
	roof.aim_angle = 0
	await frames()
	reset_sounds()
	check(roof.fire() and roof.ammo == 4, "Actual roof cannon fires one paid shell")
	check(game.sound_requests == ["cannon"] and playing("cannon") == 1, "Roof cannon plays its own sample without a rifle layer")
	clear_shots()
	var flak := FlakTurret.new()
	flak.game = game
	flak.position = Vector2(2800, 650)
	game.add_child(flak)
	flak.set_physics_process(false)
	flak.ammo = 5
	flak.aim_angle = 0
	await frames()
	reset_sounds()
	check(flak.fire() and flak.ammo == 4, "Actual flak cannon fires one paid shell")
	check(game.sound_requests == ["cannon"] and playing("cannon") == 1, "Flak uses the cannon bank through its normal firing path")
	clear_shots()
	var wooden_wall: DefenseWall = null
	var wall_cases := {DefenseWall.State.FORM:"impact_wood", DefenseWall.State.REBAR:"impact_metal", DefenseWall.State.HARD:"impact_stone"}
	var wall_index := 0
	for wall_state: int in wall_cases:
		var wall: DefenseWall = load("res://scenes/wall.tscn").instantiate()
		wall.game = game
		wall.initial_state = wall_state
		wall.position = Vector2(3600 + wall_index * 500, 300)
		game.add_child(wall)
		if wall_state == DefenseWall.State.FORM: wooden_wall = wall
		await frames()
		var hp_before := wall.hp
		reset_sounds()
		rifle_contact(wall.position + Vector2(-180, -45))
		check(game.sound_requests == [wall_cases[wall_state]] and playing(wall_cases[wall_state]) == 1, "A swept round hitting wall stage %d plays exactly its material sample" % wall_state)
		check(wall.hp == hp_before, "Material contact retains friendly structural damage protection")
		clear_shots()
		wall_index += 1
	var machine: SiegeMachine = load("res://scenes/enemy.tscn").instantiate()
	machine.game = game
	machine.kind = "runner"
	machine.position = Vector2(3600, 600)
	game.add_child(machine)
	machine.set_physics_process(false)
	machine.hp = 300
	machine.max_hp = 300
	await frames()
	reset_sounds()
	rifle_contact(machine.position + Vector2(-180, -28))
	check(game.sound_requests == ["impact_metal"] and playing("impact_metal") == 1 and machine.hp == 284, "A real machine contact plays one metal hit and applies the same sixteen damage")
	clear_shots()
	reset_sounds()
	var shell := FlakProjectile.new()
	shell.game = game
	game.add_child(shell)
	shell.set_physics_process(false)
	shell.impact(machine, machine.position, Vector2.LEFT)
	shell.impact(machine, machine.position, Vector2.LEFT)
	check(game.sound_requests == ["impact_metal"] and playing("impact_metal") == 1, "A retired flak shell cannot emit a second contact sample")
	check(is_equal_approx(machine.hp, 284.0 - shell.damage * 0.45), "The sound change preserves reduced ground damage and single-hit retirement")
	var pane := DomeSegment.new()
	pane.game = game
	pane.configure(Vector2(4300, 550), Vector2(4300, 700), 1)
	game.add_child(pane)
	pane.set_frame()
	pane.glaze()
	await frames()
	reset_sounds()
	hostile_contact(Vector2(4120, 620), 1.0)
	check(pane.hp == pane.max_hp - 1 and game.sound_requests == ["hit"] and not game.audio.cooldowns.has("glass_break"), "A nonlethal pane contact does not prematurely play shattering")
	clear_shots()
	reset_sounds()
	hostile_contact(Vector2(4120, 620), pane.max_hp)
	check(pane.stage == DomeSegment.Stage.BROKEN and game.sound_requests == ["hit", "glass_break"] and playing("glass_break") == 1, "Actual glass destruction adds one distinct shatter recording")
	clear_shots()
	reset_sounds()
	var core_hp: float = game.core.hp
	check(ImpactBurst.sound_for(game.core)=="impact_core" and ImpactBurst.material_for(game.core)=="metal" and game.audio.variants.impact_core.size()==5, "Core contacts select five dedicated physical recordings while retaining metal debris")
	var hostile := HostileAirProjectile.new()
	hostile.game = game
	hostile.damage = 12
	game.add_child(hostile)
	hostile.set_physics_process(false)
	# The core is an intended damage receiver, not a physics body. Exercise the
	# actual projectile's resolved-contact path, then its duplicate-hit guard.
	hostile._impact(game.core, game.core.position, Vector2.RIGHT)
	hostile._impact(game.core, game.core.position, Vector2.RIGHT)
	check(game.core.hp == core_hp - 12 and game.sound_requests == ["impact_core"] and playing("impact_core") == 1, "Projectile contact and core damage share one dry core sample without a generic duplicate")
	clear_shots()
	reset_sounds()
	game.core.remove_meta("impact_contact_frame")
	game.core.take_damage(1)
	check(game.sound_requests == ["impact_core"] and playing("impact_core") == 1, "Direct core damage still has its dedicated physical sound when no contact owns it")
	machine.position = wooden_wall.position + Vector2(180, 0)
	await frames()
	reset_sounds()
	var wood_hp := wooden_wall.hp
	check(machine._fire_collision_shot(wooden_wall.position + Vector2(0, -45), wooden_wall, 7.0), "Actual ground-machine firing resolves its wooden target")
	check(wooden_wall.hp == wood_hp - 7 and game.sound_requests == ["impact_wood", "enemy_shot"] and playing("impact_wood") == 1, "Ground-machine fire keeps damage and plays wood contact plus its firing sound once")
	game.core.position = Vector2(3800, 900)
	machine.position = Vector2(4000, 900)
	await frames()
	reset_sounds()
	core_hp = game.core.hp
	check(machine._fire_collision_shot(game.core.position + Vector2(0, -30), game.core, 9.0), "Ground-machine fire reaches the actual core receiver")
	check(game.core.hp == core_hp - 9 and game.sound_requests == ["impact_core", "enemy_shot"], "Ground-machine core contact has one dry core hit and one firing sound")
	machine.position = Vector2(3600, 1100)
	var trap := FieldDefense.new()
	trap.game = game
	trap.kind = "jaw_trap"
	trap.position = machine.position + Vector2(-10, 0)
	game.add_child(trap)
	trap.set_physics_process(false)
	trap.arming = 0
	await frames()
	reset_sounds()
	var machine_hp := machine.hp
	check(trap.trigger(machine), "A real armed jaw trap triggers on the machine")
	check(machine.hp == machine_hp - 70 and trap.charges == 2 and game.sound_requests == ["impact_metal"] and playing("impact_metal") == 1, "Jaw trap uses one metal recording while preserving damage and charges")
	check(await CLEANUP.free_scene(game, self), "Gameplay sound fixture releases all players and native playback handles")
	print("AUDIO GAMEPLAY EFFECTS: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
