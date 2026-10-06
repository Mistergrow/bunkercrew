extends SceneTree
## Real weapon logic, spatial mixer routes and protocol-decoded events. No device playback.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const PROTOCOL := preload("res://scripts/network_protocol.gd")
const OUTPUT := "res://artifacts/weapon-audio"

class ObservedGame extends "res://scripts/game.gd":
	var requests: Array[Dictionary] = []
	func sound_at(kind: String, at: Vector2) -> void:
		requests.append({"kind":kind,"at":at})
		super.sound_at(kind,at)

var game: ObservedGame
var worker: Worker
var weapon: WorkerWeapon
var flak: FlakTurret
var checks := 0
var failures := 0
var capture: AudioEffectCapture
var capture_index := -1
var measurements: Dictionary = {}

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	print("WEAPON AUDIO %s: %s" % ["PASS" if value else "FAIL",label])

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func reset_sounds() -> void:
	game.requests.clear()
	game.network._events.clear()
	game.audio.cooldowns.clear()
	for voice in game.audio.voices: voice.stop()

func kinds() -> Array:
	return game.requests.map(func(event): return event.kind)

func prepare(family: String) -> Node2D:
	worker.mounted_turret = null
	weapon.cancel_actions()
	worker.inventory.clear()
	game.turret.occupant = null
	game.turret.reload_timer = 0.0
	flak.occupant = null
	flak.reload_timer = 0.0
	flak.autonomous = false
	var target: Node2D = weapon
	if family == "cannon": target = game.turret
	elif family == "flak": target = flak
	else:
		weapon.weapon_kind = "arcgun" if family == "arc" else family
		if weapon.weapon_kind in ["shotgun", "arcgun"]: game.upgrades.owned[weapon.weapon_kind] = true
		weapon.loaded[weapon.weapon_kind] = 0
	if target != weapon:
		target.occupant = worker
		worker.mounted_turret = target
		target.ammo = 0
		if target == flak: flak.hp = 200.0
	# Position outside the bunker, with actual ground and the flak's own hull present.
	worker.global_position = Vector2(1010,430)
	weapon._update_origin()
	target.reserve = 40
	reset_sounds()
	return target

func phase_checks(family: String, duration: float) -> void:
	var target := prepare(family)
	check(target.start_reload(),family+": real reload starts")
	check(kinds() == ["reload_"+family+"_open"],family+": exactly one opening cue")
	check(not target.start_reload() and game.requests.size() == 1,family+": repeated input cannot duplicate the start")
	target._physics_process(duration*.47)
	check(game.requests.size() == 1,family+": feeding stays aligned with the middle of the animation")
	target._physics_process(duration*.02)
	check(kinds() == ["reload_"+family+"_open","reload_"+family+"_load"],family+": crossing the feed phase emits once")
	target._physics_process(duration*.02)
	check(game.requests.size() == 2,family+": later frames do not repeat feeding")
	target._physics_process(duration*.52)
	check(kinds() == ["reload_"+family+"_open","reload_"+family+"_load","reload_"+family+"_close"],family+": actual ammunition transfer produces one closing cue")
	var ammo: int = target.current_ammo() if target == weapon else int(target.ammo)
	check(ammo > 0 and ammo+target.reserve == 40,family+": phased sound preserves finite ammunition")
	for event in game.requests:
		check(event.at is Vector2 and event.at.is_finite() and event.at.y < 410,family+": audio originates at the elevated mechanism")
	for voice in game.audio.voices:
		if voice.playing:
			check(voice.stream in game.audio.variants[voice.get_meta("kind")],family+": playing voice uses an imported original WAV")
	# A stalled frame can cross both milestones without dropping or repeating them.
	target = prepare(family)
	target.start_reload()
	target._physics_process(duration*1.1)
	check(game.requests.size() == 3,family+": a long frame preserves all three ordered phases")

