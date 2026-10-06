extends SceneTree
const Settings=preload("res://scripts/violence_settings.gd")
var checks:=0
var failures:=0
func check(value: bool,label: String):
	checks+=1
	print("VIOLENCE SETTINGS ","PASS " if value else "FAIL ",label)
	if not value: failures+=1
func _initialize():
	var settings:=Settings.new()
	settings.settings_path="user://violence-regression.cfg"
	var path:=ProjectSettings.globalize_path(settings.settings_path)
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	settings.load_settings()
	check(settings.level==2,"An absent profile uses the requested full presentation")
	check(not settings.set_level(-1) and not settings.set_level(3) and settings.level==2,"Unsupported setting values cannot enter the renderer")
	check(settings.set_level(1) and settings.level==1,"Blood-only selection applies locally")
	var other:=Settings.new()
	other.settings_path=settings.settings_path
	other.load_settings()
	if "--no-profile-save" in OS.get_cmdline_user_args():
		check(not FileAccess.file_exists(path) and other.level==2,"No-profile-save prevents writes and loading shared user settings")
	else:
		check(FileAccess.file_exists(path) and other.level==1,"A separate settings instance loads the saved local selection")
		var config:=ConfigFile.new()
		config.set_value("graphics","violence","Full")
		config.save(path)
		other=Settings.new()
		other.settings_path=settings.settings_path
		other.load_settings()
		check(other.level==2,"Malformed configuration falls back to a valid level")
		DirAccess.remove_absolute(path)
	print("VIOLENCE SETTINGS: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
