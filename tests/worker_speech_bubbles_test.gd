extends SceneTree
const Bubbles := preload("res://scripts/worker_speech_bubbles.gd")
const Voice := preload("res://scripts/voice_chat.gd")
class TestNetwork extends Node:
	signal chat_received(row: Dictionary)
	var _generation := 1
	var active := true
	var peer_connected := true
	var is_host := true
	var _authenticated := true
	var local_player_id := 2
	var state := "playing"
	var blocked: Dictionary = {}
	func deliver(row: Dictionary) -> void: chat_received.emit(row)
	func next_generation() -> void: _generation += 1
	func authenticated() -> bool: return _authenticated
	func is_player_blocked(seat: int) -> bool: return blocked.has(seat)
class TestHud extends Node:
	var overlay := ""
	var canvas := Control.new()
class TestPlayer extends Node2D:
	var player_id := 1
	var character_id := "mara"
class TestDialogue extends Node:
	var active: Dictionary = {}
class TestGame extends Node2D:
	var started := true
	var network: Node
	var hud: Node
	var voice: Node
	var dialogue: Node
	var players: Array = []
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func row(seat: int, text: String) -> Dictionary:
	return {"id":1,"player_id":seat,"name":"Crew","text":text,"preset":"","time":0.0}

func output_pixels_per_unit(bubbles: Node) -> float:
	# Independent window/viewport dimensions catch omitted or doubled stretch.
	# The runtime computes this through transforms instead of these dimensions.
	return float(root.size.x)/root.get_visible_rect().size.x*bubbles.canvas.scale.x

