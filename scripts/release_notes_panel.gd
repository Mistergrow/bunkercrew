extends Control
signal closed
const L := preload("res://scripts/locale_text.gd")
const Identity := preload("res://scripts/build_identity.gd")
const Notes := preload("res://scripts/release_notes_catalog.gd")
const READER := Rect2(480,192,800,612)
const FADE := 30.0
var hud: Node
var reader: TextEdit
var back_button: Button
var _closed:=false

## Gives the plain notes a reading hierarchy without changing their text: the
## "version · date" line in amber, the release title brightest, entries ivory.
class NotesHighlighter extends SyntaxHighlighter:
	func _get_line_syntax_highlighting(line: int) -> Dictionary:
		var edit:=get_text_edit()
		var value:=edit.get_line(line)
		if value.strip_edges().is_empty() or value.begins_with("• "): return {0:{"color":UiArt.IVORY}}
		if line==0 or edit.get_line(line-1).strip_edges().is_empty(): return {0:{"color":UiArt.AMBER}}
		return {0:{"color":UiArt.TEXT_HOVER}}

func _ready() -> void:
	name="ReleaseNotesPanel"
	process_mode=Node.PROCESS_MODE_ALWAYS
	mouse_filter=Control.MOUSE_FILTER_STOP
	size=Vector2(1440,900)
	draw.connect(_draw_notes)
	# The notes follow the menu grid: title and actions in the left column, a
	# reading column of about 95 characters at 19 px beside it. The bottom margin
	# keeps the last line clear of the fade when the reader is scrolled to the end.
	reader=TextEdit.new()
	reader.position=READER.position
	reader.size=READER.size
	reader.editable=false
	reader.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	reader.add_theme_font_override("font",UiArt.FONT)
	reader.add_theme_font_size_override("font_size",19)
	reader.add_theme_constant_override("line_spacing",6)
	reader.add_theme_color_override("font_color",UiArt.IVORY)
	reader.add_theme_color_override("font_readonly_color",UiArt.IVORY)
	var paper:=StyleBoxFlat.new()
	paper.bg_color=Color(.040,.058,.060,1.0)
	paper.content_margin_left=20
	paper.content_margin_right=20
	paper.content_margin_top=14
	paper.content_margin_bottom=FADE+6
	reader.add_theme_stylebox_override("normal",paper)
	reader.add_theme_stylebox_override("read_only",paper)
	var focused:=paper.duplicate() as StyleBoxFlat
	focused.border_width_left=2
	focused.border_color=UiArt.AMBER
	reader.add_theme_stylebox_override("focus",focused)
	reader.syntax_highlighter=NotesHighlighter.new()
	reader.gui_input.connect(_reader_input)
	add_child(reader)
	# Lines scrolled past the lower edge dissolve into the paper instead of
	# being cut mid-glyph; drawn above the reader, it never takes input.
	var fade:=Control.new()
	fade.name="ReaderFade"
	fade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	fade.position=Vector2(READER.position.x,READER.end.y-FADE)
	fade.size=Vector2(READER.size.x-14,FADE)
	fade.draw.connect(func():
		var paper_color:=Color(.040,.058,.060)
		fade.draw_polygon(PackedVector2Array([Vector2.ZERO,Vector2(fade.size.x,0),fade.size,Vector2(0,fade.size.y)]),PackedColorArray([Color(paper_color,0),Color(paper_color,0),paper_color,paper_color])))
	add_child(fade)
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
	# A full-screen reading page is opaque: the menu wordmark, roster and hints
	# underneath must not ghost through the notes.
	draw_rect(SocialUiArt.bounds(hud),Color(.024,.040,.044,1.0))
	UiArt.text(self,Vector2(80,112),"Änderungen",UiArt.TEXT_SIGNAL,UiArt.IVORY,UiArt.TITLE_FONT)
	UiArt.text(self,Vector2(80,164),Identity.display_text(),17,UiArt.MUTED)
	UiArt.divider(self,Vector2(80,724),Vector2(400,724))
