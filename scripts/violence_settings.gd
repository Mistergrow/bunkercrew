extends RefCounted
## Per-device presentation preference; never part of authoritative match state.
const OFF := 0
const BLOOD := 1
const FULL := 2
var level := FULL
var settings_path := "user://violence.cfg"

func load_settings() -> void:
	if "--no-profile-save" in OS.get_cmdline_user_args(): return
	var config := ConfigFile.new()
	if config.load(settings_path)!=OK: return
	var value: Variant=config.get_value("graphics","violence",FULL)
	if value is int and value in [OFF,BLOOD,FULL]: level=value

func set_level(value: int) -> bool:
	if value not in [OFF,BLOOD,FULL] or value==level: return false
	level=value
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		var config:=ConfigFile.new()
		config.set_value("graphics","violence",level)
		config.save(settings_path)
	return true
