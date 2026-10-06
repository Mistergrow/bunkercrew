extends Control
## Open settings navigation over the existing world, with native input controls.
const L := preload("res://scripts/locale_text.gd")
const TABS := ["Bild","Kamera","Ton","Takt","Sprache"]
var game
var hud
var tab := 0
var tab_buttons: Array[Button] = []
var pages: Array[Control] = []
var camera_mode: OptionButton
var zoom_slider: HSlider
var display_mode: OptionButton
var vsync: CheckButton
var effects: CheckButton
var violence_choice: OptionButton
var renderer_choice: OptionButton
var renderer_restart: Button
var standalone_button: Button
var live_music_check: CheckButton
var music_style_choice: OptionButton
var rhythm_reduced_check: CheckButton
var dance_gain_slider: HSlider
var music_lab_button: Button
var cinematic_player_button: Button
var calibration_button: Button
var back_button: Button
var microphone_button: Button
var support_button: Button
var release_button: Button
var release_panel: Control
var support_panel: Control
var calibration_panel: Control
var music_lab: CanvasLayer
var cinematic_player: CanvasLayer
var audio_sliders: Array[HSlider] = []
var decoration: Control
var _landscape: Dictionary = {}
var _syncing := false
var _modal_visibility: Dictionary = {}
var _modal_opener: Control
var _active_slider: HSlider
var _focus_signature := ""
var _presentation_values: Array = []

func _ready() -> void:
	name = "OptionsPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440,900)
	tab = clampi(hud.options_tab,0,4)
	if not game.started:
		var environment: String = str(hud._main_menu_navigation.get("environment",hud.scenario_options.get("environment","sector07")))
		_landscape = SocialUiArt.create_landscape(self,game,hud,environment)
	decoration = Control.new()
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.draw.connect(_draw_foreground)
	add_child(decoration)
	for index in TABS.size():
		var button := _button(TABS[index],Rect2(80,224+index*64,290,50),func(): select_tab(index))
		SocialUiArt.button(button,24,"",0)
		button.name = "Category%d" % index
		button.toggle_mode = true
		button.gui_input.connect(_category_input.bind(index))
		tab_buttons.append(button)
		var page := Control.new()
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.size = size
		add_child(page)
		pages.append(page)
	_build_display()
	_build_camera()
	_build_audio()
	_build_rhythm()
	_build_language()
	support_button = _button("Fehlerbericht",Rect2(80,592,300,30),_open_support_report)
	SocialUiArt.button(support_button,17,"",0)
	release_button = _button("Änderungen",Rect2(80,628,300,30),_open_release_notes)
	SocialUiArt.button(release_button,17,"",0)
	microphone_button = _button("Mikrofon & Sprachchat",Rect2(80,663,300,46),hud._open_microphone)
	SocialUiArt.button(microphone_button,17,"voice",0)
	back_button = _button("Zurück · Esc / F4",Rect2(80,746,300,48),hud._close_audio)
	SocialUiArt.button(back_button,20,"back",0)
	select_tab(tab)
	refresh_locale()
	tab_buttons[tab].grab_focus.call_deferred()

func _button(title: String,rect: Rect2,callback: Callable,parent: Node=self) -> Button:
	var button := Button.new()
	button.text = title
	button.position = rect.position
	button.size = rect.size
	SocialUiArt.button(button,18,"",12)
	button.pressed.connect(callback)
	parent.add_child(button)
	hud.buttons.append(button)
	return button

func _choice(rect: Rect2,values: Array[String],parent: Node) -> OptionButton:
	var choice := OptionButton.new()
	choice.position = rect.position
	choice.size = rect.size
	SocialUiArt.button(choice,17,"",12)
	SocialUiArt.popup(choice.get_popup())
	for value in values: choice.add_item(L.text(value))
	parent.add_child(choice)
	return choice

func _check(title: String,at: Vector2,callback: Callable,parent: Node) -> CheckButton:
	var control := CheckButton.new()
	control.position = at
	control.size = Vector2(360,44)
	control.set_meta("setting_title",title)
	control.tooltip_text = L.text(title)
	SocialUiArt.button(control,17,"",12)
	for icon_name in ["checked","checked_disabled","unchecked","unchecked_disabled","checked_mirrored","unchecked_mirrored"]:
		control.add_theme_icon_override(icon_name,UiArt.switch_icon(icon_name.begins_with("checked")))
	control.toggled.connect(callback)
	parent.add_child(control)
	return control

