extends Control
## Session decisions share the open options/lobby presentation over the world.
signal confirmed
signal canceled
const L := preload("res://scripts/locale_text.gd")
const TEXT_WIDTH := 780.0
var hud
var heading := "Schicht neu starten?"
var message := "Der Fortschritt der laufenden Mission geht verloren."
var detail := "Einstellungen und gelernte Tänze bleiben erhalten."
var confirm_label := "Neu starten"
var confirm_button: Button
var cancel_button: Button
var blocker: Control

func _ready() -> void:
	name = "SessionActionPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440,900)
	blocker = Control.new()
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	confirm_button = _button(confirm_label,Rect2(1000,268,360,58),"play",func(): confirmed.emit())
	cancel_button = _button("Abbrechen",Rect2(1000,348,360,58),"back",func(): canceled.emit())
	for button: Button in [cancel_button,confirm_button]:
		var other := confirm_button if button==cancel_button else cancel_button
		button.focus_neighbor_left = NodePath(".")
		button.focus_neighbor_right = NodePath(".")
		button.focus_neighbor_top = button.get_path_to(other)
		button.focus_neighbor_bottom = button.get_path_to(other)
		button.focus_next = button.get_path_to(other)
		button.focus_previous = button.get_path_to(other)
		button.focus_entered.connect(queue_redraw)
		button.focus_exited.connect(queue_redraw)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _button(label: String,rect: Rect2,glyph: String,callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.position = rect.position
	button.size = rect.size
	SocialUiArt.button(button,24,glyph,12)
	button.pressed.connect(callback)
	add_child(button)
	return button

func _layout() -> void:
	var bounds: Rect2 = hud.screen_rect()
	blocker.position = bounds.position
	blocker.size = bounds.size
	queue_redraw()

func open(title: String,body: String,note: String,accept: String) -> void:
	heading = title
	message = body
	detail = note
	confirm_label = accept
	confirm_button.text = L.text(confirm_label)
	cancel_button.text = L.text("Abbrechen")
	show()
	_layout()
	cancel_button.grab_focus.call_deferred()

func refresh_locale() -> void:
	confirm_button.text = L.text(confirm_label)
	cancel_button.text = L.text("Abbrechen")
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible or event.is_echo(): return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		canceled.emit()
		return
	# Keep native accept and navigation inside the two-action focus loop. All
	# other keyboard/controller events stop here before reaching another panel.
	# Space is the game's start shortcut, rather than a second confirmation key.
	if event.is_action_pressed("start"):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction:
		for action: String in ["ui_accept","ui_left","ui_right","ui_up","ui_down","ui_focus_next","ui_focus_prev"]:
			if event.is_action(action): return
		get_viewport().set_input_as_handled()

func _draw() -> void:
	var bounds: Rect2 = SocialUiArt.bounds(hud)
	draw_rect(bounds,Color(.01,.015,.018,.20))
	SocialUiArt.reading_shade(self,bounds,780,990)
	var headings := UiArt.wrap_text(heading,TEXT_WIDTH,36,UiArt.TITLE_FONT)
	for index in headings.size():
		UiArt.text(self,Vector2(80,112+index*46),headings[index],36,UiArt.IVORY,UiArt.TITLE_FONT)
	var lines := UiArt.wrap_text(message,TEXT_WIDTH,20)
	for index in lines.size():
		UiArt.text(self,Vector2(80,252+index*30),lines[index],20)
	var notes := UiArt.wrap_text(detail,TEXT_WIDTH,15)
	var note_y := maxf(410,252+lines.size()*30+48)
	for index in notes.size():
		UiArt.text(self,Vector2(80,note_y+index*23),notes[index],15,UiArt.MUTED)
	var selected: Button = cancel_button if cancel_button.has_focus() else confirm_button if confirm_button.has_focus() else null
	if selected!=null:
		draw_line(Vector2(984,selected.position.y+17),Vector2(984,selected.position.y+selected.size.y-17),UiArt.AMBER,2)
	draw_line(Vector2(80,724),Vector2(1360,724),Color(UiArt.MUTED,.18),1)
	UiArt.text(self,Vector2(80,819),"Pfeile / Steuerkreuz: wählen · Enter / A: bestätigen",13,UiArt.MUTED)
