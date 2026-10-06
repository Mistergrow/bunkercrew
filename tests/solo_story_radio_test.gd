extends SceneTree
## Real Main/Director/Speech plus in-memory host effects, no sockets or profiles.
const Catalog:=preload("res://scripts/story_dialogue_catalog.gd")
const Protocol:=preload("res://scripts/network_protocol.gd")
const Clean:=preload("res://tests/scene_cleanup.gd")
const LINES:=["crew_wall","crew_reply","crew_storm","crew_final","crew_contact","crew_air","crew_clear"]
const ORIGINAL_VOICES := "res://tests/fixtures/story_voice_original_hashes.json"
const OUTPUT:="res://artifacts/solo-story/runtime/"
var checks:=0
var failures:=0
var rows: Array[Dictionary]=[]
var game: Node
var capture: AudioEffectCapture
var capture_bus: int
var capture_index: int
var evidence: Array[Dictionary]=[]

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	rows.append({"passed":ok,"description":label})
	if not ok: failures+=1;push_error(label)

func samples() -> float:
	capture.clear_buffer()
	var until:=Time.get_ticks_usec()+300000
	while Time.get_ticks_usec()<until: await process_frame
	var buffer:=capture.get_buffer(capture.get_frames_available())
	var energy:=0.0
	for sample in buffer: energy+=sample.length_squared()
	return sqrt(energy/maxf(1,float(buffer.size())*2))

func assets() -> Dictionary:
	var values: Dictionary={}
	for locale: String in ["de","en"]:
		var metadata_path:=Catalog.VOICE_ROOT+("en/" if locale=="en" else "")+"source.json"
		var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		for filename: String in metadata.files:
			var path:=metadata_path.get_base_dir()+"/"+filename
			values[path]=FileAccess.get_sha256(path)
	return values

func exercise(identity: String,language: String,id: String,host: bool) -> void:
	var dialogue: StoryDialogue=game.dialogue
	dialogue.reset()
	LocaleText.set_locale(language,false)
	game.network._events.clear()
	game.network.active=host
	game.network.is_host=host
	game.network.peer_connected=host
	game.network._generation=37
	check(game.players[0].character_id==identity,"Actual fresh scene retains requested identity: "+identity)
	var expected_speaker: String=identity
	var expected_id: String=id
	var expected_anchor:=1
	var serial: int=game.story.serial
	game.story.say(id,1)
	var label:="%s/%s/%s/%s"%["host" if host else "solo",language,identity,id]
	check(game.story.serial==serial+1 and dialogue.pending.size()==1,label+": actual director creates one accepted authored event")
	if dialogue.pending.size()!=1: return
	var pending: Dictionary=dialogue.pending[0]
	var expected:=Catalog.line(expected_id,expected_speaker)
	check(pending.id==expected_id and pending.speaker_id==expected_speaker and pending.anchor_player_id==1 and pending.serial==game.story.serial,label+": precise character-specific human identity/anchor")
	check(Catalog.SPEAKERS.has(pending.speaker_id) and ResourceLoader.exists(pending.voice_path) and pending.voice_path==expected.voice_path and pending.text==expected.text,label+": subtitle and actual existing language recording match")
	check(dialogue._resolve_anchor(expected_speaker,expected_anchor)==game.players[0],label+": caption resolves an actual owned worker while speaker remains its own recorded identity")
	if host:
		check(game.network._events.size()==1,label+": actual connected-host queue publishes one effect")
		if game.network._events.size()!=1: return
		var event: Dictionary=game.network._events[0]
		var payload: Dictionary=event.payload
		check(event.category=="dialogue" and payload=={"id":expected_id,"speaker":expected_speaker,"player":expected_anchor,"serial":game.story.serial,"generation":37},label+": published payload is exactly the speech that the host accepted")
		var message:={"kind":"effects","generation":37,"events":[event]}
		var decoded:=Protocol.decode(Protocol.encode(message))
		check(decoded==message,label+": genuine safe binary protocol roundtrip retains valid dialogue values")
		dialogue.reset()
		game.network._receive_events(decoded.events)
		check(dialogue.pending.size()==1 and dialogue.pending[0].speaker_id==expected_speaker and dialogue.pending[0].anchor_player_id==1,label+": actual receive handler accepts the same authored speaker/anchor")
		game.network._receive_events(decoded.events)
		check(dialogue.pending.size()==1,label+": repeated received serial never stacks a second speech")
	else:
		check(game.network._events.is_empty(),label+": ordinary solo speech cannot publish an online event")
	dialogue.advance(.01)
	check(dialogue.active.id==expected_id and dialogue.active.speaker_id==expected_speaker and dialogue.active.text==expected.text,label+": real speech presentation starts the intended localized line")
	check(dialogue.voice.playing and dialogue.voice.stream!=null and dialogue.voice.stream.resource_path==expected.voice_path and not dialogue.voice.stream_paused,label+": actual speech voice starts its real matching WAV")
	if not host and id=="crew_air":
		var rms:=await samples()
		check(rms>.002,label+": actual Voice mixer contains audible PCM")
		evidence.append({"identity":identity,"language":language,"rms":rms,"voice":expected.voice_path})
	# Replay the caller, not only a wire serial: active/cooldown still blocks audio.
	var spoken:=dialogue.spoken_count
	game.story.say(id,1)
	dialogue.advance(.01)
	check(dialogue.spoken_count==spoken and dialogue.active.speaker_id==expected_speaker and dialogue.pending.is_empty(),label+": repeated local call cannot stack or change the speaker")

