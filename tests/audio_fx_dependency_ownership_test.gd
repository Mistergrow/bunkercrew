extends SceneTree
## One native effect may be referenced by multiple buses. Saved Windows text
## must watch the same external dependencies as native LF editor saves.
const Mix:=preload("res://scripts/audio_bus_mix.gd")
const OUTPUT:="res://artifacts/final-hardening-20261004/presentation/"
var layout_path:="user://fx-ownership-%d.tres"%OS.get_process_id()
var effect_path:="user://fx-shared-%d.tres"%OS.get_process_id()
var checks:=0
var failures:=0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)
func save_layout(shared: bool=false,music_only: bool=false,crlf: bool=false) -> void:
	var layout:=AudioBusLayout.new()
	for index in 3:
		layout.set("bus/%d/name"%[index+1],[&"Music",&"SFX",&"Voice"][index])
		layout.set("bus/%d/send"%[index+1],&"Master")
	if shared or music_only:
		var effect:=ResourceLoader.load(effect_path,"AudioEffect",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AudioEffect
		layout.set("bus/1/effect/0/effect",effect)
		layout.set("bus/1/effect/0/enabled",true)
		if shared:
			layout.set("bus/2/effect/0/effect",effect)
			layout.set("bus/2/effect/0/enabled",true)
	check(ResourceSaver.save(layout,layout_path)==OK,"Native layout fixture saves actual shared/external references")
	if crlf:
		var text:=FileAccess.get_file_as_string(layout_path)
		var file:=FileAccess.open(layout_path,FileAccess.WRITE)
		file.store_string(text.replace("\n","\r\n"));file.close()
func poll(mix: RefCounted) -> bool:
	mix._last_poll_usec=0
	return mix.poll()
func fx(channel: String) -> AudioEffect:
	var index:=AudioServer.get_bus_index(channel)
	return AudioServer.get_bus_effect(index,0) if AudioServer.get_bus_effect_count(index)>0 else null

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args() or AudioServer.get_driver_name()!="Dummy": quit(2);return
	var source:=AudioEffectAmplify.new();source.volume_db=3.0
	check(ResourceSaver.save(source,effect_path)==OK,"Independent native Amplify fixture saves")
	save_layout()
	AudioServer.set_bus_layout(ResourceLoader.load(layout_path,"AudioBusLayout",ResourceLoader.CACHE_MODE_IGNORE_DEEP))
	var master:=AudioServer.get_bus_index("Master")
	var capture:=AudioEffectCapture.new();AudioServer.add_bus_effect(master,capture)
	var mix:=Mix.new()
	check(mix.setup(layout_path),"Empty native fixture is adopted before shared-effect edit")
	save_layout(true)
	await create_timer(.51).timeout
	check(poll(mix),"Native external effect used by Music and SFX is adopted")
	var music:=fx("Music");var sfx:=fx("SFX")
	check(music is AudioEffectAmplify and sfx is AudioEffectAmplify and music.volume_db==3 and sfx.volume_db==3,"Both buses retain the same authored effect parameters")
	check(music!=sfx,"Each bus owns a separate native effect instance")
	check(music!=null and sfx!=null and music.get_meta(Mix.AUTHORED_EFFECT_META,{}).get("channel")=="Music" and sfx.get_meta(Mix.AUTHORED_EFFECT_META,{}).get("channel")=="SFX","Shared source references cannot overwrite per-bus ownership metadata")
	var untouched:=ResourceLoader.load(effect_path,"AudioEffect",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AudioEffect
	check(not untouched.has_meta(Mix.AUTHORED_EFFECT_META),"Authored source resource remains free of runtime ownership metadata")
	save_layout()
	check(poll(mix),"Removing the shared authored effect is a fresh source edit")
	check(fx("Music")==null and fx("SFX")==null,"Removing shared source FX clears both buses exactly once")
	save_layout(false,true,true)
	check(poll(mix) and mix._external_paths==[effect_path],"CRLF native layout records its actual external effect dependency")
	var root_hash:=FileAccess.get_sha256(layout_path)
	var accepted: String=mix.source_hash
	source.volume_db=12.0
	check(ResourceSaver.save(source,effect_path)==OK,"External parameter changes independently of the CRLF layout")
	check(poll(mix) and root_hash==FileAccess.get_sha256(layout_path) and accepted!=mix.source_hash,"External edit invalidates a CRLF layout with byte-identical root file")
	check(fx("Music") is AudioEffectAmplify and fx("Music").volume_db==12.0,"CRLF dependency reload reaches the real mixer effect with exact new parameter")
	var captures:=0
	for index in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master,index)==capture: captures+=1
	check(captures==1,"Shared/CRLF edits retain the same private capture effect once")
	DirAccess.remove_absolute(layout_path);DirAccess.remove_absolute(effect_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var report:=FileAccess.open(OUTPUT+"fx-dependency-ownership-verification.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"prepared_state":"Isolated ResourceSaver-created native AudioBusLayout references one external Amplify from Music/SFX, then removes it. Actual CRLF root bytes remain identical while separately saved effect changes. Private Master capture kept live."},"\t")+"\n")
	print("AUDIO FX DEPENDENCY OWNERSHIP: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
