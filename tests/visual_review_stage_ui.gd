extends RefCounted
## Interface shots of the visual-review instrument. Screens are reached through
## the real input actions and panel calls the UI galleries use.
const World := preload("res://tests/visual_review_stage_world.gd")
const DEFAULT_ENVIRONMENT := ""

static func _environment(c) -> String:
	return str(ScenarioCatalog.environments()[0].id)

## Opens an overlay with its real shortcut; falls back to the public field.
static func _overlay(c, action: String, overlay: String) -> bool:
	var hud = c.game.hud
	if InputMap.has_action(action): await c.press(action)
	if str(hud.overlay) != overlay:
		c.note("shortcut '%s' did not open '%s'; overlay set directly" % [action, overlay])
		hud.overlay = overlay
		c.paused = true
	await c.frames(8)
	return str(hud.overlay) == overlay

static func _settle_menu(c) -> void:
	await c.frames(40)

static func main_menu(c, _spec: Dictionary) -> void:
	await c.menu()
	await _settle_menu(c)
	await c.still()

static func scenario_select(c, _spec: Dictionary) -> void:
	await c.menu()
	await c.press("start")
	if str(c.game.hud.overlay) != "scenario" and c.need(c.game.hud, "_open_scenario_selection"): c.game.hud._open_scenario_selection(1)
	await c.frames(30)
	if str(c.game.hud.overlay) != "scenario": c.fail("scenario selection did not open")
	await c.still()

static func character_select(c, _spec: Dictionary) -> void:
	await c.menu()
	if not c.need(c.game.hud, "_open_scenario_selection"): return
	c.game.hud._open_scenario_selection(4)
	await c.frames(6)
	if not c.need(c.game.hud.scenario_panel, "confirm"): return
	c.game.hud.scenario_panel.confirm()
	await c.frames(30)
	if str(c.game.hud.overlay) != "characters": c.fail("character selection did not open")
	await c.still()

static func overlay_menu(c, spec: Dictionary) -> void:
	await c.menu()
	if not await _overlay(c, str(spec.args.action), str(spec.args.overlay)): c.fail("overlay did not open: " + str(spec.args.overlay))
	await c.frames(20)
	await c.still()

static func options(c, spec: Dictionary) -> void:
	await c.menu()
	if not await _overlay(c, "audio_settings", "audio"):
		c.fail("options did not open")
		return
	var panel = c.game.hud.options_panel
	if not c.need(panel, "select_tab"): return
	await _reach_tab(c, panel, int(spec.args.tab))
	await c.frames(20)
	await c.still()

## A player reaches a category with the arrow keys from the focused first
## tab, so focus and selection move together; a click is the fallback.
static func _reach_tab(c, panel, wanted: int) -> void:
	await c.frames(2)
	for step in wanted: await c.press("ui_down")
	if int(panel.tab) != wanted:
		c.note("arrow keys reached tab %d; tab %d clicked instead" % [int(panel.tab), wanted])
		panel.tab_buttons[wanted].grab_focus()
		panel.select_tab(wanted)

static func changelog(c, _spec: Dictionary) -> void:
	await c.menu()
	var panel = c.game.hud.main_menu_panel
	if not c.need(panel, "release_button"): return
	panel.release_button.pressed.emit()
	await c.frames(20)
	if panel.has_method("has_modal_subpanel") and not panel.has_modal_subpanel(): c.fail("release notes did not open")
	await c.still()

static func _match(c, players: int, options: Dictionary = {}) -> void:
	await c.play(players, _environment(c), options)

static func overlay_match(c, spec: Dictionary) -> void:
	await _match(c, 4)
	if c.failed(): return
	c.game.upgrades.points = 12
	for worker in c.game.players:
		if is_instance_valid(worker.progression) and worker.progression.has_method("award_damage"): worker.progression.award_damage(1500.0)
	c.game.elapsed = 2183.0
	await c.frames(4)
	if not await _overlay(c, str(spec.args.action), str(spec.args.overlay)): c.fail("overlay did not open: " + str(spec.args.overlay))
	await c.frames(20)
	await c.still()

