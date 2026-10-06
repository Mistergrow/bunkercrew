extends CanvasLayer
## Invalid bundled data stops before world, audio and save services initialize.
var diagnostics: Array[String] = []

func _ready() -> void:
	name = "ContentStartupError"
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var background := ColorRect.new()
	background.color = Color("101a1b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,32)
	background.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(0,240)
	body.add_theme_constant_override("separation",20)
	center.add_child(body)
	var title := Label.new()
	title.text = LocaleText.text("Spielinhalte konnten nicht geladen werden")
	title.add_theme_font_override("font",UiArt.MENU_FONT)
	title.add_theme_font_size_override("font_size",24)
	title.add_theme_color_override("font_color",UiArt.IVORY)
	body.add_child(title)
	var explanation := Label.new()
	explanation.name = "ContentExplanation"
	explanation.text = LocaleText.text("Ein Inhaltspaket ist ungültig oder unvollständig. Installiere die passende Spielversion erneut. Spielstände bleiben unverändert.")
	explanation.add_theme_font_override("font",UiArt.FONT)
	explanation.add_theme_font_size_override("font_size",18)
	explanation.add_theme_color_override("font_color",UiArt.IVORY)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.custom_minimum_size.x = minf(680,get_viewport().get_visible_rect().size.x-64)
	body.add_child(explanation)
	var detail := Label.new()
	detail.name = "ContentDiagnostics"
	detail.text = "\n".join(diagnostics.slice(0,4))
	detail.add_theme_font_override("font",UiArt.FONT)
	detail.add_theme_font_size_override("font_size",16)
	detail.add_theme_color_override("font_color",UiArt.MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(detail)
	var close := Button.new()
	close.name = "QuitContentError"
	close.text = LocaleText.text("Beenden")
	SocialUiArt.button(close,22,"back")
	close.custom_minimum_size.y = 48
	close.pressed.connect(func(): get_tree().quit())
	body.add_child(close)
	close.grab_focus()
