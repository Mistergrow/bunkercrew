class_name BetaInternetCoopCheck
extends "res://tests/convoy_coop_defense_peer.gd"
## Runs the real four-person defense/repair and reconnect scenario from its PCK.
func _run() -> void:
	role=OS.get_environment("LASTSHIFT_GAMEPLAY_ROLE")
	prefix=OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	slot=OS.get_environment("LASTSHIFT_PARTY_SLOT").to_int()
	if prefix.is_empty() or slot not in [1,2,3,4]:
		await finish(false,"isolated internet role/path missing"); return
	publish("identity"+str(slot),preload("res://tests/internet_peer_identity.gd").capture())
	if not check(OS.get_environment("LASTSHIFT_PARTY_RELAY").begins_with("wss://"),"Internet fixture uses the actual TLS relay"):
		await finish(false,"TLS relay required"); return
	if OS.get_environment("BUNKERCREW_EXPORTED_PEER")=="1" and not check(not OS.has_feature("editor"),"Actual exported template runs its embedded fixture"):
		await finish(false,"exported template required"); return
	await super._run()