static func expedition(c, _spec: Dictionary) -> void:
	await _match(c, 4)
	if c.failed(): return
	var state = c.game.campaign
	if not c.need(state, "complete_mission"): return
	var reward = state.complete_mission(state.mission_id, 20, c.game.players, c.game.upgrades, {"steel": 12, "ammo": 6, "concrete": 18, "scrap": 8})
	if reward is Dictionary and reward.is_empty(): c.note("mission completion returned no reward")
	if is_instance_valid(state.expedition) and is_instance_valid(state.expedition.vehicle): state.expedition.vehicle.cargo = {"steel": 4, "ammo": 3, "concrete": 6}
	c.game.hud.overlay = "expedition"
	c.paused = true
	await c.frames(30)
	if not is_instance_valid(c.game.hud.expedition_panel): c.fail("convoy map did not open")
	await c.still()

static func crafting(c, _spec: Dictionary) -> void:
	await _match(c, 1)
	if c.failed(): return
	if not World.clear_field(c, 0):
		c.fail("first basement could not be cleared for the workbench")
		return
	var bench = c.game.workshop
	bench.refresh_access()
	var worker = c.game.players[0]
	worker.global_position = bench.interaction_point() if bench.has_method("interaction_point") else bench.global_position
	# A load the worker can really carry (the game's own capacity limit).
	worker.inventory = {}
	worker.add_item("steel", 4)
	worker.add_item("scrap", 3)
	c.note("carried: %s of %d" % [str(worker.inventory), int(worker.capacity())])
	c.camera_follow(1.25)
	await c.frames(30)
	# The real interact key opens the bench menu; the HUD call is the fallback.
	c.hold(worker.action("interact"))
	await c.frames(3)
	c.release(worker.action("interact"))
	await c.frames(4)
	if not is_instance_valid(c.game.hud.crafting_panel):
		c.note("interact key did not open the bench; HUD call used")
		worker.global_position = bench.interaction_point()
		await c.frames(2)
		if c.need(c.game.hud, "open_crafting"): c.game.hud.open_crafting(worker, bench)
	await c.frames(20)
	if not is_instance_valid(c.game.hud.crafting_panel): c.fail("crafting panel did not open")
	await c.still()

## The last wave of a shift: wave 20 for a held bunker; for a lost one the
## wave with the most enemy families. Everything the report reads is the
## game's own state at that moment: the attack phase of that wave, the shift
## clock and kills of every wave before it (each wave only ends once its whole
## roster is destroyed), kills credited through the crew's progression, and
## the bunker core worn down through its own damage path.
static func _final_wave(c, won: bool) -> int:
	var Action = load("res://tests/visual_review_stage_action.gd")
	var crew: Array = c.game.players
	var players: int = crew.size()
	var last: int = Balance.TOTAL_WAVES if won else Action.mixed_wave(players)
	var kills := 0
	var clock := 0.0
	for wave in range(1, last + 1):
		var count := ceili(Balance.WAVE_COUNTS[wave - 1] * Balance.wave_multiplier(players))
		# A lost shift ends halfway through its last attack.
		var share := 1.0 if won or wave < last else 0.5
		kills += roundi(count * share)
		clock += float(Balance.BUILD_TIMES[wave - 1]) + Balance.WARNING_TIME + count * share * Balance.spawn_interval(players) + (Balance.SALVAGE_TIME if wave < last else 0.0)
	c.game.elapsed = clock
	c.game.stats.kills = kills
	# Every kill is credited to a crew member (gunners, and the flak's builder).
	var credited := 0
	for index in players:
		var progression = crew[index].get("progression")
		var mine := kills - credited if index == players - 1 else roundi(kills * (0.56 if index == 0 else 0.44 / maxf(1.0, players - 1.0)))
		if is_instance_valid(progression) and progression.has_method("award_kill"):
			for kill in mine: progression.award_kill()
		credited += mine
	if won: c.game.core.take_damage(float(c.game.core.max_hp) * 0.38)
	var rounds = c.game.rounds
	rounds.running = true
	rounds.wave = last
	rounds.begin_warning()
	await c.frames(2)
	rounds.time_left = 0.0
	for index in 30:
		await c.frames(1)
		if str(rounds.phase) == "attack": break
	if str(rounds.phase) != "attack": c.fail("the attack of wave %d did not begin (phase %s)" % [last, str(rounds.phase)])
	c.note("wave %d of %d, %d kills, shift clock %d s" % [last, Balance.TOTAL_WAVES, kills, roundi(clock)])
	return last

