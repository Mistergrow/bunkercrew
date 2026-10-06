extends "res://tests/network_gameplay_peer.gd"
## Two actual peers; combat poses and cargo are prepared, all synchronization uses ENet.
var heard_sounds: Dictionary = {}

func observe_sounds() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.audio): return
	for voice in game.audio.voices:
		var kind: String = str(voice.get_meta("kind",""))
		if not kind.is_empty(): heard_sounds[kind] = true

func host_run() -> void:
	process_frame.connect(observe_sounds)
	LocaleText.set_locale("de")
	game.network.host_room("")
	publish("room",{"code":game.network.room_code})
	if not await barrier("joined"):
		await finish(false,"lobby")
		return
	game.network.start_match(OPTIONS,game.selected_characters)
	if not await wait_for(func():return playing(),"host match") or not await barrier("guest_started"):
		await finish(false,"start")
		return
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	for worker in game.players: worker.set_physics_process(false)
	game.rounds.wave = 7
	game.rounds.phase = "build"
	game.rounds.begin_warning()
	check(not game.rounds.air_wave_enabled,"Unbuilt AA keeps the real host ground-only")
	publish("ground_warning")
	if not await barrier("ground_seen"):
		await finish(false,"ground warning")
		return
	game.flak_station.unlock()
	game.flak_station.materials = FlakStation.SPECS[1].cost.duplicate()
	game.flak_station.interact(game.players[0],3.0)
	game.flak_station.turret.set_physics_process(false)
	game.rounds.phase = "build"
	game.rounds.begin_warning()
	publish("air_warning")
	if not await barrier("air_seen"):
		await finish(false,"air warning")
		return
	var gun = game.turret
	gun.set_physics_process(false)
	gun.enter(game.players[0])
	var angles := [0.35,-1.1,-2.6]
	for index in angles.size():
		gun.aim_angle = angles[index]
		gun.occupant.facing = gun.facing_direction()
		gun.occupant.global_position = gun.operator_position()
		gun.pose_barrel()
		publish("pose_%d"%index)
		if not await barrier("pose_seen_%d"%index):
			await finish(false,"mounted pose")
			return
	gun.ammo = 0
	gun.reserve = 20
	check(gun.start_reload(),"Real mounted reload starts with finite reserve")
	gun._physics_process(0.6)
	gun._physics_process(0.6)
	check(gun.ammo==20 and gun.reserve==0,"Real reload transfers exactly its twenty reserved rounds")
	publish("reload_sent")
	if not await barrier("reload_heard"):
		await finish(false,"reload audio")
		return
	game.upgrades.add_points(6)
	check(game.upgrades.purchase("bunker_workshop"),"Host pays the prerequisite technology")
	publish("upgrade_ready")
	if not await barrier("upgrade_sent") or not await wait_for(func():return game.upgrades.has_upgrade("medic_logistics"),"guest logistics purchase"):
		await finish(false,"upgrade")
		return
	check(game.upgrades.points==0,"Guest purchase consumes shared points exactly once")
	var crates := get_nodes_in_group("supplies").filter(func(node):return node.game==game and node.kind=="sand" and node.amount>0)
	if not check(not crates.is_empty(),"Prepared cargo has a real stock source"):
		await finish(false,"source")
		return
	var source = crates[0]
	var stock: int = source.amount
	source.amount -= 1
	game.medic.logistics_cargo = "sand"
	game.medic.logistics_phase = "deliver"
	game.medic.logistics_progress = 0.5
	game.medic.status_label = LocaleText.format("SAN-1 · %s liefern",Balance.RESOURCE_NAMES.sand)
	check(source.amount+1==stock,"Prepared robot cargo is removed from the source stock")
	publish("cargo_ready")
	if not await barrier("cargo_seen"):
		await finish(false,"cargo replication")
		return
	var instance: int = game.get_instance_id()
	game.network.transport.disconnect_guest()
	if not await wait_for(func():return game.network.state=="reconnecting" and paused,"host disconnect"):
		await finish(false,"disconnect")
		return
	if not await wait_for(func():return playing(),"host reconnect",12.0) or not await barrier("cargo_reconnected",12.0):
		await finish(false,"reconnect")
		return
	check(game.get_instance_id()==instance and game.medic.logistics_cargo=="sand" and source.amount==stock-1,"Reconnect preserves robot cargo and original stock deduction")
	publish("host_passed")
	if not await barrier("guest_passed"):
		await finish(false,"completion")
		return
	publish("finish")
	await finish(failures==0,"AA readiness, attached poses, positioned reload audio and logistics upgrade/cargo")

