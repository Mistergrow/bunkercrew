extends RefCounted
const Protocol := preload("res://scripts/network_protocol.gd")
## Identity of the actual running executable; package hashes are recorded by
## the launcher, including the PCK. Wine is labelled by the launcher, not guessed.
static func capture() -> Dictionary:
	return {"os":OS.get_name(),"engine":Engine.get_version_info().string,
		"application_version":str(ProjectSettings.get_setting("application/config/version","")),
		"network_build":Protocol.BUILD,"world_revision":Protocol.WORLD_REVISION,
		"exported_template":not OS.has_feature("editor"),
		"executable":OS.get_executable_path(),"microphone_test":"synthetic only"}