## The moment the game itself ends the shift: the last machine of the final
## roster is gone (the round controller declares victory), or the core falls.
static func _end_shift(c, won: bool) -> void:
	var rounds = c.game.rounds
	if won:
		rounds.spawned = rounds.wave_total
		for enemy in c.get_nodes_in_group("enemies"):
			if enemy.get("game") == c.game and not bool(enemy.get("dead")): c.game.combat_hit(enemy, float(enemy.max_hp) * 4.0, c.game.players[0])
	else:
		rounds.spawned = ceili(rounds.wave_total * 0.5)
		c.game.core.take_damage(float(c.game.core.hp) * 10.0 + 1.0)

static func result(c, spec: Dictionary) -> void:
	await _match(c, 2)
	if c.failed(): return
	var won := bool(spec.args.won)
	await _final_wave(c, won)
	if c.failed(): return
	_end_shift(c, won)
	await c.frames(30)
	if str(c.game.hud.overlay) not in ["victory", "defeat", "campaign_victory"]: c.fail("result screen did not open (overlay '%s', phase %s)" % [str(c.game.hud.overlay), str(c.game.rounds.phase)])
	await c.still()

static func tutorial(c, _spec: Dictionary) -> void:
	await c.play(1, _environment(c), {"tutorial": true, "quiet": true})
	if c.failed(): return
	var lessons = c.game.solo_tutorial
	if not c.need(lessons, "restart"): return
	lessons.set_enabled(true)
	lessons.restart()
	await c.frames(90)
	var view: Variant = lessons.get_view() if lessons.has_method("get_view") else {}
	if view is Dictionary and view.is_empty(): c.fail("no tutorial lesson is on screen")
	await c.still()

static func hud_idle(c, spec: Dictionary) -> void:
	var players := int(spec.args.players)
	await c.play(players, _environment(c), {"quiet": false, "hold_rounds": false, "settle": 20})
	if c.failed(): return
	if players > 1:
		var loads := [["steel", 3], ["concrete", 2], ["ammo", 4], ["sand", 5]]
		for index in c.game.players.size():
			c.game.players[index].add_item(loads[index % loads.size()][0], loads[index % loads.size()][1])
	await c.frames(100)
	await c.still()

static func hud_combat(c, _spec: Dictionary) -> void:
	var Action = load("res://tests/visual_review_stage_action.gd")
	await Action.stage_wave(c, str(Action.night_environment()), true, 1)
	if c.failed(): return
	# The gunner keeps the pointer on the nearest machine, as a player does.
	var gun = c.game.turret
	if is_instance_valid(gun): c.aim_follow(func() -> Variant: return Action._gun_target(c, gun, Action._outward(c)))
	await c.frames(60 * 12)
	# A moment the threat read has work to do: a ground machine is closing in
	# beyond the edge of the view (bounded wait; the HUD is captured either way).
	var waited := 0
	var beyond := 0
	while waited < 60 * 20:
		beyond = 0
		for enemy: Node2D in Action._hostiles(c):
			if not enemy.is_in_group("air_enemies") and not c.view_rect().has_point(enemy.global_position): beyond += 1
		if beyond > 0: break
		await c.frames(10)
		waited += 10
	c.note("%.1f s into the attack, %d ground machines beyond the view" % [12.0 + waited / 60.0, beyond])
	await c.still()