func prepare(identity: String) -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.network.set_process(false)
	game.social_bridge.set_process(false)
	game.selected_characters.assign([identity])
	game.start_scenario(1,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.set_process(false)
	game.story.set_process(false)
	game.solo_story.set_process(false)
	game.expedition.set_process(false)
	game.set_process(false)
	game.dialogue.set_process(false)
	for node: Node in game.find_children("*","Node",true,false): node.set_physics_process(false)
	game.hud.overlay=""
	paused=false
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),true)
	capture_bus=AudioServer.get_bus_index("Voice")
	capture_index=AudioServer.get_bus_effect_count(capture_bus)
	capture=AudioEffectCapture.new()
	capture.buffer_length=2
	AudioServer.add_bus_effect(capture_bus,capture)
	check(game.network.transport==null and not game.microphone.capturing,"Actual Main fixture has no transport, bound port or recording microphone")
	check(game.players[0].character_id==identity,"Prepared fresh scenario applies actual selected identity: "+identity)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var before:=assets()
	check(before.size()==170 and Catalog.SPEAKERS==["san","mara","branko","ivo","nora","levin","selma","oskar","rika"],"All170 voice files provide the eight playable characters and the separate SAN radio")
	var historical: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ORIGINAL_VOICES))
	check(historical.files.size()==142,"The pre-extension audit retains all142 original recording hashes")
	for path: String in historical.files:
		check(FileAccess.get_sha256(path)==str(historical.files[path]),"Original performance stays byte-identical to the pre-extension audit: "+path.get_file())
	check(Protocol.WORLD_REVISION==5,"Peer world revision explicitly distinguishes the eight-character schema")
	CrewRoster.persistence_enabled=false
	CrewRoster.unlock("oskar")
	CrewRoster.unlock("rika")
	for identity: String in ["oskar","rika","mara"]:
		prepare(identity)
		for host in [false,true]:
			for language: String in ["de","en"]:
				for id: String in LINES: await exercise(identity,language,id,host)
				game.dialogue.reset()
				game.network._events.clear()
				var serial: int=game.story.serial
				for unknown: String in ["missing","","../crew_air","crew_not_authored"]: game.story.say(unknown,1)
				check(game.story.serial==serial and game.dialogue.pending.is_empty() and game.dialogue.active.is_empty() and game.network._events.is_empty(),"Unknown authored IDs remain true no-ops for "+identity+"/"+language)
		check(game.network.transport==null and not game.microphone.capturing,"Host event simulation never creates sockets or starts input recording")
		game.network.active=false
		game.network.peer_connected=false
		game.network.is_host=false
		game.network._events.clear()
		AudioServer.remove_bus_effect(capture_bus,capture_index)
		check(await Clean.free_scene(game,self),"Actual Main and all genuine speech handles release cleanly: "+identity)
	check(assets()==before,"All170 localized voice files remain byte-for-byte unchanged during gameplay and network tests")
	var report:={"success":failures==0,"checks":checks,"passed":checks-failures,"failures":failures,"cases":84,"actual_mixer_probes":evidence,"voice_assets_preserved":before,"source_sha256":FileAccess.get_sha256("res://scripts/story_director.gd"),"fixture":"Three fresh actual Main/Worker/StoryDirector/StoryDialogue scenes with genuine pre-start character selection; seven authored crew calls and two languages, solo plus in-memory actual connected-host effects/receive path; transport=null, process-off networking, no sockets/profiles, Master muted and Voice captured before Master.","results":rows}
	FileAccess.open(OUTPUT+"radio-verification.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SOLO STORY RADIO: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
