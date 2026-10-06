extends Control
## Presentation-only adapters render production art on an isolated World2D.
## Neither adapter creates a vehicle, campaign, enemy or gameplay controller.
const TravelCatalog := preload("res://scripts/travel_cinematic_catalog.gd")
const TravelArt := preload("res://scripts/travel_cinematic_art.gd")
const AirCatalog := preload("res://scripts/air_raid_intro_catalog.gd")
const REFERENCE := Vector2(1440,900)

class PreviewAirController extends Node:
	# Inherited AirRaidIntroPanel connects these external presentation signals.
	# The isolated player supplies frames directly; emitting would start audio.
	@warning_ignore("unused_signal")
	signal began(context: Dictionary)
	@warning_ignore("unused_signal")
	signal ended(skipped: bool)
	var active := false
	var elapsed := 0.0
	var duration := 8.0
	var context: Dictionary = {}
	func skip() -> void: pass

class PreviewWeather extends Node:
	var reduced_effects := false

class PreviewGame extends Node:
	var air_raid_intro: Node
	var weather: Node
	var audio: Node

class PreviewHud extends Node:
	func screen_rect() -> Rect2: return Rect2(Vector2.ZERO,REFERENCE)

class AirPresentation extends "res://scripts/air_raid_intro_panel.gd":
	# The developer player owns all audio and the clock. Production drawing,
	# cloud layers, aircraft animation and the real subtitle layout are reused.
	func _process(_delta: float) -> void: pass
	func _play_voice() -> void: pass
	func _set_ducked(_enabled: bool) -> void: pass
	func _locale_changed(_locale: String) -> void: pass

var context: Dictionary = {}
var clock := 0.0
var reduced := false
var subtitles := true
var travel_canvas: Node2D
var travel_shade: Node2D
var travel_title: Label
var travel_speaker: Label
var travel_caption: Label
var air_panel: Control
var air_controller: PreviewAirController
var preview_game: PreviewGame

func _ready() -> void:
	name="CinematicPreviewWorld"
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	size=REFERENCE
	travel_canvas=Node2D.new()
	travel_canvas.draw.connect(func(): TravelArt.draw(travel_canvas,context,clock,reduced))
	add_child(travel_canvas)
	travel_shade=Node2D.new()
	travel_shade.draw.connect(func(): travel_shade.draw_rect(Rect2(0,680,1440,220),Color(.025,.045,.045,.80)))
	add_child(travel_shade)
	travel_title=_label(29,UiArt.IVORY,Vector2(62,47),Vector2(1316,55))
	travel_speaker=_label(20,UiArt.AMBER,Vector2(92,719),Vector2(1256,32))
	travel_caption=_label(24,UiArt.IVORY,Vector2(92,759),Vector2(1256,100))
	travel_caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	preview_game=PreviewGame.new()
	preview_game.air_raid_intro=PreviewAirController.new()
	preview_game.weather=PreviewWeather.new()
	preview_game.add_child(preview_game.air_raid_intro)
	preview_game.add_child(preview_game.weather)
	add_child(preview_game)
	air_controller=preview_game.air_raid_intro
	var preview_hud:=PreviewHud.new()
	add_child(preview_hud)
	air_panel=AirPresentation.new()
	air_panel.game=preview_game
	air_panel.hud=preview_hud
	add_child(air_panel)
	tree_exiting.connect(func():
		if is_instance_valid(air_panel.voice): air_panel.voice.stop()
		if is_instance_valid(air_panel.flyover): air_panel.flyover.stop())

func _label(font_size: int,tint: Color,at: Vector2,extent: Vector2) -> Label:
	var label:=Label.new()
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.position=at
	label.size=extent
	label.add_theme_font_override("font",UiArt.MENU_FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",tint)
	label.add_theme_color_override("font_shadow_color",Color("0b1415"))
	label.add_theme_constant_override("shadow_offset_y",2)
	add_child(label)
	return label

func present(value: Dictionary,seconds: float,show_subtitles: bool,reduced_effects: bool) -> void:
	context=value
	clock=seconds
	subtitles=show_subtitles
	reduced=reduced_effects
	var is_air:=str(context.get("id",""))=="air_raid"
	travel_canvas.visible=not is_air
	travel_shade.visible=not is_air
	travel_title.visible=not is_air
	travel_speaker.visible=not is_air and subtitles and clock>=TravelCatalog.VOICE_AT
	travel_caption.visible=travel_speaker.visible
	air_panel.visible=is_air
	if is_air:
		air_controller.context=context
		air_controller.elapsed=clock
		air_controller.duration=float(context.duration)
		air_controller.active=true
		preview_game.weather.reduced_effects=reduced
		air_panel.dialogue=context.dialogue
		air_panel._voice_started=true
		air_panel._refresh_dialogue()
		air_panel._layout()
		air_panel._update_frame()
		air_panel.skip_button.hide()
		air_panel.caption_label.visible=subtitles
		air_panel.speaker_label.visible=subtitles
		air_panel.portrait_canvas.visible=subtitles
	else:
		air_controller.active=false
		travel_title.text=str(context.title)
		travel_speaker.text=str(context.dialogue.speaker_name)
		travel_speaker.add_theme_color_override("font_color",context.dialogue.accent)
		travel_caption.text=str(context.dialogue.text)
		travel_canvas.queue_redraw()
	queue_redraw()

func subtitle_text() -> String:
	if not subtitles or clock<voice_at(): return ""
	return str(context.get("dialogue",{}).get("text",""))

func voice_at() -> float:
	return 1.15 if str(context.get("id",""))=="air_raid" else TravelCatalog.VOICE_AT

func _draw() -> void:
	if str(context.get("id",""))=="air_raid": return
	draw_rect(Rect2(0,680,1440,220),Color(.025,.045,.045,.80))