static func lobby(c, spec: Dictionary) -> void:
	var coordination := OS.get_environment("VR_LOBBY_PATH")
	if coordination.is_empty():
		c.fail("lobby shots need the paired launch from tools/visual_review.py")
		return
	await c.menu()
	var network = c.game.network
	var host := str(spec.args.role) == "host"
	if "listen_port" in network: network.listen_port = int(OS.get_environment("VR_LOBBY_PORT"))
	if "lan_discovery_port" in network: network.lan_discovery_port = int(OS.get_environment("VR_LOBBY_PORT")) + 1
	c.game.hud.overlay = "network"
	if host:
		c.game.hud.scenario_options = {"environment": _environment(c), "build_type": "bastion", "position": "left"}
		network.host_room("")
		await c.frames(5)
		if str(network.state) != "lobby":
			c.fail("host room did not open: " + str(network.error_message))
			return
		var file := FileAccess.open(coordination + ".code", FileAccess.WRITE)
		file.store_string(str(network.direct_code))
		file.close()
	else:
		var waited := 0
		while not FileAccess.file_exists(coordination + ".code") and waited < 1800:
			await c.frames(1)
			OS.delay_msec(10)
			waited += 1
		network.join_room("", FileAccess.get_file_as_string(coordination + ".code").strip_edges())
	var connected := false
	for index in 3000:
		await c.frames(1)
		OS.delay_msec(8)
		if str(network.state) == "error":
			c.fail("lobby connection failed: " + str(network.error_message))
			return
		if str(network.state) == "lobby" and bool(network.peer_connected) and (host or bool(network.get("_authenticated"))):
			connected = true
			break
	if not connected:
		c.fail("no lobby connection within the time limit")
		return
	c.note("room codes are random per run; the code text differs between renders")
	# Let both sides exchange their crew rows before the picture.
	for index in 90:
		await c.frames(1)
		OS.delay_msec(8)
	await c.still()
	var mark := FileAccess.open(coordination + (".host" if host else ".guest"), FileAccess.WRITE)
	mark.store_string("done")
	mark.close()
	var other := coordination + (".guest" if host else ".host")
	for index in 1500:
		if FileAccess.file_exists(other): break
		await c.frames(1)
		OS.delay_msec(8)
	network.leave()
	await c.frames(4)

# ------------------------------------------------------------- sequences
static func seq_menu_focus(c, _spec: Dictionary) -> void:
	await c.menu()
	await _settle_menu(c)
	var steps := ["ui_down", "ui_down", "ui_down", "ui_down", "ui_down", "ui_up", "ui_up"]
	await c.sequence(14, 3, func(index: int) -> void:
		if index > 0 and index % 2 == 0 and index / 2 - 1 < steps.size(): await c.press(steps[index / 2 - 1]))

static func seq_panel(c, _spec: Dictionary) -> void:
	await _match(c, 1)
	if c.failed(): return
	c.game.upgrades.points = 12
	await c.frames(20)
	await c.sequence(14, 2, func(index: int) -> void:
		if index == 2 or index == 8: await c.press("upgrades"))

static func seq_tabs(c, _spec: Dictionary) -> void:
	await c.menu()
	if not await _overlay(c, "audio_settings", "audio"):
		c.fail("options did not open")
		return
	var panel = c.game.hud.options_panel
	if not c.need(panel, "select_tab"): return
	var tabs: int = maxi(1, panel.tab_buttons.size())
	await c.frames(20)
	# Each change is a click on the next category: it takes focus and selects.
	await c.sequence(12, 2, func(index: int) -> void:
		if index > 0 and index % 3 == 0:
			panel.tab_buttons[(index / 3) % tabs].grab_focus()
			panel.select_tab((index / 3) % tabs))

static func seq_wave_start(c, _spec: Dictionary) -> void:
	await c.play(1, _environment(c), {"hold_rounds": false})
	if c.failed(): return
	await c.frames(30)
	await c.sequence(16, 10, func(index: int) -> void:
		if index == 1: await c.press("skip_build")
		if index == 1 and str(c.game.rounds.phase) != "warning": c.game.rounds.begin_warning()
		if index == 7: c.game.rounds.time_left = 0.0)
	if str(c.game.rounds.phase) != "attack": c.note("round phase after the sequence: " + str(c.game.rounds.phase))

static func seq_victory(c, _spec: Dictionary) -> void:
	await _match(c, 2)
	if c.failed(): return
	await _final_wave(c, true)
	if c.failed(): return
	# The wave's own start announcement has long left the screen by the time
	# its last machine falls; let it play out before the victory.
	await c.frames(60 * 4)
	await c.sequence(14, 3, func(index: int) -> void:
		if index == 2: _end_shift(c, true))
