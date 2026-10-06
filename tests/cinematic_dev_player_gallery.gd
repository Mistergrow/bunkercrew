extends SceneTree
## Actual Options entry rendered at two sizes in DE/EN; controlled preview times.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUT := "res://artifacts/cinematic-dev-player-20261004/gallery/"
var game: Node
var view: SubViewport
var player: CanvasLayer
var checks:=0
var failures:=0
var captures: Array[Dictionary]=[]

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)

func frames(count: int=3) -> void:
	for _unused in count: await process_frame

func _run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2); return
	var original_locale:=LocaleText.current_locale()
	var master_muted:=AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	view=SubViewport.new()
	view.size=Vector2i(1440,900)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames()
	game.hud._toggle_audio()
	await frames()
	game.hud.options_panel.select_tab(3)
	await frames()
	game.hud.options_panel.cinematic_player_button.pressed.emit()
	await frames()
	player=game.hud.options_panel.cinematic_player
	player.set_process(false)
	player.set_muted(true)
	for locale: String in ["de","en"]:
		LocaleText.set_locale(locale,false)
		for resolution: Vector2i in [Vector2i(960,600),Vector2i(1440,900)]:
			view.size=resolution
			await frames()
			for definition: Dictionary in [{"id":"signal","character":"branko","environment":"abandoned_harbor","time":3.8},{"id":"storm","character":"mara","environment":"mountain_pass","time":5.7},{"id":"supply","character":"oskar","environment":"overgrown_steelworks","time":3.0},{"id":"air_raid","character":"rika","environment":"storm_dam","time":3.4}]:
				player.select_scene(str(definition.id))
				player.character_id=str(definition.character)
				player.environment_id=str(definition.environment)
				player._refresh_context(true)
				player._refresh_locale()
				player.seek(float(definition.time))
				await frames()
				await RenderingServer.frame_post_draw
				var rect:=Rect2(Vector2.ZERO,Vector2(resolution))
				var controls: Array[Control]=[player.scene_choice,player.character_choice,player.environment_choice,player.speed_choice,player.timeline,player.play_button,player.restart_button,player.close_button,player.mute_button,player.subtitle_button,player.reduced_button,player.preview_container]
				check(controls.all(func(control):return rect.encloses(control.get_global_rect()) and control.is_visible_in_tree()),"Every real control fits "+locale+str(resolution)+str(definition.id))
				check(player._labels.all(func(label):return label.get_line_count()*label.get_line_height()<=label.size.y+.5),"Localized labels fit without truncation "+locale+str(resolution)+str(definition.id))
				check(player.preview_world.subtitle_text()==str(player.context.dialogue.text) and not player.playing and not player.voice.playing,"Captured actual selected subtitle and silent exact previewtime")
				var path:="%s-%dx%d-%s.png"%[locale,resolution.x,resolution.y,definition.id]
				var picture:=view.get_texture().get_image()
				check(picture.get_size()==resolution and picture.save_png(OUT+path)==OK,"Native capture saved "+path)
				captures.append({"file":path,"locale":locale,"resolution":[resolution.x,resolution.y],"scene":definition.id,"character":definition.character,"environment":definition.environment,"elapsed":definition.time,"subtitle":str(player.context.dialogue.text)})
	# A rendered pointer reaches the actual timeline: no native signal emission.
	var target: Vector2=player.timeline.get_global_rect().get_center()
	var pointer:=InputEventMouseButton.new()
	pointer.button_index=MOUSE_BUTTON_LEFT
	pointer.pressed=true
	pointer.position=target
	view.push_input(pointer,true)
	pointer=pointer.duplicate()
	pointer.pressed=false
	view.push_input(pointer,true)
	await frames()
	check(not player.playing and player.elapsed>3.6 and player.elapsed<4.4,"Real pointer hit scrubs into half of eight-second air sequence")
	player.close()
	await frames()
	paused=false
	check(await Cleanup.free_scene(game,self),"Actual game, preview and source audio free after rendered gallery")
	view.queue_free()
	await frames()
	LocaleText.set_locale(original_locale,false)
	AudioServer.set_bus_mute(0,master_muted)
	var result:={"checks":checks,"failures":failures,"captures":captures,"fixture":"Actual menu Options Takt entry in isolated world, no match started. Muted preview and deliberately exact scene timestamps; four existing production scenes, two languages, native960x600/1440x900. Root generated storm scorched-tree visible at5.7s. Actual rendered mouse timeline hit; no profile/network changes.","renderer":RenderingServer.get_current_rendering_method()}
	FileAccess.open(OUT+"gallery.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	var html:="<!doctype html><html lang='de'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>Bunkercrew · Sequenz-Studio</title><style>body{margin:24px;background:#10191b;color:#dedccc;font:16px system-ui}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(430px,1fr));gap:18px}figure{margin:0}img{width:100%;display:block}figcaption{padding:8px 0;color:#adb39f}</style><h1>Bunkercrew · Sequenz-Studio</h1><p>Vier vorhandene Szenen, DE/EN, 960×600 und 1440×900. Tatsächlicher Options-Einstieg; Zeitpunkte für die Bilder bewusst angehalten.</p><main>"
	for entry: Dictionary in captures:
		html+="<figure><a href='%s'><img loading='lazy' src='%s' alt='%s'></a><figcaption>%s · %s · %d×%d · %.2fs</figcaption></figure>"%[entry.file,entry.file,entry.scene,entry.scene,entry.locale.to_upper(),entry.resolution[0],entry.resolution[1],entry.elapsed]
	html+="</main></html>"
	FileAccess.open(OUT+"index.html",FileAccess.WRITE).store_string(html)
	print("CINEMATIC PLAYER GALLERY: %d/%d passed; %d captures"%[checks-failures,checks,captures.size()])
	quit(1 if failures else 0)