func _slider(rect: Rect2,value: float,callback: Callable,parent: Node,min_value: float=0,max_value: float=1) -> HSlider:
	var slider := HSlider.new()
	slider.position = rect.position
	slider.size = rect.size
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = .01
	slider.value = value
	slider.focus_mode = Control.FOCUS_ALL
	slider.add_theme_stylebox_override("slider",UiArt.slider_track())
	slider.add_theme_stylebox_override("grabber_area",UiArt.slider_track(true))
	slider.add_theme_stylebox_override("grabber_area_highlight",UiArt.slider_track(true))
	for style in ["grabber","grabber_highlight","grabber_disabled"]: slider.add_theme_icon_override(style,UiArt.slider_handle())
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_width_bottom = 1
	focus.border_color = UiArt.AMBER
	slider.add_theme_stylebox_override("focus",focus)
	slider.drag_started.connect(func(): _active_slider=slider)
	slider.drag_ended.connect(func(_changed: bool):
		if _active_slider==slider: _active_slider=null)
	slider.value_changed.connect(callback)
	parent.add_child(slider)
	return slider

func _build_display() -> void:
	display_mode = _choice(Rect2(1000,242,360,44),["Fenster","Vollbild"],pages[0])
	display_mode.item_selected.connect(func(index: int):
		if _syncing: return
		var full := get_window().mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN]
		if full!=(index==1): hud.display_settings.toggle_fullscreen())
	standalone_button = _button("Eigenes Fenster",Rect2(1000,290,360,38),func(): hud.display_settings.open_standalone(),pages[0])
	standalone_button.visible = hud.display_settings.is_embedded()
	vsync = _check("Vertikale Synchronisation",Vector2(1000,344),func(value: bool):
		if not _syncing:
			if hud.display_settings.has_method("set_vsync"): hud.display_settings.set_vsync(value)
			elif DisplayServer.get_name()!="headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED),pages[0])
	effects = _check("Wettereffekte reduzieren",Vector2(1000,434),func(value: bool):
		if not _syncing: game.weather.set_reduced_effects(value),pages[0])
	violence_choice = _choice(Rect2(1000,524,360,44),["Aus","Blut","Blut + Abtrennungen"],pages[0])
	violence_choice.item_selected.connect(func(index: int):
		if not _syncing and _gore()!=null: _gore().set_level(index))
	renderer_choice = _choice(Rect2(1000,614,360,44),["Kompatibilität · OpenGL","Vulkan · Mobile"],pages[0])
	if hud.display_settings.has_method("renderer_status"):
		var status: Dictionary = hud.display_settings.renderer_status()
		renderer_choice.select(1 if status.get("current","")=="vulkan" else 0)
	renderer_restart = _button("Neu starten",Rect2(1000,673,360,40),func():
		if hud.display_settings.has_method("restart_with_renderer"):
			hud.display_settings.restart_with_renderer("vulkan" if renderer_choice.selected==1 else "compatibility"),pages[0])

func _build_camera() -> void:
	camera_mode = _choice(Rect2(1000,242,360,44),["Spielern folgen","Bunkerübersicht"],pages[1])
	camera_mode.item_selected.connect(func(index: int):
		if not _syncing and game.has_method("set_camera_mode"): game.set_camera_mode("follow" if index==0 else "overview"))
	zoom_slider = _slider(Rect2(480,410,880,36),1.0,func(value: float):
		if not _syncing and game.has_method("set_camera_zoom"): game.set_camera_zoom(value),pages[1],.5,2.0)
	_button("Kamera zurücksetzen",Rect2(1000,536,360,44),func():
		if game.has_method("reset_camera_view"): game.reset_camera_view(),pages[1])

func _build_audio() -> void:
	for index in 3:
		var value: float = [game.audio.music_volume,game.audio.sfx_volume,game.audio.voice_volume][index]
		var callback: Callable = [game.audio.set_music_volume,game.audio.set_sfx_volume,game.audio.set_voice_volume][index]
		var slider := _slider(Rect2(480,310+index*130,880,36),value,callback,pages[2])
		audio_sliders.append(slider)
		hud.sliders.append(slider)

func _build_rhythm() -> void:
	live_music_check = _check("Live-Musik pro Schauplatz",Vector2(1000,242),func(value: bool):
		if not _syncing: game.audio.set_live_music_enabled(value),pages[3])
	var genres := preload("res://scripts/music_genre_catalog.gd")
	var labels: Array[String] = []
	for selection in genres.SELECTIONS: labels.append(genres.selection_label(selection))
	music_style_choice = _choice(Rect2(1000,328,360,44),labels,pages[3])
	music_style_choice.item_selected.connect(func(index: int):
		if not _syncing: game.audio.set_music_style(genres.SELECTIONS[index]))
	rhythm_reduced_check = _check("Taktbewegungen reduzieren",Vector2(1000,414),func(value: bool):
		if not _syncing: game.audio.set_rhythm_motion_reduced(value),pages[3])
	dance_gain_slider = _slider(Rect2(480,531,880,30),game.audio.dance_intensity,func(value: float):
		if not _syncing: game.audio.set_dance_configuration(value,preload("res://scripts/worker_dance_catalog.gd").normalized_profiles(game.audio.dance_profiles)),pages[3],0.0,1.5)
	calibration_button = _button("Abstimmen",Rect2(1000,592,360,40),_open_calibration,pages[3])
	music_lab_button = _button("Musik-Labor",Rect2(480,681,240,42),_open_music_lab,pages[3])
	music_lab_button.tooltip_text = L.text("Musik-Labor im Hauptmenü öffnen.")
	cinematic_player_button = _button("Sequenz-Studio",Rect2(742,681,240,42),_open_cinematic_player,pages[3])
	cinematic_player_button.tooltip_text = L.text("Zwischensequenzen im Hauptmenü ansehen und prüfen.")
	_button("Ausgleich zurücksetzen",Rect2(1000,681,360,42),func(): game.audio.set_music_calibration(0.0),pages[3])

func _build_language() -> void:
	for index in 2:
		var code: String = ["de","en"][index]
		var button := _button("Deutsch" if index==0 else "English",Rect2(480,260+index*78,880,58),func():
			L.set_locale(code)
			refresh_locale(),pages[4])
		SocialUiArt.button(button,24,"",12)
		button.toggle_mode = true
		button.tooltip_text = "Deutsch" if index==0 else "English"
		hud.language_buttons.append(button)

func select_tab(index: int) -> void:
	var previous_focus := get_viewport().gui_get_focus_owner()
	var page_had_focus := false
	for page in pages:
		if is_instance_valid(previous_focus) and page.is_ancestor_of(previous_focus): page_had_focus=true
	tab = clampi(index,0,4)
	hud.options_tab = tab
	for current in pages.size():
		pages[current].visible = current==tab
		tab_buttons[current].set_pressed_no_signal(current==tab)
	if page_had_focus and is_instance_valid(previous_focus) and not previous_focus.is_visible_in_tree():
		tab_buttons[tab].grab_focus.call_deferred()
	_focus_signature = ""
	_wire_focus()
	_redraw()

func _category_input(event: InputEvent,index: int) -> void:
	if has_modal_subpanel(): return
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		var next := index+(-1 if event.is_action_pressed("ui_up") else 1)
		if next<0:
			back_button.grab_focus()
		elif next>=TABS.size():
			support_button.grab_focus()
		else:
			select_tab(next)
			tab_buttons[next].grab_focus()
		accept_event()
	elif event.is_action_pressed("ui_right"):
		select_tab(index)
		var controls := _visible_page_controls()
		if not controls.is_empty(): controls[0].grab_focus()
		accept_event()

func _visible_page_controls() -> Array[Control]:
	var result: Array[Control] = []
	if pages.is_empty() or has_modal_subpanel(): return result
	for child in pages[tab].get_children():
		if not child is Control or not child.is_visible_in_tree() or child.focus_mode==Control.FOCUS_NONE: continue
		if child is BaseButton and child.disabled: continue
		if child is Slider and not child.editable: continue
		result.append(child)
	result.sort_custom(func(a: Control,b: Control):
		return a.position.x<b.position.x if is_equal_approx(a.position.y,b.position.y) else a.position.y<b.position.y)
	return result

func _wire_focus() -> void:
	if not is_instance_valid(back_button) or has_modal_subpanel(): return
	var controls := _visible_page_controls()
	var active: Array[Control] = []
	active.append_array(tab_buttons)
	active.append_array(controls)
	active.append_array([support_button,release_button,microphone_button,back_button])
	var signature := str(tab)
	for control in active: signature+="/"+str(control.get_instance_id())
	if signature==_focus_signature: return
	_focus_signature=signature
	for index in active.size():
		var control := active[index]
		control.focus_next=control.get_path_to(active[(index+1)%active.size()])
		control.focus_previous=control.get_path_to(active[posmod(index-1,active.size())])
	for index in tab_buttons.size():
		var button := tab_buttons[index]
		button.focus_neighbor_top=button.get_path_to(tab_buttons[index-1] if index>0 else back_button)
		button.focus_neighbor_bottom=button.get_path_to(tab_buttons[index+1] if index<tab_buttons.size()-1 else support_button)
		button.focus_neighbor_left=NodePath(".")
		button.focus_neighbor_right=button.get_path_to(controls[0]) if not controls.is_empty() else NodePath(".")
	for index in controls.size():
		var control := controls[index]
		control.focus_neighbor_top=control.get_path_to(controls[index-1] if index>0 else tab_buttons[tab])
		control.focus_neighbor_bottom=control.get_path_to(controls[index+1] if index<controls.size()-1 else back_button)
		control.focus_neighbor_left=NodePath(".") if control is HSlider else control.get_path_to(tab_buttons[tab])
		control.focus_neighbor_right=NodePath(".")
	support_button.focus_neighbor_top=support_button.get_path_to(tab_buttons[4])
	support_button.focus_neighbor_bottom=support_button.get_path_to(release_button)
	release_button.focus_neighbor_top=release_button.get_path_to(support_button)
	release_button.focus_neighbor_bottom=release_button.get_path_to(microphone_button)
	microphone_button.focus_neighbor_top=microphone_button.get_path_to(release_button)
	microphone_button.focus_neighbor_bottom=microphone_button.get_path_to(back_button)
	back_button.focus_neighbor_top=back_button.get_path_to(microphone_button)
	back_button.focus_neighbor_bottom=back_button.get_path_to(tab_buttons[0])
	for button: Button in [support_button,release_button,microphone_button,back_button]:
		button.focus_neighbor_left=NodePath(".")
		button.focus_neighbor_right=button.get_path_to(controls[0]) if not controls.is_empty() else NodePath(".")
	var focus := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus) and is_ancestor_of(focus) and not focus in active:
		tab_buttons[tab].grab_focus.call_deferred()

