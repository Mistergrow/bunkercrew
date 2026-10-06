extends SceneTree
## Real main scene, routed UI input and real progression purchases. Optional
## screenshots use explicitly arranged XP/events for presentation, not gameplay.
var game
var checks := 0
var failures := 0
var capture_images := false

func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func frames(count: int=2):
	for frame in count: await process_frame
func press(action: String):
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await frames()
func capture(name: String):
	if not capture_images: return
	await frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/personal-%s.png" % name)
	print("RENDERED UI FIXTURE ",name)
func _layout_clear(layout: Array) -> bool:
	for first in layout.size():
		for second in range(first+1,layout.size()):
			if layout[first].rect.intersects(layout[second].rect): return false
	return true

func run():
	capture_images = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.combat_events.unlocked.clear()
	await frames()
	check(game.selected_characters.slice(0,2)==["mara","branko"],"Fresh coop slots offer two distinct identities by default")
	await press("join")
	check(game.hud.overlay=="scenario" and paused and not game.started,"Coop start opens scenario setup first")
	game.hud.scenario_panel.next_button.pressed.emit()
	await frames()
	check(game.hud.overlay=="characters" and paused and not game.started and game.players.is_empty(),"Coop menu opens selection without constructing unused workers")
	var selection: CharacterSelectPanel = game.hud.character_panel
	check(selection.player_count==2 and selection.cards.size()==CharacterCatalog.CHARACTERS.size() and not selection.slot_buttons[1].disabled,"Coop selection offers all eight characters and both independent worker slots")
	selection.cards[0].grab_focus()
	await press("ui_down")
	check(selection.cards[1].has_focus(),"Standard keyboard/controller down navigation reaches the next character row")
	await press("ui_accept")
	check(game.selected_characters[0]=="branko" and not game.started,"Accepting a card selects Branko without prematurely beginning the round")
	selection.slot_buttons[1].pressed.emit()
	selection.cards[2].pressed.emit()
	check(game.selected_characters.slice(0,2)==["branko","ivo"],"P2 can choose Ivo without changing P1's Branko selection")
	await capture("character-selection")
	await press("audio_settings")
	check(game.hud.overlay=="characters" and paused,"A selection modal cannot be replaced by an unrelated audio panel")
	await press("ui_cancel")
	check(game.hud.overlay=="scenario" and not game.started,"Character cancel returns to the chosen scenario")
	await press("ui_cancel")
	check(game.hud.overlay=="menu" and not game.started,"Controller cancel returns safely to the main menu")
	await press("join")
	game.hud.scenario_panel.next_button.pressed.emit()
	await frames()
	selection = game.hud.character_panel
	check(game.selected_characters.slice(0,2)==["branko","ivo"],"Returning to selection preserves both explicit choices")
	selection.cards[-1].grab_focus()
	await press("ui_down")
	check(selection.begin_button.has_focus(),"Keyboard/controller down navigation reaches explicit Begin")
	await press("ui_accept")
	await frames()
	check(game.started and not paused and game.players.size()==2,"Explicit Begin button starts real local coop")
	check(game.players[0].character_id=="branko" and game.players[0].hp==125 and game.players[1].character_id=="ivo" and game.players[1].hp==90,"Chosen identities apply actual catalog HP before play")
	game.rounds.running = false
	game.players[1].progression.award_damage(500)
	await press("personnel")
	var personal: PersonalPanel = game.hud.personal_panel
	check(paused and game.hud.overlay=="personal" and personal.player_buttons.size()==2,"P opens a paused personal panel with two worker tabs")
	check(personal.skill_buttons.combat.disabled,"P1 cannot spend P2's earned personal skill point")
	personal.player_buttons[1].pressed.emit()
	check(personal.selected_player==1 and not personal.skill_buttons.engineering.disabled,"Selecting P2 displays P2's actual available personal point")
	personal.skill_buttons.engineering.pressed.emit()
	check(game.players[1].progression.skills.engineering==1 and game.players[1].progression.skill_points==0 and game.players[0].progression.skills.engineering==0,"Actual skill button buys exactly one rank for its selected worker")
	check(personal.skill_buttons.engineering.disabled,"Unaffordable skill button disables immediately after purchase")
	game.players[1].progression.equip_armor(1)
	await capture("progression")
	await press("help")
	await press("audio_settings")
	check(game.hud.overlay=="personal" and paused,"Help and audio cannot bypass the active personal modal")
	game.combat_events.unlock("first_kill")
	game.combat_events.unlock("armor")
	await press("achievements")
	check(personal.tab=="achievements" and game.combat_events.records().size()==26,"F6 selects all 21 public and five hidden persistent achievement records")
	check(game.combat_events.records().filter(func(entry): return entry.unlocked).size()==2,"Achievement presentation reads only genuinely unlocked service records")
	personal.change_achievement_page(1)
	personal.change_achievement_page(1)
	check(personal.achievement_page==2 and personal.page_buttons[1].disabled and not personal.page_buttons[0].disabled,"All 26 achievements are reachable across three bounded pages")
	personal.change_achievement_page(1)
	check(personal.achievement_page==2,"Achievement navigation stops at its final page")
	personal.change_achievement_page(-2)
	for language in ["de","en"]:
		LocaleText.set_locale(language,false)
		var achievements_fit := true
		for entry: Dictionary in CombatEvents.ACHIEVEMENTS:
			achievements_fit = achievements_fit and UiArt.wrap_text(str(entry.title),PersonalPanel.ACHIEVEMENT_TITLE_WIDTH,16).size() <= 2 and UiArt.wrap_text(str(entry.detail),PersonalPanel.ACHIEVEMENT_DETAIL_WIDTH,13).size() <= 4
		check(achievements_fit,language+" achievement titles and full descriptions fit without cropping or shrinking")
		var skills_fit := true
		for spec: Dictionary in PlayerProgression.SKILL_SPECS.values():
			skills_fit = skills_fit and UiArt.wrap_text(str(spec.detail),490,16).size() <= 2
		check(skills_fit,language+" skill effects retain readable type clear of purchase controls")
	LocaleText.set_locale("de",false)
	await capture("achievements")
	await press("personnel")
	check(not paused and game.hud.overlay.is_empty(),"Closing personal UI resumes the previously running round")
	await press("pause")
	await press("personnel")
	await press("ui_cancel")
	check(paused and game.hud.overlay=="pause","Closing personal UI opened from pause restores the pause screen")
	await press("pause")
	var feedback: CombatOverlay = game.hud.combat_overlay
	feedback._support_clock=1000
	feedback._support_pending.clear()
	feedback.numbers.clear()
	feedback.banners.clear()
	for pellet in 8:
		game.combat_events.event.emit("hit",{"player_id":1,"amount":9.0,"earned":0.9,"position":Vector2(900,395)})
	check(feedback.numbers.size()==1 and is_equal_approx(feedback.numbers[0].amount,72.0) and is_equal_approx(feedback.numbers[0].earned,7.2),"Coincident shotgun pellets merge into one exact damage/XP total")
	check(feedback._number_text(0.1)=="0.1" and feedback._number_text(14.0)=="14","Fractional XP never displays as a falsely rounded-up whole point")
	# Real normal-HP enemies and authoritative damage/XP events, with normal
	# automatic-fire spacing. This catches the overlap from the combat gallery.
	feedback.numbers.clear()
	feedback.banners.clear()
	var worker = game.players[0]
	var first = game.ENEMY.instantiate()
	first.game = game
	first.kind = "runner"
	first.position = Vector2(1140,430)
	game.add_child(first)
	first.set_physics_process(false)
	var normal_hp: float=first.max_hp
	var xp_share: float=(1.0+.35*(game.players.size()-1))/game.players.size()
	for tick in 3:
		game.combat_hit(first,16.0,worker)
		first.position.x -= 32.0
		await create_timer(0.20).timeout
	check(feedback.numbers.size()==1 and is_equal_approx(feedback.numbers[0].amount,48.0) and is_equal_approx(feedback.numbers[0].earned,4.8*xp_share),"Automatic rifle ticks aggregate by real enemy identity across movement and 0.20-second intervals")
	game.combat_hit(first,16.0,worker)
	check(feedback.numbers.size()==1 and feedback.numbers[0].kind=="kill" and is_equal_approx(feedback.numbers[0].amount,normal_hp) and is_equal_approx(feedback.numbers[0].earned,(normal_hp*.1+14)*xp_share),"Lethal hit replaces its complete burst with exact damage plus hit/kill XP without double-counting")
	for victim_index in 4:
		var victim = game.ENEMY.instantiate()
		victim.game = game
		victim.kind = "runner"
		victim.position = Vector2(1140,430)
		game.add_child(victim)
		victim.set_physics_process(false)
		for tick in 4:
			game.combat_hit(victim,16.0,worker)
			await create_timer(0.025).timeout
	check(feedback.numbers.size()==5 and feedback.numbers.all(func(entry): return entry.kind=="kill" and is_equal_approx(entry.amount,normal_hp)),"Five rapid sequential kills leave five complete summaries, with no orphan rifle ticks")
	var layout: Array = feedback.number_layout()
	check(layout.size()==feedback.numbers.size() and _layout_clear(layout),"All five coincident two-line damage/XP summaries occupy non-overlapping screen rectangles")
	check(worker.progression.kills==5 and worker.progression.level==2 and is_equal_approx(worker.progression.xp,(normal_hp*.1*5+14*5.8)*xp_share-50),"Visual aggregation preserves all five real kill credits and the equal bounded share of five real kills")
	check(worker.progression.combo==5 and feedback.numbers.all(func(entry): return not feedback._number_lines(entry)[0].contains("SERIE") and not feedback._number_lines(entry)[1].contains("SERIE")),"Only the current per-player HUD series remains; old corpse labels never repeat outdated combos")
	feedback.numbers.clear()
	feedback._support_pending.clear()
	for event_index in 20: game.combat_events.event.emit("support",{"player_id":2,"action":"repair","earned":.2})
	check(feedback.numbers.is_empty(),"Support XP accumulates without frame-by-frame floating text")
	feedback._flush_support()
	check(feedback.numbers.size()==1 and feedback.numbers[0].kind=="support" and is_equal_approx(feedback.numbers[0].earned,4.0),"Useful role rewards combine into one bounded floating XP summary")
	feedback.numbers.clear()
	for enemy_id in [9001,9002]:
		game.combat_events.event.emit("hit",{"player_id":1,"enemy_id":enemy_id,"amount":10.0,"earned":1.0,"position":Vector2(1100,395)})
	check(feedback.numbers.size()==2 and _layout_clear(feedback.number_layout()),"Distinct enemies at the same position keep separate exact hit totals and readable lanes")
	game.combat_events.event.emit("hit",{"player_id":2,"enemy_id":9001,"amount":7.0,"earned":0.7,"position":Vector2(1100,395)})
	check(feedback.numbers.size()==3 and feedback.numbers[-1].player_id==2 and is_equal_approx(feedback.numbers[-1].earned,0.7) and _layout_clear(feedback.number_layout()),"Coop contributions stay attributed to their owner and never overlap neighboring damage/XP text")
	feedback.numbers.clear()
	for hit in 100:
		game.combat_events.event.emit("hit",{"player_id":1,"amount":1.0,"earned":0.1,"position":Vector2(300+hit*35,395)})
	check(feedback.numbers.size()==CombatOverlay.MAX_NUMBERS,"Normal hit-number storage remains bounded under a hundred incoming events")
	game.weather.reduced_effects = true
	for hit in 20:
		game.combat_events.event.emit("hit",{"player_id":2,"amount":1.0,"earned":0.1,"position":Vector2(300+hit*35,360)})
	check(feedback.numbers.size()<=8,"Reduced effects also limits floating combat messages to eight")
	game.weather.reduced_effects = false
	feedback.numbers.clear()
	feedback.banners.clear()
	for level in 20: game.combat_events.event.emit("level_up",{"player_id":1,"level":level+2})
	check(feedback.banners.size()==CombatOverlay.MAX_BANNERS,"Level/achievement notification queue remains bounded")
	feedback.banners.clear()
	game.combat_events.event.emit("level_up",{"player_id":2,"level":2})
	var notification_rect: Rect2 = feedback.notification_bounds()
	check(game.hud.screen_rect().encloses(notification_rect) and notification_rect.end.x < game.hud.status_bounds().position.x,"Level feedback stays at the left edge and clear of the central status and bunker")
	game.combat_events.event.emit("hit",{"player_id":1,"amount":16.8,"earned":1.68,"position":Vector2(865,387)})
	game.combat_events.event.emit("kill",{"player_id":2,"earned":16.24,"combo":3,"position":Vector2(1050,380)})
	await capture("combat-feedback")
	if capture_images:
		# Presentation-only full upgraded backpack; these materials are arranged.
		var cargo: Dictionary = game.players[0].inventory.duplicate(true)
		var original_engineering: int = game.players[0].progression.skills.engineering
		game.players[0].progression.skills.engineering = 4
		game.players[0].inventory = {"sand":1,"ore":1,"steel":1,"alloy":1,"concrete":1,"ammo":1,"jaw_trap":1,"blast_trap":1,"sentry_kit":1}
		await capture("nine-material-slots")
		game.players[0].inventory = cargo
		game.players[0].progression.skills.engineering = original_engineering
	var number_age: float = feedback.numbers[0].age
	await press("pause")
	await create_timer(0.12,true).timeout
	check(feedback.numbers[0].age-number_age<0.05,"Combat numbers and badges stop ageing while the game is paused")
	await press("pause")
	game.rounds.wave = 20
	game.rounds.phase = "attack"
	game.spawn_enemy(20,11,12)
	await frames()
	check(not feedback.boss.is_empty() and feedback.boss.title=="MUTTERMASCHINE" and not game.combat_events.boss_status().is_empty(),"Actual final-boss spawn drives its portrait announcement and live health bar")
	check(not feedback.notification_bounds(true).intersects(feedback.boss_status_bounds()) and feedback.boss_status_bounds().position.y >= game.hud.status_bounds().end.y,"Compact boss arrival and health remain in separate edge regions")
	var was_treating: bool=game.medic.treating
	game.medic.treating=true
	check(not game.hud.auxiliary_status_bounds().intersects(feedback.boss_status_bounds()),"SAN treatment status stacks below the live boss health bar")
	game.medic.treating=was_treating
	await create_timer(0.4).timeout
	await capture("boss-transmission")
	game.combat_events.event.emit("boss_phase",{"title":"MUTTERMASCHINE","subtitle":"ANTRIEB FREIGELEGT / DOPPELSALVE","portrait":"siege"})
	check(feedback.boss.subtitle.contains("DOPPELSALVE"),"Real boss-phase event refreshes the industrial transmission")
	feedback.boss.clear()
	feedback.banners.clear()
	await create_timer(1.3).timeout
	check(feedback.numbers.is_empty(),"Expired floating hit/XP numbers are removed completely")
	game.rounds.running = true
	game.rounds.defeat()
	await press("personnel")
	await press("pause")
	check(paused and game.hud.overlay=="defeat","Personal inspection after defeat cannot resume a finished game")
	paused = false
	var cleaned: bool = await load("res://tests/scene_cleanup.gd").free_scene(game,self)
	check(cleaned,"UI fixture releases scene and real audio playbacks cleanly")
	print("PERSONAL UI: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
