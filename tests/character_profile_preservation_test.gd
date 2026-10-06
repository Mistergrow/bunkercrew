extends SceneTree
## Removing a pack leaves its personal settings inert and recoverable on disk.
const Roster := preload("res://scripts/crew_roster.gd")
const Audio := preload("res://scripts/audio.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CHARACTER PROFILE: "+label)
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var rescue_id := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--rescue-id="): rescue_id = argument.trim_prefix("--rescue-id=")
	var absent := "absentpack:saved_worker"
	check(not CharacterCatalog.contains(absent),"fixture character is deliberately absent")
	var path := "user://character-preservation-%d.cfg"%OS.get_process_id()
	var config := ConfigFile.new()
	config.set_value("crew",absent,true)
	config.set_value("crew","absentpack:false_worker",false)
	config.set_value("other","keep","untouched")
	check(config.save(path)==OK,"isolated roster profile created")
	Roster.save_path = path
	Roster.persistence_enabled = true
	Roster._loaded = false
	Roster.unlocked.clear()
	Roster.load_records()
	check(not Roster.is_unlocked(absent) and Roster.unlocked.get(absent)==true,"absent identity stays inert but retains its rescued record")
	check(Roster.unlock("rika"),"present rescue can be added beside absent pack")
	var saved := ConfigFile.new()
	check(saved.load(path)==OK and saved.get_value("crew",absent)==true and saved.get_value("crew","absentpack:false_worker")==false and saved.get_value("other","keep")=="untouched","roster save preserves absent true/false keys and unrelated data")
	Roster._loaded = false
	Roster.unlocked.clear()
	Roster.load_records()
	check(Roster.is_unlocked("rika") and not Roster.is_unlocked(absent),"reload preserves current entitlement without granting missing content")
	if not rescue_id.is_empty():
		check(CharacterCatalog.contains(rescue_id) and not CharacterCatalog.is_unlocked(rescue_id) and not CharacterCatalog.data(rescue_id).has("unlock_site"),"private additional rescue has explicit locked state without a site")
		check(Roster.unlock(rescue_id),"real additional rescue persists despite no predefined site reward")
		check(saved.load(path)==OK and saved.get_value("crew",rescue_id,false)==true,"additional rescue writes its actual ID")
		Roster._loaded = false
		Roster.unlocked.clear()
		Roster.load_records()
		check(CharacterCatalog.is_unlocked(rescue_id),"additional rescue entitlement survives profile reload")
	var audio_path := path+"-audio"
	var saved_move := {"style":"mara_precision_step","intensity":0.35}
	var active_move := {"style":"crew_clap","intensity":0.65}
	config.clear()
	config.set_value("audio","mix_version",2)
	config.set_value("rhythm","dance_profiles",{absent:saved_move,"mara":active_move})
	config.set_value("other","keep","audio-sidecar")
	check(config.save(audio_path)==OK,"isolated audio profile created")
	var audio := Audio.new()
	audio.settings_path = audio_path
	audio.persistence_enabled = true
	audio._load_settings()
	check(audio.dance_profiles.mara==active_move and not audio.dance_profiles.has(absent) and Dance.valid_profiles(audio.dance_profiles),"absent preference does not reset present dancers or enter active configuration")
	audio.dance_profiles.ivo = {"style":"crew_two_step","intensity":0.25}
	audio.save_settings()
	check(saved.load(audio_path)==OK and saved.get_value("rhythm","dance_profiles")[absent]==saved_move and saved.get_value("other","keep")=="audio-sidecar","audio save keeps absent pack preference and unrelated settings exactly")
	audio.free()
	for suffix: String in ["",".bak","-audio"]:
		var temporary := path+suffix
		if FileAccess.file_exists(temporary): DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	Roster.persistence_enabled = false
	print("CHARACTER PROFILE: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