func check_layout(bubbles: Node, game: Node, label: String) -> void:
	var layout: Array[Dictionary] = bubbles.bubble_layout()
	var screen: Vector2 = root.get_visible_rect().size / game.hud.canvas.scale.x
	var visible := Rect2(Vector2(8,72),screen-Vector2(16,144))
	check(layout.size()==4,label+" keeps all four public speakers")
	for index in layout.size():
		var bubble: Dictionary = layout[index]
		check(visible.encloses(bubble.rect),label+" bubble stays inside the readable viewport: "+str(bubble.seat))
		check(bubble.rows.size()<=Bubbles.MAX_ROWS and bubble.rect.size.x<=ceilf(bubble.text_width+bubble.padding.x*2),label+" long word stays within three lines and a bounded width")
		check(bubble.font_size>=Bubbles.FONT_SIZE,label+" uses the larger comic lettering")
		check(bubble.font_size*output_pixels_per_unit(bubbles)>=Bubbles.MIN_FONT_PIXELS-.01,label+" lettering retains its minimum output pixel size")
		check(bubble.font_size==maxi(Bubbles.FONT_SIZE,ceili(Bubbles.MIN_FONT_PIXELS/output_pixels_per_unit(bubbles))),label+" window stretch is compensated exactly once")
		var font_size: int = bubble.font_size
		check(bubble.line_height>=UiArt.FONT.get_height(font_size),label+" consecutive text rows leave room for actual glyphs")
		for line_index in bubble.rows.size():
			var text_line: String = bubble.rows[line_index]
			var line_width := UiArt.FONT.get_string_size(text_line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
			check(line_width<=bubble.text_width,label+" each visible line fits its bubble")
			var glyphs := Rect2(Vector2(bubble.padding.x,bubble.baseline+line_index*bubble.line_height-UiArt.FONT.get_ascent(font_size)),Vector2(line_width,UiArt.FONT.get_ascent(font_size)+UiArt.FONT.get_descent(font_size)))
			check(Rect2(Vector2.ZERO,bubble.rect.size).encloses(glyphs),label+" actual first/last line glyphs stay inside the bubble")
		var player: Node2D = game.players[int(bubble.seat)-1]
		var actor_tip: Vector2 = (player.get_global_transform_with_canvas()*Vector2(0,-68))/game.hud.canvas.scale.x
		check(bubble.tip==actor_tip.round(),label+" connector retains its own transformed actor")
		for previous in index:
			check(not layout[previous].rect.grow(2).intersects(bubble.rect.grow(2)),label+" crew lettering remains separate")

func _run() -> void:
	root.size = Vector2i(1440, 900)
	var game := TestGame.new()
	root.add_child(game)
	game.network = TestNetwork.new()
	game.add_child(game.network)
	game.hud = TestHud.new()
	game.add_child(game.hud)
	game.voice = Voice.new()
	game.voice.game = game
	game.voice.enabled = true
	game.voice.speaking = true
	game.network.is_host = false
	game.network._authenticated = false
	check(game.voice.speaking_players().is_empty(), "unauthenticated guest has no local or remote speech status")
	game.network._authenticated = true
	check(game.voice.speaking_players()==[2], "authenticated guest retains only its unmuted local status")
	game.network.peer_connected = false
	check(game.voice.speaking_players().is_empty(), "disconnected room has no speech status")
	game.network.peer_connected = true
	game.network.is_host = true
	game.voice.speaking = true
	game.voice._primary_sender = 3
	game.voice._clock = 1.0
	game.voice._last_received = 0.95
	game.voice._receive_peak = 0.1
	check(game.voice.speaking_players() == [2,3], "voice points to local and authenticated remote seat")
	game.voice.set_sender_muted(3, true)
	check(game.voice.speaking_players() == [2], "muted sender has no speech indicator")
	game.voice.enabled = false
	check(game.voice.speaking_players().is_empty(), "disabled voice has no indicator")
	game.voice.enabled = true
	for seat in 4:
		var player := TestPlayer.new()
		player.player_id = seat + 1
		player.position = Vector2(350 + seat * 190, 430)
		game.add_child(player)
		game.players.append(player)
	var bubbles := Bubbles.new()
	bubbles.game = game
	game.add_child(bubbles)
	bubbles._bind_network()
	check(bubbles.bubble_layout().size() == 1 and bubbles.bubble_layout()[0].seat == 2, "microphone bubble appears on speaking player only")
	check(bubbles.show_chat(row(1, "Munition liegt im Lager!")), "delivered public chat accepted")
	check(bubbles.bubble_layout().size() == 2, "voice and public text coexist")
	check(bubbles.bubble_layout()[0].rows[0] == "Munition liegt im Lager!", "chat text is plain and attributed")
	LocaleText.set_locale("en",false)
	bubbles.show_chat(row(1,"Danke!"))
	check(bubbles.bubble_layout()[0].rows==["Danke!"], "free German player text remains literal in the English game")
	check(UiArt.wrap_plain_text("Danke!",Bubbles.TEXT_WIDTH,Bubbles.FONT_SIZE)==["Danke!"] and UiArt.wrap_text("Danke!",Bubbles.TEXT_WIDTH,Bubbles.FONT_SIZE)==["Thank you!"], "literal helper leaves existing localized UI behavior intact")
	var preset_row := row(1,"")
	preset_row.preset = "thanks"
	check(bubbles.show_chat(preset_row) and bubbles.bubble_layout()[0].rows==["Thank you!"], "intentional quick-chat preset is localized once")
	var preset_deadline: float = bubbles._messages[1].until
	LocaleText.set_locale("de",false)
	check(bubbles.bubble_layout()[0].rows==["Danke!"] and bubbles._messages[1].until==preset_deadline, "visible quick-chat tracks a language switch without extending its lifetime")
	LocaleText.set_locale("en",false)
	bubbles.show_chat(row(1,"Danke!"))
	LocaleText.set_locale("de",false)
	check(bubbles.bubble_layout()[0].rows==["Danke!"], "free player text remains unchanged through a language switch")
	game.network.blocked[1] = true
	check(bubbles.bubble_layout().all(func(entry): return entry.seat!=1) and not bubbles._messages.has(1), "blocking immediately removes previously delivered public text")
	check(not bubbles.show_chat(row(1,"Danke!")), "blocked public text cannot enter the projection cache")
	game.dialogue = TestDialogue.new()
	game.add_child(game.dialogue)
	game.dialogue.active = {"speaker_id":"mara","anchor_player_id":1,"text":"Auftrag.","ending":false}
	check(bubbles.bubble_layout()[0].seat==1 and bubbles.bubble_layout()[0].rows==["Auftrag."], "blocking public chat preserves independently authored story dialogue")
	game.dialogue.active.clear()
	game.network.blocked.clear()
	check(bubbles.bubble_layout().all(func(entry): return entry.seat!=1) and not bubbles._messages.has(1), "unblocking does not resurrect a retired public message")
	bubbles.show_chat(row(1,"Munition liegt im Lager!"))
	game.hud.overlay = "options"
	game.network.blocked[1] = true
	bubbles._process(0)
	check(not bubbles._messages.has(1), "always-process retires blocked chat while a modal hides the speech layer")
	game.network.blocked.clear()
	game.hud.overlay = ""
	check(bubbles.bubble_layout().all(func(entry): return entry.seat!=1), "unblocking under Options cannot restore old chat after the modal closes")
	bubbles.show_chat(row(1,"Munition liegt im Lager!"))
	var private_row := row(3, "Private message")
	private_row.merge({"private":true,"recipient_id":1,"sender_key":"a".repeat(48),"recipient_key":"b".repeat(48)})
	check(not bubbles.show_chat(private_row), "private chat is never projected into world")
	check(not bubbles.show_chat(row(1,"bad\ncontrol")), "unvalidated text is rejected")
	game.network.deliver(row(4, "Verteidigt den Reifenwechsel, ich übernehme die Reparatur!"))
	check(bubbles.bubble_layout().size() == 3, "session signal displays actual delivered chat")
	game.players[3].position = game.players[0].position
	var layout := bubbles.bubble_layout()
	check(not layout[0].rect.intersects(layout[2].rect), "adjacent crew bubbles separate their text")
	bubbles.show_chat(row(1,"W".repeat(240)))
	check(bubbles.bubble_layout()[0].rows.size() <= 3, "long messages stay bounded with full chat retained elsewhere")
	game.hud.overlay = "options"
	check(bubbles.bubble_layout().is_empty(), "modal settings remain clear")
	game.hud.overlay = ""
	game.hud.canvas.scale = Vector2.ONE * 0.75
	var scaled := bubbles.bubble_layout()
	check(scaled[0].rect.size.x<=ceilf(scaled[0].text_width+scaled[0].padding.x*2) and bubbles.canvas.scale.x==.75 and scaled[0].font_size*output_pixels_per_unit(bubbles)>=Bubbles.MIN_FONT_PIXELS-.01, "comic lettering retains readable output while following UI scale independently of camera zoom")
	game.hud.canvas.scale = Vector2.ONE
	# Four speakers can share the same world point while crossing ladders or doors.
	# Check the actual submitted rectangles, including top/bottom/side gutters.
	for dimensions: Vector2i in [Vector2i(960,600),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size = dimensions
		await process_frame
		for ui_scale: float in [0.65,1.0,1.4]:
			game.hud.canvas.scale = Vector2.ONE*ui_scale
			var screen := root.get_visible_rect().size/ui_scale
			for point: Vector2 in [Vector2(12,76),Vector2(screen.x*.5,76),Vector2(screen.x-12,76),Vector2(12,screen.y-76),Vector2(screen.x*.5,screen.y-76),Vector2(screen.x-12,screen.y-76)]:
				for player: Node2D in game.players:
					player.position = game.get_global_transform_with_canvas().affine_inverse()*(point*ui_scale)+Vector2(0,68)
					bubbles.show_chat(row(player.player_id,"W".repeat(240)))
				check_layout(bubbles,game,"viewport %s / scale %.2f / tip %s"%[dimensions,ui_scale,point])
	check(str(bubbles._messages[1].text)=="W".repeat(240), "truncated display leaves the delivered public message intact")
	root.size = Vector2i(1440,900)
	game.hud.canvas.scale = Vector2.ONE
	game.players[0].position = Vector2(-1000,-1000)
	check(bubbles.bubble_layout().all(func(entry): return entry.seat != 1), "offscreen speaker has no floating orphan bubble")
	game.network.next_generation()
	bubbles._bind_network()
	check(bubbles._messages.is_empty(), "new session clears old chat bubbles")
	game.voice.set_sender_muted(3,false)
	game.voice._last_received = game.voice._clock
	game.voice._receive_peak = .1
	check(game.voice.speaking_players()==[2,3], "unmuted active sender returns with a fresh status")
	game.voice.retire_sender(3)
	check(game.voice.speaking_players()==[2], "departed remote sender retires without hiding the local speaker")
	game.voice._last_received = game.voice._clock
	game.voice._receive_peak = .1
	game.voice.set_remote_muted(true)
	check(game.voice.speaking_players()==[2], "all-remote mute keeps only the local speaker")
	game.voice.set_remote_muted(false)
	check(game.voice.speaking_players()==[2], "unmuting does not resurrect the previous remote receive peak")
	bubbles.show_chat(row(1,"Danke!"))
	bubbles._process(10.0)
	check(bubbles._messages.is_empty(), "expired chat is retired")
	game.started = false
	check(bubbles.bubble_layout().is_empty(), "main menu never shows world speech")
	game.voice.free()
	game.hud.canvas.free()
	game.queue_free()
	await process_frame
	var world: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await process_frame
	var original_bubbles: Node = world.speech_bubbles
	world.start_scenario(2,{"environment":"sector07","build_type":"bastion","position":"left"})
	await process_frame
	check(is_instance_valid(original_bubbles) and original_bubbles == world.speech_bubbles and original_bubbles.is_inside_tree(), "speech layer survives actual menu-to-selected-world transition")
	check(world.speech_bubbles.show_chat(row(1,"Danke!")), "actual selected world accepts delivered crew speech")
	var previous_world_id: int = world.get_instance_id()
	check(world.restart(), "actual offline restart is accepted")
	var deadline := Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=previous_world_id and current_scene.started: break
	var restarted: Node = current_scene
	check(is_instance_valid(restarted) and restarted.get_instance_id()!=previous_world_id and restarted.started, "restart creates the real replacement mission")
	if is_instance_valid(restarted) and restarted.get_instance_id()!=previous_world_id:
		check(is_instance_valid(restarted.speech_bubbles) and restarted.speech_bubbles.is_inside_tree() and restarted.speech_bubbles._messages.is_empty(), "replacement mission owns a clean speech layer without old chat")
		check(not is_instance_valid(original_bubbles), "restart releases the previous mission speech layer")
		await preload("res://tests/scene_cleanup.gd").free_scene(restarted,self)
	elif is_instance_valid(world):
		await preload("res://tests/scene_cleanup.gd").free_scene(world,self)
	print("WORKER_SPEECH_BUBBLES ", checks-failures, "/", checks)
	quit(1 if failures else 0)
