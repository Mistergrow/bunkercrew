extends SceneTree
## Renders the vehicle guns of GroundVehicleArt.draw_weapon at 8 px per unit
## into assets/enemies/vehicle_guns_src.png, the high-density source that
## tools/bake_world_density_art.py reduces to the guns' drawn sizes in aim
## stances (tools/world_density_bake.json, vehicle_guns_world). Needs a
## renderer (display :78):
##     godot --path . --script tools/capture_vehicle_guns.gd -- --no-profile-save
const VehicleArt := preload("res://scripts/ground_vehicle_art.gd")
const OUTPUT := "res://assets/enemies/vehicle_guns_src.png"
const KINDS := ["scout_car","mortar_carrier","battle_tank"]
## The gun's own space that each row holds (GroundVehicleArt.GUN_RECTS).
const SCALE := 8.0

## The fields draw_weapon reads, at rest: no flash, no breech slide, no ride.
class Mount extends Node2D:
	var kind := ""
	var motion: Node2D
	var game: Node
	var muzzle_flash := 0.0
	var attack_count := 0
	var locomotion_speed := 0.0
	var move_speed := 1.0
	var age := 0.1
	var attack_direction := -1.0
	var visual_scale := 1.0
	var weapon_part: Node2D

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var rect: Rect2 = VehicleArt.GUN_RECTS.scout_car
	var view := SubViewport.new()
	view.transparent_bg = true
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.size = Vector2i(Vector2(rect.size.x, rect.size.y * KINDS.size()) * SCALE)
	root.add_child(view)
	for row in KINDS.size():
		var mount := Mount.new()
		mount.kind = KINDS[row]
		var canvas := Node2D.new()
		var place: Rect2 = VehicleArt.GUN_RECTS[mount.kind]
		canvas.scale = Vector2.ONE * SCALE
		canvas.position = (-place.position + Vector2(0, rect.size.y * row)) * SCALE
		mount.weapon_part = canvas
		canvas.draw.connect(func() -> void: VehicleArt.draw_weapon(mount, true))
		view.add_child(canvas)
		view.add_child(mount)
	for frame in 4: await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	var result := image.save_png(ProjectSettings.globalize_path(OUTPUT))
	print("VEHICLE GUNS ", image.get_size(), " ", result)
	quit(0 if result == OK else 1)
