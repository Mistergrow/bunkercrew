extends SceneTree
## Close-up sheet of the texel-grid smoke primitive (PixelEffectArt.grid_smoke)
## as the game uses it: single puffs of four sizes across their fade, a blast
## cluster of overlapping billows (as impact_burst.gd lays them out) at four
## ages, and a wreck plume of drifting puffs, on a day and a night backdrop.
## Graphical display only:
##   godot --fixed-fps 60 --path . --script tests/vfx_smoke_shading_capture.gd -- --no-profile-save [--out=<folder>] [--scale=3]
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
const PixelGrid := preload("res://scripts/pixel_grid.gd")
const CELL := Vector2(80, 80)
var output := "res://artifacts/visual-pass4-fx/smoke"

class Backdrop extends Node2D:
	var night := false
	func _draw() -> void:
		draw_rect(Rect2(-2000,-2000,4000,4000),Color("1c2433") if night else Color("8da7c2"))
		for index in 6:
			draw_rect(Rect2(-2000,-200+index*90,4000,8),Color("2a3344") if night else Color("b9c9d8"))

class Sheet extends Node2D:
	const SIZES := [6.0, 12.0, 20.0, 30.0]
	const FADES := [0.0, .25, .5, .7, .85, .95]
	func _ready() -> void:
		material = PixelArt.grid_material(PixelArt.GRID_LIT)
	func _draw() -> void:
		# Row block 1: one puff per size (rows) across its fade (columns).
		for row in SIZES.size():
			for column in FADES.size():
				var at := Vector2(column*70.0+40,row*CELL.y+40)
				PixelArt.grid_smoke(self,at,SIZES[row],Color(PixelArt.smoke_tone(Color("8a8884")),1.0),row*3+1,FADES[column],0.6 if column == 0 else 0.0)
		# Blast cluster: seven billows at four ages (fade 0, .3, .6, .85).
		var offsets := [Vector2(0,0),Vector2(-.7,-.5),Vector2(.6,-.6),Vector2(-.2,-1.1),Vector2(.9,.1),Vector2(-.9,.2),Vector2(.3,-1.4)]
		var sizes := [1.0,.72,.78,.66,.62,.58,.55]
		for age in 4:
			var origin := Vector2(age*125+490,90)
			var fade: float = [0.0,.3,.6,.85][age]
			for index in range(offsets.size()-1,-1,-1):
				var tone := Color("837d74")
				tone = tone.lightened(.07) if index%3 == 1 else (tone.darkened(.08) if index%3 == 2 else tone)
				PixelArt.grid_smoke(self,origin+Vector2(offsets[index])*30.0,30.0*float(sizes[index]),Color(PixelArt.smoke_tone(tone),1.0),index+7,fade,0.5 if age == 0 else 0.0,0.15)
		# Dark fuel cluster, same layout.
		for age in 4:
			var origin := Vector2(age*125+490,230)
			var fade: float = [0.0,.3,.6,.85][age]
			for index in range(offsets.size()-1,-1,-1):
				PixelArt.grid_smoke(self,origin+Vector2(offsets[index])*26.0,26.0*float(sizes[index]),Color(PixelArt.smoke_tone(Color("47423d")),1.0),index+3,fade,0.6 if age == 0 else 0.0)
		# A wreck plume: puffs rising and growing from a source.
		for index in 12:
			var life := float(index)/11.0
			var at := Vector2(500+life*60.0+sin(life*7.0)*6.0,560-life*170.0)
			PixelArt.grid_smoke(self,at,3.0+life*16.0,Color(PixelArt.smoke_tone(Color(.28,.27,.26)),.8),index,smoothstep(.2,1.0,life),clampf(1.0-life*3.0,0.0,1.0)*.7,clampf(.3*life,0.0,.4))
		# Gun smoke wisps.
		for index in 8:
			var life := float(index)/7.0
			PixelArt.grid_smoke(self,Vector2(640+index*26,520-life*20.0),2.5+life*8.0,Color(PixelArt.smoke_tone(Color(.78,.76,.71)),.55*(1.0-life*.5)),index,clampf(.25+smoothstep(.2,1.0,life)*.75,0.0,1.0))

func _argument(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return fallback

func _initialize() -> void:
	output = _argument("--out=", output)
	var pixel_scale := float(_argument("--scale=", "2"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1920, 1080)
	for night in [false, true]:
		var backdrop := Backdrop.new()
		backdrop.night = night
		root.add_child(backdrop)
		PixelArt.set_atmosphere(Color("cfd8df"), Color(.32,.36,.48) if night else Color.WHITE)
		var sheet := Sheet.new()
		root.add_child(sheet)
		if night:
			var dark := CanvasModulate.new()
			dark.color = Color(.42,.46,.58)
			root.add_child(dark)
		var camera := Camera2D.new()
		camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
		camera.zoom = PixelGrid.zoom_for(pixel_scale, root)
		camera.position = Vector2.ZERO
		root.add_child(camera)
		camera.make_current()
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path(output) + ("/night.png" if night else "/day.png"))
		for node in [backdrop, sheet, camera]: node.queue_free()
		for child in root.get_children():
			if child is CanvasModulate: child.queue_free()
		await process_frame
	print("VFX SMOKE SHADING: captured into ", ProjectSettings.globalize_path(output))
	quit(0)