func _process(_delta: float) -> void:
	_syncing = true
	SocialUiArt.layout_landscape(_landscape,hud)
	display_mode.select(1 if get_window().mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN] else 0)
	vsync.set_pressed_no_signal(DisplayServer.window_get_vsync_mode()!=DisplayServer.VSYNC_DISABLED if DisplayServer.get_name()!="headless" else true)
	effects.set_pressed_no_signal(game.weather.reduced_effects)
	violence_choice.disabled = _gore()==null
	if _gore()!=null: violence_choice.select(clampi(int(_gore().level),0,2))
	if game.has_method("camera_settings"):
		var settings: Dictionary = game.camera_settings()
		camera_mode.select(0 if settings.get("mode","follow")=="follow" else 1)
		zoom_slider.min_value=float(settings.get("min_zoom",.5))
		zoom_slider.max_value=float(settings.get("max_zoom",2.0))
		if _active_slider!=zoom_slider: zoom_slider.set_value_no_signal(float(settings.get("zoom",1.0)))
	for index in audio_sliders.size():
		if _active_slider!=audio_sliders[index]:
			audio_sliders[index].set_value_no_signal([game.audio.music_volume,game.audio.sfx_volume,game.audio.voice_volume][index])
	if hud.display_settings.has_method("renderer_status"):
		var status: Dictionary = hud.display_settings.renderer_status()
		var selected: String = "vulkan" if renderer_choice.selected==1 else "compatibility"
		renderer_restart.visible=selected!=str(status.get("current",""))
		renderer_restart.disabled=not bool(status.get("can_restart",false)) or hud.audio_return_overlay!="menu" or selected==str(status.get("current",""))
	else:
		renderer_restart.hide()
		renderer_restart.disabled=true
	standalone_button.disabled = not hud.display_settings.can_open_standalone()
	live_music_check.set_pressed_no_signal(game.audio.live_music_enabled)
	music_style_choice.select(preload("res://scripts/music_genre_catalog.gd").SELECTIONS.find(game.audio.music_style))
	music_style_choice.disabled=game.started
	rhythm_reduced_check.set_pressed_no_signal(game.audio.rhythm_motion_reduced)
	if _active_slider!=dance_gain_slider: dance_gain_slider.set_value_no_signal(game.audio.dance_intensity)
	music_lab_button.disabled=game.started
	cinematic_player_button.disabled=game.started
	for control: CheckButton in [vsync,effects,live_music_check,rhythm_reduced_check]:
		control.text=L.text("Ein" if control.button_pressed else "Aus")
	_syncing = false
	_wire_focus()
	# The landscape and native controls animate independently. Retain the
	# foreground's shaped text until one of its displayed values changes.
	var presentation: Array = [SocialUiArt.bounds(hud),zoom_slider.value,game.audio.music_volume,game.audio.sfx_volume,game.audio.voice_volume,dance_gain_slider.value,game.audio.music_calibration_seconds]
	if presentation!=_presentation_values:
		_presentation_values=presentation
		_redraw()

