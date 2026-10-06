extends Control
## Inspect, copy or save a safe local report; never send it to a service.
signal closed
const L := preload("res://scripts/locale_text.gd")
const Diagnostics := preload("res://scripts/support_diagnostics.gd")
const Identity := preload("res://scripts/build_identity.gd")
var diagnostics: Node
var hud: Node
var preview: TextEdit
var refresh_button: Button
var copy_button: Button
var save_button: Button
var back_button: Button
var status: Label
var report: Dictionary = {}
var _closed := false

func _ready() -> void:
	name="SupportReportPanel"
	process_mode=Node.PROCESS_MODE_ALWAYS
	size=Vector2(1440,900)
	mouse_filter=Control.MOUSE_FILTER_STOP
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	draw.connect(_draw_report)
	preview=TextEdit.new()
	preview.name="ReportPreview"
	preview.position=Vector2(80,224)
	preview.size=Vector2(1280,410)
	preview.editable=false
	preview.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	preview.add_theme_font_override("font",UiArt.FONT)
	preview.add_theme_font_size_override("font_size",16)
	preview.add_theme_color_override("font_color",UiArt.IVORY)
	var paper:=StyleBoxFlat.new()
	paper.bg_color=Color(.024,.040,.044,.8)
	paper.content_margin_left=16
	paper.content_margin_right=16
	paper.content_margin_top=12
	paper.content_margin_bottom=12
	preview.add_theme_stylebox_override("normal",paper)
	var focus:=paper.duplicate() as StyleBoxFlat
	focus.border_width_left=1
	focus.border_color=UiArt.AMBER
	preview.add_theme_stylebox_override("focus",focus)
	preview.gui_input.connect(_reader_input)
	add_child(preview)
	status=Label.new()
	status.position=Vector2(80,650)
	status.size=Vector2(1280,70)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_override("font",UiArt.FONT)
	status.add_theme_font_size_override("font_size",15)
	status.add_theme_color_override("font_color",UiArt.MUTED)
	status.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(status)
	refresh_button=_button("Aktualisieren",80,refresh_report)
	copy_button=_button("Bericht kopieren",400,_copy_report)
	copy_button.disabled=not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	save_button=_button("Bericht speichern",720,_save_report)
	back_button=_button("Zurück · Esc",1040,close)
	_wire_focus()
	refresh_report()
	refresh_locale()
	back_button.grab_focus.call_deferred()

func _button(message: String,x: float,callback: Callable) -> Button:
	var button:=Button.new()
	button.position=Vector2(x,744)
	button.size=Vector2(280,48)
	SocialUiArt.button(button,18,"",0)
	button.set_meta("support_label",message)
	button.pressed.connect(callback)
	add_child(button)
	return button

func _wire_focus() -> void:
	var controls: Array[Control]=[preview,refresh_button]
	if not copy_button.disabled: controls.append(copy_button)
	controls.append_array([save_button,back_button])
	for index in controls.size():
		var control:=controls[index]
		control.focus_next=control.get_path_to(controls[(index+1)%controls.size()])
		control.focus_previous=control.get_path_to(controls[posmod(index-1,controls.size())])
		if control!=preview:
			control.focus_neighbor_top=control.get_path_to(preview)
			control.focus_neighbor_bottom=NodePath(".")
			control.focus_neighbor_left=control.focus_previous
			control.focus_neighbor_right=control.focus_next
	preview.focus_neighbor_bottom=preview.get_path_to(refresh_button)
	preview.focus_neighbor_left=NodePath(".")
	preview.focus_neighbor_right=NodePath(".")

func refresh_report() -> void:
	if not is_instance_valid(diagnostics): return
	report=diagnostics.capture()
	preview.text=Diagnostics.encode(report)
	status.text=L.text("Ergänze beim Melden: Was hast du getan, was hast du erwartet und was ist passiert?")

func refresh_locale() -> void:
	for button: Button in [refresh_button,copy_button,save_button,back_button]:
		button.text=L.text(str(button.get_meta("support_label")))
	copy_button.tooltip_text=L.text("Die Zwischenablage ist hier nicht verfügbar.") if copy_button.disabled else ""
	queue_redraw()

func _copy_report() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD): return
	DisplayServer.clipboard_set(Diagnostics.encode(report))
	status.text=L.text("Bericht kopiert. Du entscheidest, mit wem du ihn teilst.")

func _save_report() -> void:
	var result:=Diagnostics.save_local(report)
	if bool(result.ok):
		status.text=L.format("Bericht gespeichert: %s",ProjectSettings.globalize_path(str(result.path)))
	else:
		status.text=L.text("Bericht konnte nicht gespeichert werden. Kopiere ihn oder prüfe den freien Speicherplatz.")

func _reader_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_prev") or event.is_action_pressed("ui_focus_next"):
		(back_button if event.is_action_pressed("ui_focus_prev") else refresh_button).grab_focus()
		preview.accept_event()
		return
	var bar:=preview.get_v_scroll_bar()
	if event.is_action_pressed("ui_down") and preview.get_v_scroll()>=bar.max_value-bar.page-1.0:
		refresh_button.grab_focus()
		preview.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("audio_settings"):
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	if _closed: return
	_closed=true
	hide()
	closed.emit()
	queue_free()

func _draw_report() -> void:
	var screen: Rect2=SocialUiArt.bounds(hud)
	draw_rect(screen,Color(.024,.040,.044,.96))
	UiArt.text(self,Vector2(80,112),"Fehlerbericht",36,UiArt.IVORY,UiArt.TITLE_FONT)
	UiArt.text(self,Vector2(740,112),Identity.display_text(),15,UiArt.MUTED)
	var lines:=UiArt.wrap_text("Nur technische Angaben und ein kurzer Zustandsverlauf. Keine Namen, Chattexte, Freundesdaten, Raumcodes oder Netzwerkadressen. Es wird nichts hochgeladen.",1280,17)
	for index in lines.size(): UiArt.text(self,Vector2(80,162+index*24),lines[index],17,UiArt.MUTED)
