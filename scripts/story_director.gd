extends Node
## Four-act story over a complete twenty-wave shift. World actions, not elapsed
## dialogue time, unlock the prologue and relay objectives.
const Relay := preload("res://scripts/story_relay.gd")
const DialogueCatalog := preload("res://scripts/story_dialogue_catalog.gd")
const InputLabels := preload("res://scripts/input_labels.gd")
var game
var enabled := false
var stage := 0
var relay: Node2D
var wall: DefenseWall
var serial := 0
var elapsed := 0.0
var _scan_clock := 0.0
var _phase_key := ""
var _said: Dictionary = {}
var _down: Dictionary = {}
var _storm_pending := false
var _reply_cursor := 1

func authoritative() -> bool:
	return not is_instance_valid(game.network) or not game.network.active or game.network.is_host

func begin(story_enabled: bool) -> void:
	enabled=story_enabled
	if enabled:
		var bunker=game.scenario_bunker
		var side := -1.0 if bunker.position_mode=="right" else 1.0
		var edge: float=bunker.room_left if side<0 else bunker.room_right
		wall=game._entity("wall",Vector2(edge+side*84,bunker.ground_y),{"initial_state":0})
		wall.set_meta("scenario_front",true)
		wall.set_meta("story_wall",true)
		# Tutorial materials are finite, physical crates beside the construction
		# site; the normal rooftop stock remains available for the siege.
		game._entity("supply",Vector2(edge+side*40,bunker.ground_y),{"kind":"concrete","amount":2})
		relay=Relay.new()
		relay.game=game
		relay.director=self
		relay.position=Vector2(bunker.room_left+229,bunker.ground_y-39)
		relay.scale=Vector2.ONE*.65
		game.add_child(relay)
	if displays_objectives():
		var panel=preload("res://scripts/story_objective_panel.gd").new()
		panel.director=self
		game.hud.canvas.add_child(panel)
	if not authoritative(): return
	if enabled:
		say("story_open")
		say("crew_wall",1)
	else:
		say("world_"+str(game.scenario_options.get("environment","sector07")))
	_phase_key="%d:%s" % [game.rounds.wave,game.rounds.phase]

func say(id: String,player_id: int=0) -> void:
	if not is_instance_valid(game.get("dialogue")): return
	var speaker := "san"
	if player_id>0:
		for player in game.players:
			if player.player_id==player_id: speaker=player.character_id
	if DialogueCatalog.source_line(id,speaker).is_empty():
		return
	serial+=1
	game.dialogue.enqueue(id,speaker,player_id,serial)
	if is_instance_valid(game.network):
		game.network.queue_event("dialogue",{"id":id,"speaker":speaker,"player":player_id,"serial":serial,"generation":game.network._generation})

func reply_player_id() -> int:
	var available: Array=game.players.filter(func(player): return is_instance_valid(player) and not player.is_downed())
	if available.is_empty(): return 0
	var selected: int=available[_reply_cursor%available.size()].player_id
	_reply_cursor+=1
	return selected

func once(id: String,cooldown: float=99999.0,player_id: int=0) -> void:
	if elapsed-float(_said.get(id,-99999.0))<cooldown: return
	_said[id]=elapsed
	say(id,player_id)

func _process(delta: float) -> void:
	if not game.started or get_tree().paused or not authoritative(): return
	elapsed+=delta
	_scan_clock+=delta
	if _scan_clock<.1: return
	_scan_clock=0
	if enabled and stage==0 and is_instance_valid(wall) and wall.state==DefenseWall.State.HARD:
		stage=1
		game.rounds.time_left=minf(game.rounds.time_left,35)
		say("wall_ready")
		game.notify(LocaleText.format("MAUER FERTIG · Versorgt euch am Dach · %s startet die erste Welle",InputLabels.menu(game,"skip_build")))
	var phase_key := "%d:%s" % [game.rounds.wave,game.rounds.phase]
	if phase_key!=_phase_key:
		_phase_key=phase_key
		phase_changed()
	if enabled and stage==0 and elapsed>24: once("wall_hint",40)
	if _storm_pending and is_instance_valid(game.weather.get("storm_events")):
		if game.weather.storm_events.trigger_tree_strike(-1,false):
			_storm_pending=false
			say("storm_tree")
			say("crew_storm",1)
	if game.rounds.phase not in ["victory","defeat"]:
		if game.core.hp/game.core.max_hp<.3: once("core_low",50)
		for player in game.players:
			var down: bool=player.medical.incapacitated()
			if down and not bool(_down.get(player.player_id,false)): once("ally_down",12)
			elif not down and bool(_down.get(player.player_id,false)): once("revived",15)
			_down[player.player_id]=down

func phase_changed() -> void:
	var wave: int=game.rounds.wave
	var phase: String=game.rounds.phase
	if enabled and phase=="build":
		if wave>=16 and stage==5:
			stage=6
			say("final_signal")
		elif wave>=11 and stage==3:
			stage=4
			say("relay_failure")
		elif wave>=4 and stage==1:
			stage=2
			say("relay_first")
	if phase=="warning":
		if wave==20: say("warning_boss")
		elif game.rounds.air_wave_enabled:
			once("warning_air",55)
			# Solo's first crew reply belongs to the actual aircraft introduction.
			# SAN's tactical warning still precedes the wave for every game mode.
			var intro = game.get("air_raid_intro")
			if wave%3==1 and not (is_instance_valid(intro) and intro.reserves_crew_warning()):
				say("crew_air",reply_player_id())
		else:
			once("warning_ground",30)
			if wave%2==1: say("crew_contact",reply_player_id())
	elif phase=="salvage":
		once("wave_clear",60)
		if wave%4==1: say("crew_clear",1)
		if wave in [2,6,10,14,18]:
			once("world_"+str(game.scenario_options.environment),180)