func refresh_locale() -> void:
	if is_instance_valid(support_panel): support_panel.refresh_locale()
	if is_instance_valid(release_panel): release_panel.refresh_locale()
	for index in 2:
		display_mode.set_item_text(index,L.text(["Fenster","Vollbild"][index]))
		camera_mode.set_item_text(index,L.text(["Spielern folgen","Bunkerübersicht"][index]))
		renderer_choice.set_item_text(index,L.text(["Kompatibilität · OpenGL","Vulkan · Mobile"][index]))
		hud.language_buttons[index].set_pressed_no_signal(L.current_locale()==["de","en"][index])
	for index in 3: violence_choice.set_item_text(index,L.text(["Aus","Blut","Blut + Abtrennungen"][index]))
	var genres := preload("res://scripts/music_genre_catalog.gd")
	for index in genres.SELECTIONS.size(): music_style_choice.set_item_text(index,L.text(genres.selection_label(genres.SELECTIONS[index])))
	for control: CheckButton in [vsync,effects,live_music_check,rhythm_reduced_check]: control.tooltip_text=L.text(str(control.get_meta("setting_title")))
	_redraw()

func _redraw() -> void:
	if is_instance_valid(decoration): decoration.queue_redraw()

func _draw_foreground() -> void:
	if has_modal_subpanel(): return
	var bounds: Rect2 = SocialUiArt.bounds(hud)
	decoration.draw_rect(bounds,Color(.01,.015,.018,.20))
	SocialUiArt.reading_shade(decoration,bounds,420,800)
	UiArt.text(decoration,Vector2(80,112),"Optionen",36,UiArt.IVORY,UiArt.TITLE_FONT)
	var button: Button = tab_buttons[tab]
	decoration.draw_line(Vector2(64,button.position.y+14),Vector2(64,button.position.y+button.size.y-14),UiArt.AMBER,2)
	UiArt.text(decoration,Vector2(480,160),TABS[tab],30,UiArt.IVORY,UiArt.MENU_FONT)
	UiArt.text(decoration,Vector2(80,819),"Pfeile / Steuerkreuz: wählen · Enter / A: bestätigen",13,UiArt.MUTED)
	decoration.draw_line(Vector2(80,724),Vector2(360,724),Color(UiArt.MUTED,.22),1)
	match tab:
		0:
			_note("F11 oder Alt + Enter wechselt jederzeit das Vollbild." if not hud.display_settings.is_embedded() else "Eigenes Fenster: Vollbild aus dem Hauptmenü starten.",Vector2(480,195),880)
			_row("Anzeigemodus",270,"Fenster oder Vollbild.")
			_row("Vertikale Synchronisation",372,"Verhindert Bildrisse.")
			_row("Wettereffekte reduzieren",462,"F3: weniger Partikel und ruhigere Pflanzen.")
			_row("Gewaltdarstellung",552,"Nur auf deinem Bildschirm. Schaden und Spielregeln bleiben gleich.")
			_row("Grafikrenderer",642,"Neustart erforderlich · nur im Hauptmenü")
			_note("Kompatibilität ist die Standardeinstellung.",Vector2(480,701),480)
		1:
			_note("Die Übersicht zeigt den Bunker; die Folgekamera begleitet deine Figur.",Vector2(480,195),880)
			_row("Kameramodus",270,"")
			_label("Vergrößerung",386)
			_value(L.format("%d %%",roundi(zoom_slider.value*100)),386)
			_note("Mausrad: näher heran oder weiter heraus. Im lokalen Koop bleiben beide Spieler im Blick.",Vector2(480,482),880)
		2:
			_note("0 % = stumm. Untertitel bleiben sichtbar. Lautstärken werden gespeichert.",Vector2(480,195),880)
			for index in 3:
				var y := 282+index*130
				_label(["Hintergrundmusik","Effekte und Maschinen","Figurendialoge"][index],y)
				var volume: float = [game.audio.music_volume,game.audio.sfx_volume,game.audio.voice_volume][index]
				_value(L.format("%02d%%",roundi(volume*100)),y)
		3:
			_note("Musik folgt der Schicht. Ruhige Figuren bewegen sich im Takt.",Vector2(480,195),880)
			_row("Live-Musik pro Schauplatz",270,"")
			_row("Musikstil · nächste Schicht",356,"")
			_row("Taktbewegungen reduzieren",442,"")
			_label("Stärke der Taktbewegungen",510)
			_value(L.format("%d %%",roundi(dance_gain_slider.value*100)),510)
			_label("Takt und Bild abstimmen",620)
			_note(L.format("Ausgleich: %d ms",roundi(game.audio.music_calibration_seconds*1000)),Vector2(480,648),480)
			_note("Im Musik-Labor kannst du jede Figur einzeln abstimmen und die Einstellungen teilen.",Vector2(480,760),880)
		4:
			_note("Text und gesprochene Dialoge",Vector2(480,195),880)
			_note("Die Sprache wechselt sofort. Deine Schicht und offene Auswahl bleiben erhalten.",Vector2(480,461),880)
			_note("Im Online-Koop wählt jeder Spieler seine eigene Sprache.",Vector2(480,533),880)
			_note("Die Auswahl wird für den nächsten Start gespeichert.",Vector2(480,605),880)

