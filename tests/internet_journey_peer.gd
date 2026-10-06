class_name BetaInternetJourneyCheck
extends "res://tests/network_four_peer.gd"
## Full authenticated campaign handoff and completed wheel repair from the PCK.
func _run() -> void:
	overall_timeout_ms=110000
	role=OS.get_environment("LASTSHIFT_GAMEPLAY_ROLE")
	prefix=OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	slot=OS.get_environment("LASTSHIFT_PARTY_SLOT").to_int()
	if prefix.is_empty() or slot not in [1,2,3,4] or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		await finish(false,"isolated internet role/path/flags missing"); return
	publish("identity"+str(slot),preload("res://tests/internet_peer_identity.gd").capture())
	if not check(OS.get_environment("LASTSHIFT_PARTY_RELAY").begins_with("wss://"),"Full journey fixture uses the actual TLS relay"):
		await finish(false,"TLS relay required"); return
	if OS.get_environment("BUNKERCREW_EXPORTED_PEER")=="1" and not check(not OS.has_feature("editor"),"Actual exported template runs its embedded journey fixture"):
		await finish(false,"exported template required"); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/expedition"))
	await super._run()
