extends Control
signal closed
const L := preload("res://scripts/locale_text.gd")
const Identity := preload("res://scripts/build_identity.gd")
const Notes := preload("res://scripts/release_notes_catalog.gd")
var hud: Node
var reader: TextEdit
var back_button: Button
var _closed:=false

func _ready() -> void:
	name="ReleaseNotesPanel"
	process_mode=Node.PROCESS_MODE_ALWAYS
	mouse_filter=Control.MOUSE_FILTER_STOP
	size=Vector2(1440,900)
	draw.connect(_draw_notes)
	reader=TextEdit.new()
	reader.position=Vector2(80,224)
	reader.size=Vector2(1280,470)
	reader.editable=false
	reader.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	reader.add_theme_font_override("font",UiArt.FONT)
	reader.add_theme_font_size_override("font_size",18)
	reader.add_theme_color_override("font_color",UiArt.IVORY)
	reader.add_theme_color_override("font_readonly_color",UiArt.IVORY)
	var paper:=StyleBoxFlat.new()
	paper.bg_color=Color(.024,.040,.044,.45)
	paper.content_margin_left=12
	paper.content_margin_right=16
	paper.content_margin_top=8
	reader.add_theme_stylebox_override("normal",paper)
	var focused:=paper.duplicate() as StyleBoxFlat
	focused.border_width_left=1
	focused.border_color=UiArt.AMBER
	reader.add_theme_stylebox_override("focus",focused)
	reader.gui_input.connect(_reader_input)
	add_child(reader)
	back_button=Button.new()
	back_button.position=Vector2(80,746)
	back_button.size=Vector2(300,48)
	SocialUiArt.button(back_button,20,"back",0)
	back_button.pressed.connect(close)
	add_child(back_button)
	reader.focus_next=reader.get_path_to(back_button)
	reader.focus_previous=reader.focus_next
	reader.focus_neighbor_bottom=reader.focus_next
	back_button.focus_next=back_button.get_path_to(reader)
	back_button.focus_previous=back_button.focus_next
	back_button.focus_neighbor_top=back_button.focus_next
	var localization:=get_node_or_null("/root/Localization")
	if localization!=null: localization.locale_changed.connect(refresh_locale)
	refresh_locale()
	back_button.grab_focus.call_deferred()

func refresh_locale(_locale: String="") -> void:
	reader.text=Notes.body_text()
	back_button.text=L.text("Zurück · Esc")
	queue_redraw()

func close() -> void:
	if _closed: return
	_closed=true
	hide()
	closed.emit()
	queue_free()

func _reader_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_prev") or event.is_action_pressed("ui_focus_next"):
		back_button.grab_focus()
		reader.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _draw_notes() -> void:
	draw_rect(SocialUiArt.bounds(hud),Color(.024,.040,.044,.96))
	UiArt.text(self,Vector2(80,112),"Änderungen",36,UiArt.IVORY,UiArt.TITLE_FONT)
	UiArt.text(self,Vector2(80,164),Identity.display_text(),17,UiArt.MUTED)