func _gore():
	return game.combat_gore if "combat_gore" in game and is_instance_valid(game.combat_gore) else null

func _label(value: String,y: float) -> void:
	UiArt.text(decoration,Vector2(480,y),value,19)

func _value(value: String,y: float) -> void:
	var width := UiArt.FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
	UiArt.text(decoration,Vector2(1360-width,y),value,19,UiArt.AMBER)

func _row(title: String,y: float,detail: String) -> void:
	_label(title,y)
	if not detail.is_empty(): _note(detail,Vector2(480,y+29),480)
	decoration.draw_line(Vector2(480,y+62),Vector2(1360,y+62),Color(UiArt.MUTED,.16),1)

func _note(value: String,at: Vector2,width: float) -> void:
	var lines := UiArt.wrap_text(value,width,15)
	for index in lines.size(): UiArt.text(decoration,at+Vector2(0,index*21),lines[index],15,UiArt.MUTED)

func _open_calibration() -> void:
	if has_modal_subpanel(): return
	_modal_opener = get_viewport().gui_get_focus_owner()
	calibration_panel=preload("res://scripts/music_calibration_panel.gd").new()
	calibration_panel.audio=game.audio
	calibration_panel.closed.connect(_calibration_closed.bind(calibration_panel.get_instance_id()))
	calibration_panel.tree_exited.connect(_calibration_closed.bind(calibration_panel.get_instance_id()))
	add_child(calibration_panel)
	_hide_modal_controls(calibration_panel)
	_redraw()

