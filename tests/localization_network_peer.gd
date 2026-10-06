extends "res://tests/network_gameplay_peer.gd"
const LOCALE_OPTIONS := {"environment":"mountain_pass","build_type":"bastion","position":"left"}
const NOTICE := "Manuelle Internetadresse: %s. UDP %d muss auf diesen Rechner zeigen."

func host_run() -> void:
	LocaleText.set_locale("en",false)
	game.hud.story_selected=true
	game.network.host_room("")
	if not check(game.network.state=="lobby","English host opens a real ENet room"):
		await finish(false,"host room unavailable")
		return
	publish("room",{"code":game.network.room_code})
	if not await barrier("guest_lobby"):
		await finish(false,"guest missing")
		return
	game.network.start_match(LOCALE_OPTIONS,game.selected_characters)
	if not await wait_for(func(): return playing() and game.network.sent_snapshots>=3,"English host start") or not await barrier("guest_started"):
		await finish(false,"game start failed")
		return
	game.rounds.running=false
	game.story.set_process(false)
	game.medic.set_physics_process(false)
	game.medic.status_label=LocaleText.format("SAN-1 · unterwegs zu P%d",2)
	game.players[1].inventory={"concrete":2,"steel":3}
	game.notify(LocaleText.format(NOTICE,["203.0.113.42",24777]))
	game.network._combat_event("boss",{"title":LocaleText.text("MUTTERMASCHINE"),"subtitle":LocaleText.text("ENDGEGNER / SIGNAL 20"),"portrait":"siege","final_boss":true})
	game.story.say("core_low")
	publish("english_sent",{"serial":game.story.serial})
	if not await barrier("german_received"):
		await finish(false,"German presentation absent")
		return
	check(LocaleText.current_locale()=="en","Guest language never changes the English host")
	if not await barrier("guest_english"):
		await finish(false,"guest switch missing")
		return
	LocaleText.set_locale("de",false)
	game.medic.status_label=LocaleText.format("SAN-1 · P%d %s",[2,"Reanimation"])
	game.notify(LocaleText.format(NOTICE,["203.0.113.43",24778]))
	game.story.say("warning_air")
	publish("german_sent",{"serial":game.story.serial})
	if not await barrier("english_received"):
		await finish(false,"English presentation absent")
		return
	check(LocaleText.current_locale()=="de" and game.players[1].inventory=={"concrete":2,"steel":3},"Language switch preserves host world values and resource IDs")
	var old_scene:int=game.get_instance_id()
	game.network.restart_match()
	if not await wait_for(func(): return game.get_instance_id()!=old_scene and playing(),"localized rematch") or not await barrier("rematch_seen"):
		await finish(false,"rematch failed")
		return
	check(LocaleText.current_locale()=="de","Host language survives actual scene reload")
	publish("finish")
	if not await barrier("guest_done"):
		await finish(false,"guest incomplete")
		return
	await finish(failures==0,"independent locale, typed notices, dialogue, boss and rematch")

func guest_run() -> void:
	LocaleText.set_locale("de",false)
	game.network.join_room("",str(read_stage("room").get("code","")))
	if not await wait_for(func(): return game.network.state=="lobby" and game.network.peer_connected,"German guest lobby"):
		await finish(false,"join failed")
		return
	publish("guest_lobby")
	if not await wait_for(func(): return playing() and game.network.received_snapshots>=3,"German guest scene"):
		await finish(false,"world missing")
		return
	check(LocaleText.current_locale()=="de" and game.story_mode,"English host does not overwrite German story selection")
	publish("guest_started")
	if not await barrier("english_sent") or not await wait_for(func(): return game.notice.contains("203.0.113.42") and game.hud.combat_overlay.boss.get("final_boss",false),"localized German snapshot and boss"):
		await finish(false,"German events missing")
		return
	check(game.notice=="Manuelle Internetadresse: 203.0.113.42. UDP 24777 muss auf diesen Rechner zeigen.","English host's formatted notice renders in German")
	check(game.medic.status_label=="SAN-1 · unterwegs zu P2","English medic rescue status renders in German on a fresh peer")
	check(game.hud.combat_overlay.boss.title=="MUTTERMASCHINE","English boss name translates on the receiving peer")
	check(game.players[1].inventory=={"concrete":2,"steel":3},"Translated inventory retains canonical material identifiers")
	var serial:int=int(read_stage("english_sent").serial)
	if not await wait_for(func(): return game.dialogue._seen.has(serial),"German authored dialogue"):
		await finish(false,"dialogue missing")
		return
	check(_line_language(serial,"de"),"German guest chooses German text and recording for the host's dialogue ID")
	publish("german_received")
	LocaleText.set_locale("en",false)
	check(LocaleText.text(game.notice).begins_with("Manual internet address:"),"Live switch updates an existing received notice")
	check(LocaleText.text(game.medic.status_label)=="SAN-1 · En route to P2","Live switch updates the received medic status")
	publish("guest_english")
	if not await barrier("german_sent") or not await wait_for(func(): return game.notice.contains("203.0.113.43"),"English notice from German host"):
		await finish(false,"reverse language pair missing")
		return
	check(game.notice=="Manual internet address: 203.0.113.43. Forward UDP 24778 to this computer.","German host's formatted notice renders in English")
	check(game.medic.status_label==LocaleText.format("SAN-1 · P%d %s",[2,"Reanimation"]),"German medic treatment and its nested action name render in English")
	serial=int(read_stage("german_sent").serial)
	if not await wait_for(func(): return game.dialogue._seen.has(serial),"English authored dialogue"):
		await finish(false,"English line missing")
		return
	check(_line_language(serial,"en"),"English guest uses the English recording path independently")
	var scene_id:int=game.get_instance_id()
	publish("english_received")
	if not await wait_for(func(): return game.get_instance_id()!=scene_id and playing(),"guest actual rematch"):
		await finish(false,"rematch absent")
		return
	check(LocaleText.current_locale()=="en" and game.story.stage==0,"Guest retains English through rematch with a German host")
	publish("rematch_seen")
	if not await barrier("finish"):
		await finish(false,"host did not finish")
		return
	publish("guest_done")
	await finish(failures==0,"German and English presentation over real ENet")

func _line_language(serial:int,code:String) -> bool:
	var candidates:Array=game.dialogue.pending.duplicate()
	if not game.dialogue.active.is_empty(): candidates.append(game.dialogue.active)
	for line:Dictionary in candidates:
		if int(line.serial)!=serial: continue
		var expected:=StoryDialogueCatalog.line(line.id,line.speaker_id)
		return line.text==expected.text and (str(line.voice_path).contains("/en/")== (code=="en"))
	return false
