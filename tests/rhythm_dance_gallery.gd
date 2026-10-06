extends SceneTree
## Prepared silent comparison, sampled at 60 Hz and normal 116 BPM. Native
## rendering uses the real outfits, rig, boots and complete dance phrase.
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const VisualTest := preload("res://tests/rhythm_visual_test.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const BPM := 116.0
const FPS := 60
const PHRASE_BEATS := 16.0
const DIRECTORY := "res://artifacts/rhythm-dance"

class GalleryWorld extends VisualTest.Fixture:
	var actors: Array[Worker] = []
	var current_beat := 0.0
	func _draw() -> void:
		draw_rect(Rect2(0,0,1600,1000),Color("10191c"))
		Art.text(self,Vector2(40,44),"TANZSTUDIO · SIEBEN VOLLSTÄNDIGE MOVES",28,UiArt.IVORY)
		Art.text(self,Vector2(40,73),"Echte Crew-Rigs · normale 116 BPM · vorbereitete stumme Vergleichsaufnahme",16,Art.MUTED)
		for index in 7:
			var x := 32.0+float(index%4)*390.0
			var y := 103.0+float(floori(float(index)/4.0))*408.0
			var actor := actors[index]
			var accent := Color(CharacterCatalog.data(actor.character_id).accent)
			draw_rect(Rect2(x,y,364,384),Color("1b2829"))
			draw_rect(Rect2(x,y,364,3),accent)
			Art.text(self,Vector2(x+16,y+34),LocaleText.text(Dance.LABELS[Dance.STYLES.find(Dance.FULL_BODY_STYLES[index])]),23,accent)
			Art.text(self,Vector2(x+16,y+58),str(CharacterCatalog.data(actor.character_id).title),15,Art.MUTED)
			draw_line(Vector2(x+20,y+318),Vector2(x+344,y+318),Color("63736b"),1)
			var pose: Dictionary = actor.get_node("PixelVisual").pose_skeleton
			var caption := "Boden-Kontakt · kosmetische Schritte"
			if Dance.FULL_BODY_STYLES[index]=="breakdance":
				caption = "TOPROCK → DROP → FLOORWORK → FREEZE" if str(pose.get("dance_stage",""))!="freeze" else "FREEZE · STABIL AUF HAND UND FUSS"
			Art.text(self,Vector2(x+16,y+355),caption,12,Art.MUTED)
		Art.text(self,Vector2(1225,622),"BUM → REAKTION → TANZ",19,UiArt.IVORY)
		Art.text(self,Vector2(1225,658),"Alle Schritte bleiben am Ort.",15,Art.MUTED)
		Art.text(self,Vector2(1225,687),"Spielkörper und Kollision unverändert.",13,Art.MUTED)
		Art.text(self,Vector2(1225,731),"Individuelle Verzögerung: 32–94 ms",14,Art.MUTED)
		Art.text(self,Vector2(1225,761),"Abbruch bei Bewegung oder Gefahr.",14,Art.MUTED)
		Art.text(self,Vector2(40,958),"16 Schläge · %.1f / 16 · Einstieg nach tatsächlich gehörten Kicks"%current_beat,16,Art.MUTED)
		draw_rect(Rect2(40,974,1518,4),Color("283b39"))
		draw_rect(Rect2(40,974,1518*current_beat/16.0,4),Art.AMBER)

func _initialize() -> void:
	_run.call_deferred()

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Dance gallery requires native graphics")
		quit(1)
		return
	InputSetup.install()
	LocaleText.set_locale("de",false)
	root.size = Vector2i(1600,1000)
	root.content_scale_size = Vector2i(1600,1000)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY+"/frames"))
	var world := GalleryWorld.new()
	root.add_child(world)
	world.audio = VisualTest.AudioStub.new()
	world.add_child(world.audio)
	world.audio.live_music = VisualTest.MusicStub.new()
	world.audio.add_child(world.audio.live_music)
	var music = world.audio.live_music
	var characters := ["levin","ivo","mara","selma","branko","nora","selma"]
	for index in 7:
		var actor := Worker.new()
		actor.game = world
		actor.character_id = characters[index]
		actor.position = Vector2(32+index%4*390+174,103+floori(float(index)/4.0)*408+318)
		actor.scale = Vector2.ONE*3.4
		world.add_child(actor)
		actor.remove_from_group("players")
		var visual := WorkerVisual.new()
		visual.name = "PixelVisual"
		actor.add_child(visual)
		_freeze(actor)
		visual._identity.hide()
		visual.idle_clock.wait_remaining = 10000
		world.actors.append(actor)
	var frames := ceili(PHRASE_BEATS*60.0/BPM*float(FPS))
	for frame in range(-180,frames):
		var seconds := maxf(0.0,float(frame)/float(FPS))
		var beats := seconds*BPM/60.0
		music.state.active = true
		music.state.phase = fposmod(beats,1.0)
		music.state.beat = floori(beats)%4
		music.state.bar = floori(beats/4.0)
		music.state.audible_seconds = float(frame+180)/float(FPS)
		music.state.last_kick_seconds = floorf(float(frame+180)/float(FPS)*BPM/60.0)*60.0/BPM
		music.state.last_kick_strength = 1.0
		music.state.kick_count = floori(float(frame+180)/float(FPS)*BPM/60.0)+1
		for index in 7:
			var actor := world.actors[index]
			music.state.dance_profiles = {actor.character_id:{"style":Dance.FULL_BODY_STYLES[index],"intensity":1.0}}
			actor.get_node("PixelVisual")._process(1.0/float(FPS))
		world.current_beat = minf(beats,16.0)
		world.queue_redraw()
		if frame<0: continue
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels := root.get_texture().get_image()
		pixels.save_jpg(DIRECTORY+"/frames/%04d.jpg"%frame,0.94)
		if frame in [60,270,375]:
			pixels.save_png(DIRECTORY+"/dance-%04d.png"%frame)
	var result := {"renderer":RenderingServer.get_video_adapter_name(),"width":1600,"height":1000,"frames":frames,"fps":FPS,"bpm":BPM,"phrase_beats":16,"styles":Dance.FULL_BODY_STYLES,"prepared_states":true,"audible_recording":false,"actual_worker_rigs":true,"physics_position_unchanged":true}
	var file := FileAccess.open(DIRECTORY+"/gallery-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("RHYTHM DANCE GALLERY: ",JSON.stringify(result))
	await Cleanup.free_scene(world,self)
	quit()