func _hide_modal_controls(except: Node = null) -> void:
	_modal_visibility.clear()
	for child in get_children():
		if child is CanvasItem and not child.is_queued_for_deletion() and child!=except and child!=_landscape.get("clip"):
			_modal_visibility[child.get_instance_id()] = child.visible
			child.hide()

func _restore_modal_controls() -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	for instance_id: int in _modal_visibility:
		var child := instance_from_id(instance_id) as CanvasItem
		if is_instance_valid(child) and not child.is_queued_for_deletion(): child.visible = bool(_modal_visibility[instance_id])
	_modal_visibility.clear()
	select_tab(tab)
	if is_instance_valid(_modal_opener) and _modal_opener.is_visible_in_tree() and not (_modal_opener is BaseButton and _modal_opener.disabled):
		_modal_opener.grab_focus.call_deferred()
	else:
		tab_buttons[tab].grab_focus.call_deferred()
	_redraw()

func _calibration_closed(instance_id: int) -> void:
	if not is_instance_valid(calibration_panel) or calibration_panel.get_instance_id()!=instance_id: return
	calibration_panel = null
	_restore_modal_controls()

func _music_lab_closed(instance_id: int) -> void:
	if not is_instance_valid(music_lab) or music_lab.get_instance_id()!=instance_id: return
	music_lab = null
	_restore_modal_controls()