func guest_run() -> void:
	process_frame.connect(observe_sounds)
	LocaleText.set_locale("en")
	game.network.join_room("",str(read_stage("room").get("code","")))
	if not await wait_for(func():return game.network.peer_connected and game.network.state=="lobby","guest lobby"):
		await finish(false,"lobby")
		return
	publish("joined")
	if not await wait_for(func():return playing() and game.network.received_snapshots>=3,"guest match"):
		await finish(false,"start")
		return
	publish("guest_started")
	if not await barrier("ground_warning") or not await wait_for(func():return game.rounds.wave==7 and game.rounds.phase=="warning","ground warning snapshot"):
		await finish(false,"ground warning")
		return
	check(not game.rounds.air_wave_enabled,"Guest receives ground-only wave eligibility")
	publish("ground_seen")
	if not await barrier("air_warning") or not await wait_for(func():return game.flak_station.built and game.rounds.air_wave_enabled,"paid AA and air warning"):
		await finish(false,"air warning")
		return
	check(game.flak_station.turret.hp>0 and "AIR RAID" in game.notice,"English guest receives the real tower and translated air warning")
	publish("air_seen")
	var angles := [0.35,-1.1,-2.6]
	for index in angles.size():
		if not await barrier("pose_%d"%index) or not await wait_for(func():return is_instance_valid(game.players[0].mounted_turret) and absf(game.turret.aim_angle-float(angles[index]))<0.001,"mounted angle"):
			await finish(false,"pose")
			return
		var worker = game.players[0]
		game.network.world.interpolate(0.0)
		var visual = worker.get_node("PixelVisual")
		visual._process(0.0)
		check(worker.global_position.distance_to(game.turret.operator_position())<0.01,"Remote operator stays attached immediately across angle and side changes")
		check(visual.special_pose=="mounted" and not visual.pose_skeleton.is_empty(),"Remote worker uses the articulated mounted pose")
		var anchors: Dictionary = game.turret.operator_pose_anchors()
		for hand in 2:
			check(worker.to_global(visual.pose_skeleton.hands[hand]*Vector2(worker.facing,1)).distance_to(anchors.hands[hand])<0.05,"Remote hand coincides with its visible gun grip")
		publish("pose_seen_%d"%index)
	if not await barrier("reload_sent") or not await wait_for(func():return heard_sounds.has("reload_cannon_open") and heard_sounds.has("reload_cannon_load") and heard_sounds.has("reload_cannon_close"),"three spatial reload phases"):
		await finish(false,"reload audio")
		return
	check(game.network._events.is_empty(),"Received reload sounds never broadcast back to the host")
	check(game.audio.voices.any(func(voice):return voice.get_meta("kind","")=="reload_cannon_close" and voice.get_meta("acoustic_source",Vector2.INF)==game.turret.handling_sound_position()),"Reload closes at the gun's actual spatial sound source")
	publish("reload_heard")
	if not await barrier("upgrade_ready") or not await wait_for(func():return game.upgrades.has_upgrade("bunker_workshop") and game.upgrades.points==4,"shared upgrade budget"):
		await finish(false,"technology")
		return
	game.network.send_command("upgrade",{"id":"medic_logistics"})
	game.network.send_command("upgrade",{"id":"medic_logistics"})
	publish("upgrade_sent")
	if not await barrier("cargo_ready") or not await wait_for(func():return game.medic.logistics_cargo=="sand" and game.upgrades.has_upgrade("medic_logistics"),"robot cargo"):
		await finish(false,"cargo")
		return
	check(game.medic.logistics_phase=="deliver" and is_equal_approx(game.medic.logistics_progress,0.5),"Robot phase and partial handling time replicate")
	check(game.medic.status_label==LocaleText.format("SAN-1 · %s liefern",Balance.RESOURCE_NAMES.sand),"German robot status translates to the guest's English locale")
	check(not game.medic.is_physics_processing() and game.upgrades.points==0,"Guest cannot run a second robot simulation or spend the upgrade twice")
	publish("cargo_seen")
	if not await wait_for(func():return game.network.state=="reconnecting" and paused,"guest disconnect") or not await wait_for(func():return playing(),"guest reconnect",12.0):
		await finish(false,"reconnect")
		return
	check(game.medic.logistics_cargo=="sand" and game.medic.logistics_phase=="deliver","Authenticated reconnect retains the in-transit robot item")
	publish("cargo_reconnected")
	if not await barrier("host_passed"):
		await finish(false,"host completion")
		return
	publish("guest_passed")
	if not await barrier("finish"):
		await finish(false,"finish")
		return
	await finish(failures==0,"remote poses, reload phases, localized robot cargo and reconnect")