func blocks_build() -> bool:
	return enabled and (stage in [0,2,4,6] or (stage==1 and game.rounds.wave>=4) or (stage==3 and game.rounds.wave>=11) or (stage==5 and game.rounds.wave>=16))

func complete_relay() -> void:
	if not enabled or not authoritative(): return
	match stage:
		2:
			stage=3
			say("relay_online")
			say("crew_reply",reply_player_id())
			_storm_pending=str(game.scenario_options.environment)=="mountain_pass"
		4:
			stage=5
			say("relay_restore")
		6:
			stage=7
			say("transmission_live")
		_:
			return
	game.rounds.time_left=minf(game.rounds.time_left,30)
	if is_instance_valid(game.get("solo_story")): game.solo_story.relay_completed(stage)

func finish(won: bool) -> void:
	if not authoritative() or not enabled: return
	stage=8 if won else 9
	say("story_victory" if won else "story_defeat")
	if won: say("crew_final",reply_player_id())

func displays_objectives() -> bool:
	return enabled or (is_instance_valid(game.get("solo_story")) and game.solo_story.enabled)

func act_title() -> String:
	if not enabled and displays_objectives(): return str(game.solo_story.objective().get("title",""))
	if stage<=1: return LocaleText.text("I · EIN ORT ZUM BLEIBEN")
	if stage<=3: return LocaleText.text("II · EINE STIMME IM RAUSCHEN")
	if stage<=5: return LocaleText.text("III · DIE LEITUNG HÄLT")
	return LocaleText.text("IV · KEINER BLEIBT ZURÜCK")

func objective() -> String:
	if not enabled and displays_objectives(): return str(game.solo_story.objective().get("body",""))+" · "+InputLabels.menu(game,"story_journal")
	var worker: Node=game.players[0] if not game.players.is_empty() else null
	var interact := InputLabels.action(worker,"interact")
	match stage:
		0:
			if not is_instance_valid(wall): return LocaleText.text("Baue die Mauer vor dem Bunker.")
			match wall.state:
				DefenseWall.State.EMPTY: return LocaleText.format("Am markierten Bauplatz %s halten: Schalung stellen.",interact)
				DefenseWall.State.FORM,DefenseWall.State.REBAR: return LocaleText.format("2 Beton aus der nahen Kiste holen; an der Schalung %s halten.",interact)
				_: return LocaleText.format("Beton härtet aus: noch %d Sekunden.", ceili(maxf(0,Balance.CURE_TIME-wall.cure_time)))
		1: return LocaleText.text("Wehre drei Wellen ab. Munition liegt auf dem Dach.")
		2: return LocaleText.format("Feldfunk im Bunker: 2 Stahl bringen und %s halten.",interact)
		3: return LocaleText.text("Schütze den Empfänger. Baue die Flak; danach sind ab Welle 7 Luftangriffe möglich.")
		4: return LocaleText.format("Feldfunk reparieren: 1 Stahl bringen und %s halten.",interact)
		5: return LocaleText.text("Halte den Bunker bis zur letzten Sendephase.")
		6: return LocaleText.format("Am Feldfunk fünf Sekunden %s halten: Notruf senden.",interact)
		7: return LocaleText.text("Der Notruf läuft. Halte den Kern bis zum Ende der 20. Welle.")
		8: return LocaleText.text("Mehrere Bunker antworten. Das Warnnetz steht wieder.")
	return LocaleText.text("Das Signal ist verstummt. Die Crew braucht einen neuen Versuch.")

func target_position() -> Vector2:
	if not enabled and displays_objectives(): return game.solo_story.target_position()
	if stage==0 and is_instance_valid(wall): return wall.position+Vector2(0,-112)
	if stage in [2,4,6] and is_instance_valid(relay): return relay.position+Vector2(0,-98)
	return Vector2(INF,INF)

func capture_state() -> Dictionary:
	return {"enabled":enabled,"stage":stage,"serial":serial,"elapsed":elapsed,"relay_progress":relay.progress if is_instance_valid(relay) else 0.0}

static func valid_state(state: Dictionary) -> bool:
	if state.size()!=5: return false
	if not state.get("enabled") is bool or not state.get("stage") is int or state.stage<0 or state.stage>9: return false
	if not state.get("serial") is int or state.serial<0 or state.serial>1000000: return false
	for key in ["elapsed","relay_progress"]:
		if not (state.get(key) is float or state.get(key) is int) or not is_finite(float(state[key])) or state[key]<0: return false
	return state.relay_progress<=1 and state.elapsed<10000000

func apply_state(state: Dictionary,first: bool=false) -> bool:
	if not valid_state(state) or state.enabled!=enabled: return false
	stage=state.stage
	serial=state.serial
	elapsed=state.elapsed
	if is_instance_valid(relay): relay.progress=state.relay_progress
	if first and is_instance_valid(game.dialogue): game.dialogue.reset()
	return true