func _cinematic_player_closed(instance_id: int) -> void:
	if not is_instance_valid(cinematic_player) or cinematic_player.get_instance_id()!=instance_id: return
	cinematic_player = null
	_restore_modal_controls()

func has_modal_subpanel() -> bool:
	return is_instance_valid(calibration_panel) or is_instance_valid(music_lab) or is_instance_valid(cinematic_player) or is_instance_valid(support_panel) or is_instance_valid(release_panel)

func close_modal_subpanel() -> bool:
	if is_instance_valid(release_panel):
		release_panel.close()
		return true
	if is_instance_valid(cinematic_player):
		cinematic_player.close()
		return true
	if is_instance_valid(support_panel):
		support_panel.close()
		return true
	if is_instance_valid(calibration_panel):
		calibration_panel.close()
		return true
	if is_instance_valid(music_lab):
		music_lab.close()
		return true
	return false

func _exit_tree() -> void:
	# The lab is parented to the root, so it must follow the options lifetime.
	if is_instance_valid(music_lab) and not music_lab.is_queued_for_deletion(): music_lab.close()
	if is_instance_valid(cinematic_player) and not cinematic_player.is_queued_for_deletion(): cinematic_player.close()

func _open_cinematic_player() -> void:
	if game.started or has_modal_subpanel(): return
	_modal_opener = get_viewport().gui_get_focus_owner()
	cinematic_player = preload("res://scripts/cinematic_dev_player.gd").new()
	cinematic_player.show_for_game(game)
	cinematic_player.closed.connect(_cinematic_player_closed.bind(cinematic_player.get_instance_id()))
	cinematic_player.tree_exited.connect(_cinematic_player_closed.bind(cinematic_player.get_instance_id()))
	get_viewport().add_child(cinematic_player)
	_hide_modal_controls()

func _open_music_lab(start_audition: bool = true) -> void:
	if game.started or has_modal_subpanel(): return
	_modal_opener = get_viewport().gui_get_focus_owner()
	music_lab=preload("res://scripts/music_dev_dashboard.gd").new()
	music_lab.audition_enabled = start_audition
	# Configure before _ready: one native preview startup for one lab opening.
	music_lab.show_for_game(game)
	get_viewport().add_child(music_lab)
	_hide_modal_controls()
	music_lab.closed.connect(_music_lab_closed.bind(music_lab.get_instance_id()))
	music_lab.tree_exited.connect(_music_lab_closed.bind(music_lab.get_instance_id()))

func _open_support_report() -> void:
	if has_modal_subpanel() or not is_instance_valid(hud.support_diagnostics): return
	_modal_opener = get_viewport().gui_get_focus_owner()
	support_panel = preload("res://scripts/support_report_panel.gd").new()
	support_panel.diagnostics = hud.support_diagnostics
	support_panel.hud = hud
	support_panel.closed.connect(_support_closed.bind(support_panel.get_instance_id()))
	support_panel.tree_exited.connect(_support_closed.bind(support_panel.get_instance_id()))
	add_child(support_panel)
	_hide_modal_controls(support_panel)
	_redraw()

func _open_release_notes() -> void:
	if has_modal_subpanel(): return
	_modal_opener=get_viewport().gui_get_focus_owner()
	release_panel=preload("res://scripts/release_notes_panel.gd").new()
	release_panel.hud=hud
	release_panel.closed.connect(_release_closed.bind(release_panel.get_instance_id()))
	release_panel.tree_exited.connect(_release_closed.bind(release_panel.get_instance_id()))
	add_child(release_panel)
	_hide_modal_controls(release_panel)
	_redraw()

func _release_closed(instance_id: int) -> void:
	if not is_instance_valid(release_panel) or release_panel.get_instance_id()!=instance_id: return
	release_panel=null
	_restore_modal_controls()

func _support_closed(instance_id: int) -> void:
	if not is_instance_valid(support_panel) or support_panel.get_instance_id()!=instance_id: return
	support_panel = null
	_restore_modal_controls()