func save_capture(family: String, samples: PackedVector2Array, duration: float) -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = roundi(AudioServer.get_mix_rate())
	var bytes := PackedByteArray()
	bytes.resize(samples.size()*4)
	var peak := 0.0
	var energy := 0.0
	for index in samples.size():
		var value := samples[index]
		energy += value.length_squared()
		peak = maxf(peak,maxf(absf(value.x),absf(value.y)))
		bytes.encode_s16(index*4,roundi(clampf(value.x,-1,1)*32767))
		bytes.encode_s16(index*4+2,roundi(clampf(value.y,-1,1)*32767))
	stream.data = bytes
	check(stream.save_to_wav(ProjectSettings.globalize_path(OUTPUT+"/capture-"+family+".wav")) == OK,family+": actual mixer capture saved")
	var phase_rms: Array[float] = []
	for at in [0.0,duration*.48,duration]:
		var phase_energy := 0.0
		var count := 0
		for index in range(int(at*stream.mix_rate),mini(samples.size(),int((at+.36)*stream.mix_rate))):
			phase_energy += samples[index].length_squared()
			count += 1
		phase_rms.append(sqrt(phase_energy/maxf(1.0,count*2.0)))
	check(samples.size() > stream.mix_rate*duration and peak < .9 and peak > .015,family+": real output has a measurable unclipped signal")
	check(phase_rms.all(func(value): return value>.0015),family+": every timed mechanical phase is present in actual mixer output")
	measurements[family] = {"peak":peak,"rms":sqrt(energy/maxf(1,samples.size()*2)),"phase_rms":phase_rms,"frames":samples.size(),"rate":stream.mix_rate,"effects_volume":game.audio.sfx_volume}

