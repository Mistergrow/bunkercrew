extends Node
## Local material lighting uses the machine's pause-aware animation clock.
## One draw pass, no screen textures. Offscreen machines have no update callback.
const SURFACE_SHADER := preload("res://shaders/station_surface.gdshader")
const SurfaceArt := preload("res://scripts/station_surface_art.gd")
const EFFECT_FPS := 12.0
const MACHINE_BOUNDS := Rect2(-95, -155, 190, 160)
const SETTINGS := {
	"furnace": {"chamber": Vector4(-19, -45, 39, 24), "heat": 0.27, "heat_tint": Color("f6a44e")},
	"glass": {"chamber": Vector4(-26, -67, 48, 33), "heat": 0.25, "heat_tint": Color("f6b463"), "contacts": [Vector4(54, -45, 4, 5), Vector4(61, -45, 4, 5)], "power": 0.17, "power_tint": Color("9bd4b9")},
	"alloy": {"chamber": Vector4(-25, -66, 43, 27), "heat": 0.20, "heat_tint": Color("eed3a0"), "contacts": [Vector4(-24, -120, 4, 35), Vector4(16, -120, 4, 35)], "power": 0.24, "power_tint": Color("a4c8bc")},
	"ammo_press": {"heat": 0.0, "contacts": [Vector4(-62, -64, 6, 6), Vector4(-62, -64, 6, 6)], "power": 0.19, "power_tint": Color("d4c284")},
}

var station: Node2D
var surface_material: ShaderMaterial
var screen_notifier: VisibleOnScreenNotifier2D
var on_screen := false
var uniform_updates := 0
var _last_tick := -1
var _active := false
var _settings: Dictionary

func _ready() -> void:
	station = get_parent() as Node2D
	_settings = SETTINGS.get(str(station.get("kind")), {})
	set_process(false)
	if _settings.is_empty():
		return
	surface_material = ShaderMaterial.new()
	surface_material.shader = SURFACE_SHADER
	surface_material.set_shader_parameter("chamber", _settings.get("chamber", Vector4.ZERO))
	surface_material.set_shader_parameter("heat_tint", _settings.get("heat_tint", Color.WHITE))
	surface_material.set_shader_parameter("power_tint", _settings.get("power_tint", Color.WHITE))
	var contacts: Array = _settings.get("contacts", [Vector4.ZERO, Vector4.ZERO])
	surface_material.set_shader_parameter("power_contact_a", contacts[0])
	surface_material.set_shader_parameter("power_contact_b", contacts[1])
	screen_notifier = VisibleOnScreenNotifier2D.new()
	screen_notifier.rect = MACHINE_BOUNDS
	screen_notifier.screen_entered.connect(_screen_entered)
	screen_notifier.screen_exited.connect(_screen_exited)
	_attach_notifier.call_deferred()

func _attach_notifier() -> void:
	if not is_instance_valid(screen_notifier):
		return
	if not is_instance_valid(station) or station.is_queued_for_deletion() or is_queued_for_deletion():
		screen_notifier.free()
		screen_notifier = null
		return
	station.add_child(screen_notifier)

func _exit_tree() -> void:
	# A level rebuild can remove the station before its deferred attachment runs.
	# The pending notifier has no owner yet, so the scene cannot free it for us.
	if is_instance_valid(screen_notifier) and screen_notifier.get_parent() == null:
		screen_notifier.free()
		screen_notifier = null

func _screen_entered() -> void:
	on_screen = true
	set_process(true)
	_refresh()

func _screen_exited() -> void:
	on_screen = false
	set_process(false)
	_active = false
	if station.material == surface_material:
		station.material = null

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	var active: bool = bool(station.get("working")) and not SurfaceArt.reduced_effects(station)
	if not active:
		if _active:
			station.material = null
		_active = false
		return
	var tick := floori(float(station.get("elapsed")) * EFFECT_FPS)
	if _active and station.material == surface_material and tick == _last_tick:
		return
	_active = true
	_last_tick = tick
	var animation_time := float(tick) / EFFECT_FPS
	var heat_pulse := 0.88 + sin(animation_time * 7.4) * 0.08 + sin(animation_time * 4.3) * 0.04
	var power_pulse := 0.80 + sin(animation_time * 5.1 + 1.2) * 0.20
	surface_material.set_shader_parameter("heat_strength", float(_settings.get("heat", 0.0)) * heat_pulse)
	surface_material.set_shader_parameter("power_strength", float(_settings.get("power", 0.0)) * power_pulse)
	surface_material.set_shader_parameter("effect_phase", fposmod(animation_time * 0.68, 1.0))
	station.material = surface_material
	uniform_updates += 1
