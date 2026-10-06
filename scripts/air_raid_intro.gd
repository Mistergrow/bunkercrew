extends Node
## Local presentation barrier at the first scheduled aircraft, never a wave phase.
## Only a cosmetic seen flag crosses a campaign checkpoint; combat stays unsaved.
signal began(context: Dictionary)
signal ended(skipped: bool)

const DURATION := 8.0
const SKIP_DELAY := 0.35
const OVERLAY := "air_raid_intro"
var game: Node
var active := false
var elapsed := 0.0
var duration := DURATION
var context: Dictionary = {}
var seen := false
var _release_pending := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _solo_candidate() -> bool:
	if not is_instance_valid(game) or not game.started or game.player_count != 1 or game.players.size() != 1: return false
	if is_instance_valid(game.network) and game.network.active: return false
	var player: Node = game.players[0]
	return is_instance_valid(player) and not player.is_queued_for_deletion() and not player.is_downed()

func already_seen() -> bool:
	if game.campaign != null and game.campaign.active: return game.campaign.air_raid_intro_seen
	return seen

func reserves_crew_warning() -> bool:
	return not already_seen() and _solo_candidate() and game.rounds.wave >= 7 and game.air_defense_ready()

func before_spawn(wave: int, index: int, total: int) -> bool:
	if active: return true
	if already_seen() or not _solo_candidate() or get_tree().paused: return false
	if not game.hud.overlay.is_empty() or not game.rounds.running or game.rounds.phase != "attack": return false
	if wave < 7 or index < 0 or total <= 0 or not game.rounds.air_wave_enabled or not game.air_defense_ready(): return false
	if wave == Balance.TOTAL_WAVES and index == total-1: return false
	var roster: Array[String] = EnemyCatalog.wave_roster(wave,total,true)
	var kind: String = roster[index % roster.size()]
	if not AirEnemyCatalog.is_air(kind): return false
	context = {"character_id":str(game.players[0].character_id), "enemy_kind":kind,
		"environment":str(game.scenario_options.get("environment","sector07")), "wave":wave}
	active = true
	seen = true
	elapsed = 0.0
	duration = DURATION
	_release_pending = false
	game.hud.overlay = OVERLAY
	get_tree().paused = true
	_release_actions()
	if game.campaign != null and game.campaign.active:
		# Even a failed cosmetic write cannot create a combat save or trap a player.
		# In-memory retries still retain the seen flag; normal safe saves retry it.
		game.campaign.mark_air_raid_intro_seen()
	began.emit(context.duplicate())
	return true

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not active or not is_finite(delta) or delta <= 0.0: return
	# A scene teardown, terminal result or external mode change never unpauses
	# someone else's menu. Joining locally through input is blocked by the HUD.
	if not _solo_candidate() or not game.rounds.running or game.hud.overlay != OVERLAY:
		finish(false)
		return
	elapsed = minf(duration, elapsed + delta)
	if elapsed >= duration: finish(false)

func skip() -> void:
	if active and elapsed >= SKIP_DELAY: finish(true)

func finish(skipped: bool) -> void:
	if not active: return
	active = false
	_release_actions()
	# Unpause on the next idle turn so the skip press cannot become a jump,
	# shot or pause action in the same input dispatch.
	_release_pending = true
	_release_pause.call_deferred()
	ended.emit(skipped)

func _release_pause() -> void:
	if not _release_pending or not is_instance_valid(game) or not is_inside_tree(): return
	_release_pending = false
	if game.hud.overlay != OVERLAY: return
	game.hud.overlay = ""
	if game.rounds.running and (not is_instance_valid(game.network) or not game.network.active):
		get_tree().paused = false

func _release_actions() -> void:
	for action: StringName in InputMap.get_actions():
		if str(action).begins_with("p1_"): Input.action_release(action)

func _input(event: InputEvent) -> void:
	if not active: return
	# Display controls are safe while simulation input remains blocked.
	if event is InputEventKey and event.physical_keycode in [KEY_F3,KEY_F11]:
		if event.pressed and not event.echo and event.physical_keycode == KEY_F3:
			game.weather.set_reduced_effects(not game.weather.reduced_effects)
			get_viewport().set_input_as_handled()
		return
	# The full-screen panel consumes these in GUI dispatch; its native skip
	# button must remain clickable. Workers remain paused, and held fire clears.
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		_release_actions()
		return
	get_viewport().set_input_as_handled()
	if not event.is_echo() and (event.is_action_pressed("start") or event.is_action_pressed("ui_accept") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		skip()
	_release_actions()