func run() -> void:
	if AudioServer.get_driver_name() != "Dummy" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use Dummy audio and isolated userdata with --no-profile-save --no-upnp")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game = ObservedGame.new()
	root.add_child(game)
	current_scene = game
	game.start(2)
	game.combat_events.persistence_enabled = false
	game.rounds.running = false
	await physics_frame
	freeze(game)
	worker = game.players[0]
	weapon = worker.get_node("WorkerWeapon")
	game.players[1].position = Vector2(1070,430)
	game.turret.position = Vector2(1040,430)
	flak = FlakTurret.new()
	flak.game = game
	flak.position = Vector2(1040,430)
	game.add_child(flak)
	flak.set_physics_process(false)
	game.audio.set_music_volume(0)
	game.audio.set_sfx_volume(.65)
	game.audio.movement.stop_effects()
	await physics_frame
	game.audio.acoustics._probe_listener()
	var durations := {"rifle":1.05,"shotgun":1.25,"arc":1.15,"cannon":1.05,"flak":1.35}
	for family: String in durations: phase_checks(family,durations[family])
	prepare("rifle")
	weapon.start_reload()
	weapon.cancel_actions()
	weapon._physics_process(1.2)
	check(kinds() == ["reload_rifle_open"] and weapon.current_ammo() == 0,"Cancelling a reload omits feed/close and never fills ammunition")
	prepare("flak")
	flak.start_reload()
	flak.take_damage(1000)
	var broken_events := game.requests.size()
	flak._physics_process(2.0)
	check(flak.reload_timer == 0.0 and flak.ammo == 0 and game.requests.size() == broken_events and "reload_flak_close" not in kinds(),"A destroyed flak cannot finish loading or play a successful closing cue")
	prepare("flak")
	flak.reserve = 0
	worker.inventory = {"ammo":1}
	check(flak.start_reload() and kinds() == ["reload_flak_open"] and flak.reserve == 20,"Taking the initial flak reserve pack does not double the opening with a premature feed cue")
	prepare("rifle")
	weapon.reserve = 0
	check(not weapon.start_reload() and game.requests.is_empty(),"Rejected reloads make no successful handling sound")
	prepare("flak")
	flak.reserve = 0
	check(not flak.fire() and kinds() == ["empty"],"A manned empty flak gives one dry trigger response")
	flak.fire()
	check(game.requests.size() == 1,"Holding a dry flak trigger does not spam sound")
	prepare("cannon")
	game.turret.occupant = null
	worker.mounted_turret = null
	game.turret.enter(worker)
	check(kinds() == ["weapon_mount"],"Mounting a heavy gun uses mechanical grip feedback")
	prepare("flak")
	worker.global_position = flak.operator_position()
	game.network.active = true
	game.network.is_host = true
	game.network.local_player_id = 1
	game.audio.acoustics._probe_listener()
	reset_sounds()
	check(flak.start_reload(),"The prepared network host starts a real seated flak reload")
	var mechanism_voice: AudioStreamPlayer = game.audio.voices.filter(func(voice): return voice.playing and voice.get_meta("kind", "") == "reload_flak_open")[0]
	var mechanism_lane: Dictionary = game.audio.acoustics._lanes[game.audio.voices.find(mechanism_voice)]
	check(mechanism_lane.target_occlusion == 0.0,"The flak's own hull cannot muffle the seated operator's reload feedback")
	game.network.active = false
	game.network.is_host = false
	game.audio.acoustics._probe_listener()
	game.upgrades.owned.clear()
	prepare("rifle")
	weapon.loaded.rifle = 5
	weapon.cycle_weapon()
	check(game.requests.is_empty(),"Cycling a single locked weapon stays silent")
	game.upgrades.owned["shotgun"] = true
	weapon.loaded.shotgun = 3
	weapon.cycle_weapon()
	check(kinds() == ["weapon_switch"],"Changing to another equipped weapon plays sling and receiver handling")
	reset_sounds()
	check(game.audio.play_sound_at("reload_rifle_open",Vector2(1010,390)) and game.audio.play_sound_at("reload_rifle_open",Vector2(1070,390)),"Separated cooperative workers can audibly reload at the same instant")
	check(not game.audio.play_sound_at("reload_rifle_open",Vector2(1010,390)),"Duplicate handling from the same source is throttled")
	reset_sounds()
	for index in game.audio.MAX_VOICES:
		game.audio.cooldowns.clear()
		game.audio.play_sound("explosion")
	check(game.audio.play_sound_at("reload_cannon_open",Vector2(1020,390)),"A reload phase remains audible through a full pool of combat effects")
	for family: String in game.audio.variants:
		if not family.begins_with("reload_") and not family.begins_with("weapon_"): continue
		var previous: AudioStream = null
		var varied := true
		for index in 7:
			reset_sounds()
			game.audio.play_sound_at(family,Vector2(1020,390))
			var sample: AudioStream = game.audio.voices[0].stream
			varied = varied and sample != previous
			previous = sample
		check(varied,family+": runtime shuffle never repeats the preceding sample")
	for i in 180:
		game.audio.play_sound_at("reload_rifle_open",Vector2(i*64,390))
	check(game.audio.cooldowns.size() <= game.audio.MAX_COOLDOWN_KEYS and game.audio.voices.size() == 12,"Moving emitters retain bounded cooldown memory and twelve voices")
	game.audio.set_sfx_volume(0)
	check(game.audio.voices.all(func(voice): return not voice.playing) and not game.audio.play_sound("reload_cannon_open"),"F4 mute stops and suppresses mechanical phases")
	game.audio.set_sfx_volume(.65)
	var paused_weapon := prepare("rifle")
	paused_weapon.start_reload()
	paused_weapon.set_physics_process(true)
	var remaining: float = paused_weapon.reload_timer
	paused = true
	await create_timer(.15,true).timeout
	check(paused_weapon.reload_timer == remaining and game.requests.size() == 1 and not game.audio.play_sound("reload_rifle_close"),"Pause freezes actual reload time and prevents later cues")
	paused = false
	paused_weapon.set_physics_process(false)
	# Same serialization and receive path used by ENet, without creating a socket.
	var net_weapon := prepare("shotgun")
	game.network.active = true
	game.network.is_host = true
	game.network.peer_connected = true
	net_weapon.start_reload()
	net_weapon._physics_process(1.3)
	var events: Array = game.network._events.duplicate(true)
	check(events.size() == 3 and events.all(func(event): return event.category == "sound" and event.payload.at is Vector2),"Authoritative phases queue three positioned network events")
	var packet := PROTOCOL.encode({"kind":"events","events":events})
	var decoded: Dictionary = PROTOCOL.decode(packet)
	game.network.is_host = false
	reset_sounds()
	game.network._receive_events(decoded.events)
	check(kinds() == ["reload_shotgun_open","reload_shotgun_load","reload_shotgun_close"] and game.network._events.is_empty(),"Decoded guest events retain phases and never echo to the host")
	game.network.active = false
	game.network.peer_connected = false
	game.network.is_host = false
	capture = AudioEffectCapture.new()
	capture.buffer_length = 4
	var master := AudioServer.get_bus_index("Master")
	capture_index = AudioServer.get_bus_effect_count(master)
	AudioServer.add_bus_effect(master,capture)
	for family: String in durations:
		var target := prepare(family)
		game.audio.acoustics._probe_listener()
		await create_timer(.2).timeout
		capture.clear_buffer()
		target.start_reload()
		target.set_physics_process(true)
		await create_timer(float(durations[family])+.42).timeout
		target.set_physics_process(false)
		check(game.requests.size() == 3,family+": normal real-time physics emits three phases")
		save_capture(family,capture.get_buffer(capture.get_frames_available()),durations[family])
	AudioServer.remove_bus_effect(master,capture_index)
	check(await CLEANUP.free_scene(game,self),"All phase voices and private acoustic buses release on scene teardown")
	var report := FileAccess.open(OUTPUT+"/runtime-measurements.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed":checks-failures,"failed":failures,"captures":measurements,"review":"Dummy driver actual AudioEffectCapture; no listening assessment."},"\t")+"\n")
	report.close()
	print("WEAPON RELOAD AUDIO: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
