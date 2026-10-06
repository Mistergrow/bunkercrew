class_name ShiftRoundController
extends Node

signal phase_changed
signal finished(won: bool)

var game: Node
var phase := "build"
var wave := 1
var time_left := 0.0
var running := false
var player_count := 1
var spawned := 0
var wave_total := 0
var spawn_clock := 0.0
var air_wave_enabled := false

func start_round(players: int = 1) -> void:
	player_count = clampi(players, 1, 4)
	wave = 1
	spawned = 0
	wave_total = 0
	air_wave_enabled = false
	running = true
	_set_phase("build", Balance.BUILD_TIMES[0])

func _process(delta: float) -> void:
	if not running:
		return
	if is_instance_valid(game.get("air_raid_intro")) and game.air_raid_intro.active:
		return
	if phase=="build" and is_instance_valid(game) and is_instance_valid(game.get("story")) and game.story.blocks_build():
		return
	if is_instance_valid(game) and Balance.active_players(game) != player_count:
		player_count = Balance.active_players(game)
		# The attack roster is fixed at its start. Changing its final index can
		# remove or repeat the final boss when crew joins or disconnects.
	if phase == "attack":
		var previous_clock := spawn_clock
		spawn_clock -= delta
		if spawned < wave_total and spawn_clock <= 0:
			if game.has_method("defer_air_spawn") and game.defer_air_spawn(wave,spawned,wave_total):
				spawn_clock = previous_clock
				return
			if game.has_method("unlock_depth"):
				game.spawn_enemy(wave,spawned,wave_total)
			else:
				game.spawn_enemy(wave)
			spawned += 1
			spawn_clock += Balance.spawn_interval(player_count)
		if spawned >= wave_total and get_tree().get_nodes_in_group("enemies").is_empty():
			if wave >= Balance.TOTAL_WAVES:
				victory()
			else:
				_set_phase("salvage", Balance.SALVAGE_TIME)
				if wave % Balance.EXPANSION_INTERVAL == 0:
					game.notify(_expansion_notice())
				else:
					game.notify(LocaleText.text("Welle abgewehrt · Schrott und Technikpunkte bergen · Schäden reparieren"))
		return
	time_left = maxf(0, time_left - delta)
	if time_left > 0:
		return
	match phase:
		"build":
			begin_warning()
		"warning":
			_begin_attack()
		"salvage":
			wave += 1
			_set_phase("build", Balance.BUILD_TIMES[wave - 1])
			game.notify(_build_notice())

func _expansion_notice() -> String:
	if ScenarioCombat.for_game(game) != null:
		return {5:LocaleText.text("BAUPLAN GLASWERK · Beton und Stahl zum Raum-Baupult · Raum fertigstellen: Sand + Kalkstein zu Glas"),10:LocaleText.text("BAUPLAN TIEFENSCHMELZE · Beton und Stahl zum Raum-Baupult · Wolframerz und Stahl zu Panzerstahl verarbeiten"),15:LocaleText.text("BAUPLAN FESTUNGSARSENAL · Raum-Baupult beliefern · T: FESTUNG für die späte Glaskuppel")}.get(wave,LocaleText.text("Weitere Baupläne freigegeben · Material zum Raum-Baupult"))
	return {5:LocaleText.text("AUSBAU II · Glaswerk offen · Schacht in der Mine freilegen"),10:LocaleText.text("AUSBAU III · Tiefenschacht öffnen · Wolframerz zu Panzerstahl verarbeiten"),15:LocaleText.text("AUSBAU IV · T: FESTUNG · Kuppel: 4 Stahl + 4 Panzerstahl + 12 Glas")}.get(wave,LocaleText.text("Ausbaugebiet freigegeben"))

func _build_notice() -> String:
	if ScenarioCombat.for_game(game) != null:
		return {6:LocaleText.text("FLAK BAUEN · Pult im Bunker: 3 Stahl + 2 Beton + 1 Munitionskiste · Luftangriffe erst mit fertiger Flak, frühestens Welle 7"),11:LocaleText.text("TIEFENSCHMELZE BAUEN · Beton und Stahl zum Raum-Baupult · FLAK II: 4 Stahl + 2 Glas"),16:LocaleText.text("FESTUNGSARSENAL BAUEN · T: FESTUNG · Kuppel: 4 Stahl + 4 Panzerstahl + 12 Glas")}.get(wave,LocaleText.text("Baupause · Raum-Baupult beliefern, Munition laden und Fronten verstärken"))
	return {6:LocaleText.text("FLAK BAUEN · Pult oben: 3 Stahl + 2 Beton + 1 Munitionskiste · Luftangriffe erst mit fertiger Flak, frühestens Welle 7"),11:LocaleText.text("FLAK II · 4 Stahl + 2 Glas · Tiefenschacht für Panzerstahl öffnen"),16:LocaleText.text("FLAK III · 3 Panzerstahl + 3 Glas · FESTUNG und Kuppel ausbauen")}.get(wave,LocaleText.text("Baupause · Munition nachladen, Material verarbeiten und Front verstärken"))

func begin_warning() -> void:
	if not running or phase != "build":
		return
	if is_instance_valid(game.get("story")) and game.story.blocks_build():
		game.notify(game.story.objective())
		return
	air_wave_enabled = _air_defense_ready()
	_set_phase("warning", Balance.WARNING_TIME)
	game.sound("alarm")
	var scenario := ScenarioCombat.for_game(game)
	if scenario != null:
		var approach: String = {"left":LocaleText.text("RECHTS"),"right":LocaleText.text("LINKS"),"center":LocaleText.text("BEIDE SEITEN")}[scenario.position_mode]
		game.notify(LocaleText.format("LUFTALARM · BODENKONTAKTE %s · Flak und Munition prüfen!", approach) if air_wave_enabled else LocaleText.format("MASCHINEN %s · Fronten und Geschütz besetzen!", approach))
	else:
		game.notify(LocaleText.text("LUFTALARM · Flak und Munition prüfen · gleichzeitig Bodenkontakte!") if air_wave_enabled else LocaleText.text("MASCHINEN IM ANMARSCH · Dachgeschütz besetzen!"))

func _air_defense_ready() -> bool:
	return wave >= 7 and is_instance_valid(game) and game.has_method("air_defense_ready") and game.air_defense_ready()

func _begin_attack() -> void:
	if is_instance_valid(game): player_count = Balance.active_players(game)
	if phase != "warning":
		air_wave_enabled = _air_defense_ready()
	spawned = 0
	wave_total = maxi(spawned, ceili(Balance.WAVE_COUNTS[wave - 1] * Balance.wave_multiplier(player_count)))
	spawn_clock = 0
	_set_phase("attack", 0)
	game.sound("alarm")

func _set_phase(next_phase: String, duration: float) -> void:
	phase = next_phase
	time_left = duration
	phase_changed.emit()

func victory() -> void:
	if not running:
		return
	running = false
	_set_phase("victory", 0)
	finished.emit(true)

func defeat() -> void:
	if not running:
		return
	running = false
	_set_phase("defeat", 0)
	finished.emit(false)
