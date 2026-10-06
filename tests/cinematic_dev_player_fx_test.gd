extends SceneTree
## Actual development-player bed reaches authored editor FX through saved
## process-local layouts. No writes touch the user's source bus resource.
const Player := preload("res://scripts/cinematic_dev_player.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUT := "res://artifacts/cinematic-dev-player-20261004/"
var checks:=0
var failures:=0
var fixture:="user://cinematic-player-fx-%d.tres"%OS.get_process_id()
var game: Node
var player: CanvasLayer
var capture: AudioEffectCapture

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	print("CINEMATIC PLAYER FX %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok: failures+=1; push_error(label)

func frames(count: int=3) -> void:
	for _unused in count: await process_frame

func wall_time(seconds: float) -> void:
	var until:=Time.get_ticks_usec()+roundi(seconds*1000000)
	while Time.get_ticks_usec()<until: await process_frame

func record_bed() -> float:
	player.seek(0)
	await wall_time(.15)
	capture.clear_buffer()
	player.set_playing(true)
	await wall_time(.35)
	var samples:=capture.get_buffer(capture.get_frames_available())
	player.set_playing(false)
	var first:=0
	while first<samples.size() and samples[first].length_squared()<1e-20: first+=1
	var last:=mini(samples.size(),first+5000)
	var energy:=0.0
	for index in range(first,last): energy+=samples[index].length_squared()
	return sqrt(energy/maxf(1.0,(last-first)*2.0))

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args() or AudioServer.get_driver_name()!="Dummy": quit(2); return
	var source_path:="res://default_bus_layout.tres"
	var source_hash:=FileAccess.get_sha256(source_path)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await frames(5)
	var original_path: String=game.audio.bus_mix.layout_path
	var original_processing: bool=game.audio.is_processing()
	var original_gains: Array=[game.audio.music_volume,game.audio.sfx_volume,game.audio.voice_volume]
	var original_master_muted:=AudioServer.is_bus_mute(0)
	var layout:=ResourceLoader.load(original_path,"AudioBusLayout",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AudioBusLayout
	var amplify:=AudioEffectAmplify.new()
	var count:=0
	while layout.get("bus/2/effect/%d/effect"%count)!=null: count+=1
	layout.set("bus/2/effect/%d/effect"%count,amplify)
	layout.set("bus/2/effect/%d/enabled"%count,true)
	check(ResourceSaver.save(layout,fixture)==OK,"Native FX layout saves only in process-local user fixture")
	player=Player.new()
	player.show_for_game(game)
	root.add_child(player)
	await frames()
	player.set_process(false)
	player.select_scene("supply")
	check(game.audio.bus_mix.setup(fixture),"Real paused SourceAudio adopts isolated authored test layout")
	for channel: String in ["Music","SFX","Voice"]: game.audio._apply_bus_volume(channel,game.audio.get(channel.to_lower()+"_volume"))
	var sfx:=AudioServer.get_bus_index("SFX")
	capture=AudioEffectCapture.new()
	capture.buffer_length=1.0
	AudioServer.add_bus_effect(sfx,capture)
	AudioServer.set_bus_mute(0,true)
	var neutral:=await record_bed()
	check(neutral>.0001,"Actual supply-generator preview reaches native SFX capture")
	var saved_hash: String=game.audio.bus_mix.source_hash
	amplify.volume_db=6.0
	check(ResourceSaver.save(layout,fixture)==OK,"Saved six-decibel edit changes private authored FX resource")
	game.audio.bus_mix._last_poll_usec=0
	player._process(0.0)
	check(game.audio.bus_mix.source_hash!=saved_hash and not game.audio.is_processing(),"Developer player hot-reloads authored bus FX while original score processing stays paused")
	var amplified:=await record_bed()
	var ratio:=amplified/maxf(neutral,1e-12)
	check(absf(ratio-db_to_linear(6.0))<.04,"Same real preview bed gains audible six decibels (ratio %.5f)"%ratio)
	var captures:=0
	for index in AudioServer.get_bus_effect_count(sfx):
		if AudioServer.get_bus_effect(sfx,index)==capture: captures+=1
	check(captures==1,"Hot reload preserves same live capture once")
	for index in range(AudioServer.get_bus_effect_count(sfx)-1,-1,-1):
		if AudioServer.get_bus_effect(sfx,index)==capture: AudioServer.remove_bus_effect(sfx,index)
	player.close()
	await frames()
	check(game.audio.bus_mix.setup(original_path),"Original authored source layout is restored without replacing live buses")
	for channel: String in ["Music","SFX","Voice"]: game.audio._apply_bus_volume(channel,game.audio.get(channel.to_lower()+"_volume"))
	AudioServer.set_bus_mute(0,original_master_muted)
	check(FileAccess.get_sha256(source_path)==source_hash and original_gains==[game.audio.music_volume,game.audio.sfx_volume,game.audio.voice_volume] and game.audio.is_processing()==original_processing,"Source bus file, slider gains and original processing remain unchanged")
	check(await Cleanup.free_scene(game,self),"Developer and source graphs clean up after native FX test")
	DirAccess.remove_absolute(fixture)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	FileAccess.open(OUT+"fx-test-result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"dry_rms":neutral,"plus_six_db_rms":amplified,"ratio":ratio,"fixture":"Actual developer player supply-generator ambience through unchanged SFX bus/private retained native capture. ResourceSaver-authorized6dB Amplify edit only process-local user:// copy; actual developer _process polls SourceAudio bus_mix while old soundtrack paused. Source editor file never written, original layout/gains restored."},"\t"))
	print("CINEMATIC PLAYER FX: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
