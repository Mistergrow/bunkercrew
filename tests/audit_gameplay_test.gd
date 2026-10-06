extends SceneTree
var checks := 0
var failures := 0
var game
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	check(game.players.is_empty() and not is_instance_valid(game.core),"Menu does not construct the unused legacy world")
	game.hud._restart_match()
	check(not is_instance_valid(game.hud.restart_dialog),"F5 in the main menu does not restart")
	var saved_selection: Dictionary=ScenarioCatalog.last_selection.duplicate()
	ScenarioCatalog.last_selection={"environment":"radar_highlands","build_type":"workshop","position":"left"}
	game.hud._open_scenario_selection(1)
	await process_frame
	await process_frame
	check(ScenarioCatalog.environments().any(func(entry):return entry.id==game.hud.scenario_panel.options.environment),"Free setup replaces a campaign-only previous environment with a visible choice")
	ScenarioCatalog.last_selection=saved_selection
	game.hud._close_scenario_selection()
	game.start(1)
	game.rounds.running=false
	check(is_instance_valid(game.expansion) and is_instance_valid(game.core),"Classic start constructs the original playable bunker")
	game.hud._restart_match()
	check(game.hud.restart_dialog.visible and paused,"Active restart requires a paused confirmation")
	game.hud._cancel_restart()
	check(not game.hud.restart_dialog.visible and not paused,"Cancel restores the running game")
	paused=true
	game.hud.overlay="audio"
	game.hud._restart_match()
	game.hud._cancel_restart()
	check(paused and game.hud.overlay=="audio","Cancel preserves an already paused options menu")
	game.campaign.active=true
	game.campaign.blueprints=["siege_optics"]
	game.turret.position=Vector2(1200,-300)
	game.turret.aim_angle=0
	game.turret.cooldown=0
	game.turret.ammo=10
	await physics_frame
	check(game.turret.fire(),"Prepared roof gun fires with siege optics")
	var found := false
	for child in game.get_children():
		if child.get_script()==preload("res://scripts/projectile.gd"):
			found=true
			check(is_equal_approx(child.damage,float(Balance.SHOT_DAMAGE)*1.15),"Siege optics adds fifteen percent to actual roof projectiles")
	check(found,"Roof shot creates a real projectile")
	var flak=FlakTurret.new()
	flak.game=game
	flak.position=Vector2(1300,-450)
	game.add_child(flak)
	flak.ammo=3
	await physics_frame
	check(flak.fire(),"Prepared flak fires with siege optics")
	var flak_found := false
	for child in game.get_children():
		if child.get_script()==preload("res://scripts/flak_projectile.gd"):
			flak_found=true
			check(is_equal_approx(child.damage,float(flak.spec().damage)*1.15),"Siege optics adds fifteen percent to actual flak shells")
	check(flak_found,"Flak creates a real shell")
	game.rounds.wave=20
	game.network.active=true
	game.network.is_host=false
	game.combat_events.unlocked.erase("pristine_core")
	game.core.hp=game.core.max_hp
	game.combat_events._victory_secrets()
	check(not game.combat_events.unlocked.has("pristine_core"),"A guest cannot infer pristine history from a repaired core")
	game.combat_events.unlock("pristine_core")
	check(game.combat_events.unlocked.has("pristine_core"),"Guest can still accept an explicit authoritative achievement")
	game.network.active=false
	game.network.is_host=true
	game.combat_events.unlocked.erase("pristine_core")
	game.core.set_meta("achievement_core_damaged",true)
	game.combat_events._victory_secrets()
	check(not game.combat_events.unlocked.has("pristine_core"),"Host rejects pristine after repaired historical damage")
	game.join_coop()
	game.join_coop()
	game.join_coop()
	var all_players: Array=game.players.duplicate()
	for kind in EnemyCatalog.GROUND_CLASSES:
		for crew in [1,4]:
			game.player_count=crew
			game.players=all_players.slice(0,crew)
			var enemy=load("res://scenes/enemy.tscn").instantiate()
			enemy.game=game
			enemy.kind=kind
			enemy.wave=20
			enemy.elite=true
			game.add_child(enemy)
			enemy.set_physics_process(false)
			if enemy.profile.has("worker_damage"):
				var expected=float(enemy.profile.worker_damage)*Balance.enemy_damage_multiplier(crew)*EnemyCatalog.damage_scale(20)*EnemyCatalog.ELITE_DAMAGE_SCALE
				check(is_equal_approx(enemy.worker_shot_damage(),expected),"Profile worker damage scales with wave, elite and crew: "+kind)
			enemy.queue_free()
	game.players=all_players
	for wave in [1,10]:
		var roster=EnemyCatalog.wave_roster(wave,12,true)
		for kind in EnemyCatalog.GROUND_CLASSES:
			if not EnemyCatalog.is_human(kind) and EnemyCatalog.INTRO_WAVES[kind]==wave:
				check(kind in roster,"Every simultaneous ground introduction survives: "+kind)
	var audio=game.audio
	check(not audio.persistence_enabled,"No-profile command line disables audio persistence by default")
	audio.settings_path="user://audit-no-save-%d.cfg"%OS.get_process_id()
	audio.persistence_enabled=false
	audio.set_music_volume(.37)
	audio.save_settings()
	check(not FileAccess.file_exists(audio.settings_path),"No-profile audio changes do not create a settings file")
	for index in LocaleText.MAX_MESSAGES+80: LocaleText.format("Ping: %d ms",index)
	check(LocaleText._messages.size()<=LocaleText.MAX_MESSAGES,"Formatted message cache stays bounded after overflow")
	var latest=LocaleText.format("Ping: %d ms",123456)
	check(LocaleText.message_payload(latest).get("args")==123456,"Newest formatted value retains its network payload after eviction")
	var previous_id: int=game.get_instance_id()
	# The earlier optics checks enabled campaign bonuses on the classic
	# fixture without constructing a campaign checkpoint.
	game.campaign.active = false
	game.hud._restart_match()
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/audit-followup/restart-confirmation.png")
	game.hud.restart_dialog.confirmed.emit()
	for frame in 5: await process_frame
	game=current_scene
	check(game.get_instance_id()!=previous_id and game.started and game.players.size()==4,"Confirming restart loads a fresh mission with the same four-person crew")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("AUDIT GAMEPLAY: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
