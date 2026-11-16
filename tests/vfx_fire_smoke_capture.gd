extends SceneTree
## Close-up sheets of the texel-grid fire and smoke primitives
## (PixelEffectArt.grid_flame / grid_smoke / grid_halo / grid_fire): flames of
## several sizes and heats over twelve flipbook frames, and smoke puffs of
## three tones across their fade, by day and under a night ambient. Graphical
## display only:
##   godot --fixed-fps 60 --path . --script tests/vfx_fire_smoke_capture.gd -- --no-profile-save [--out=<folder>] [--scale=2] [--bench]
## --bench draws 40 flames, 60 smoke puffs and 8 halos every frame at 2x and
## prints the mean frame time; --legacy draws the pass-2 cel mass and fire
## ball at the same sizes instead, for a cost comparison.
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
const PixelGrid := preload("res://scripts/pixel_grid.gd")
const WorldLighting := preload("res://scripts/world_lighting.gd")
const FRAMES := 12
const CELL := Vector2(56, 56)
var output := "res://artifacts/visual-pass3-fire/primitives"

class Backdrop extends Node2D:
	var night := false
	func _draw() -> void:
		draw_rect(Rect2(-2000,-2000,4000,2560),Color("1c2433") if night else Color("7d97b2"))
		draw_rect(Rect2(-2000,560,4000,2000),Color("1d1c1a") if night else Color("3a3631"))

class Sheet extends Node2D:
	## One row per subject, one column per frame; `frame` advances the flames
	## and ages the smoke across the columns.
	var flames: Node2D
	var halos: Node2D
	var tick := 0
	var bench := false
	var legacy := false
	func _ready() -> void:
		material = PixelArt.grid_material(PixelArt.GRID_LIT)
		flames = Node2D.new()
		flames.material = PixelArt.grid_material(PixelArt.GRID_UNLIT)
		flames.draw.connect(_draw_flames)
		add_child(flames)
		halos = Node2D.new()
		halos.material = PixelArt.grid_material(PixelArt.GRID_ADD)
		halos.draw.connect(_draw_halos)
		add_child(halos)
	func refresh() -> void:
		queue_redraw()
		flames.queue_redraw()
		halos.queue_redraw()
	func _draw() -> void:
		if bench:
			for index in 60:
				if legacy:
					PixelArt.grid_cel(self,Vector2(-420+(index%12)*70,-300+floorf(index/12.0)*70),10.0+float(index%5)*5.0,Color("8a8884"),index,float(index%7)/8.0,float(index%3)/3.0)
					continue
				PixelArt.grid_smoke(self,Vector2(-420+(index%12)*70,-300+floorf(index/12.0)*70),10.0+float(index%5)*5.0,Color("8a8884"),index,float(index%7)/8.0,float(index%3)/3.0,.15)
			return
		# Smoke: light, mid and black tones across their life (rows 3..8).
		var tones := [Color("9a9790"), Color("6e6b66"), Color("3a3632")]
		for row in 3:
			for column in FRAMES:
				var life := float(column)/float(FRAMES-1)
				var base := Vector2(column*CELL.x+28,(3+row)*CELL.y+40)
				PixelArt.grid_smoke(self,base+Vector2(life*4.0,-life*10.0),9.0+life*12.0,Color(PixelArt.smoke_tone(tones[row]),.92),row*5+1,smoothstep(.15,1.0,life),clampf(1.0-life*2.2,0.0,1.0),life*.25)
		# Small wisps (row 6) and a flak puff turning from brown to grey (row 7).
		for column in FRAMES:
			var life := float(column)/float(FRAMES-1)
			var base := Vector2(column*CELL.x+28,6*CELL.y+38)
			PixelArt.smoke_puff(self,base+Vector2(life*6.0,-life*14.0),2.5+life*6.0,Color(.30,.30,.29,.6),column,life)
			var tone := Color("4a3a2c").lerp(Color("9a9893"),smoothstep(.04,.45,life))
			PixelArt.grid_smoke(self,Vector2(column*CELL.x+28,7*CELL.y+30),7.0+12.0*(1.0-exp(-life*3.0)),Color(PixelArt.smoke_tone(tone),.95),9,smoothstep(.25,1.0,life),0.0,life*.2)
	func _draw_flames() -> void:
		if bench:
			for index in 40:
				if legacy:
					PixelArt.grid_fire(flames,Vector2(-420+(index%10)*84,140+floorf(index/10.0)*60)-Vector2(0,8.0+float(index%5)*2.5),(8.0+float(index%4)*3.0)*.7,1.0-float(index%3)*.3,1.0,index)
					continue
				PixelArt.grid_flame(flames,Vector2(-420+(index%10)*84,140+floorf(index/10.0)*60),8.0+float(index%4)*3.0,16.0+float(index%5)*5.0,1.0-float(index%3)*.3,PixelArt.flame_frame(tick/60.0,index),index)
			return
		# Flames: four sizes at full heat, then a cooling one (rows 0..2).
		var sizes := [Vector2(5,9), Vector2(9,18), Vector2(14,30)]
		for row in 3:
			for column in FRAMES:
				var base := Vector2(column*CELL.x+28,row*CELL.y+52)
				var size: Vector2 = sizes[row]
				PixelArt.grid_flame(flames,base+Vector2(-8,0),size.x,size.y,1.0,column,row*3)
				PixelArt.grid_flame(flames,base+Vector2(10,0),size.x*.8,size.y*.85,.35,column+5,row*3+1,2.0)
		# Fireball cooling (row 8).
		for column in FRAMES:
			var heat := 1.0-float(column)/float(FRAMES-1)
			PixelArt.grid_fire(flames,Vector2(column*CELL.x+28,8*CELL.y+28),12.0+float(column)*.8,heat,1.0,4,smoothstep(.40,.0,heat)*.85)
	func _draw_halos() -> void:
		for row in (1 if bench else 3):
			for column in (8 if bench else FRAMES):
				PixelArt.grid_halo(halos,Vector2(column*CELL.x+28,row*CELL.y+40),10.0+row*6.0,Color(1.0,.55,.22,.35),column)

func _initialize() -> void:
	run.call_deferred()

func _argument(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return fallback

func run() -> void:
	output = _argument("--out=", output)
	var pixel_scale := float(_argument("--scale=", "2"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1920, 1080)
	await process_frame
	var backdrop := Backdrop.new()
	backdrop.material = WorldLighting.unshaded_material()
	root.add_child(backdrop)
	var sheet := Sheet.new()
	sheet.bench = "--bench" in OS.get_cmdline_user_args()
	sheet.legacy = "--legacy" in OS.get_cmdline_user_args()
	root.add_child(sheet)
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	camera.zoom = PixelGrid.zoom_for(2.0 if sheet.bench else pixel_scale, root)
	camera.make_current()
	if sheet.bench:
		camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		var samples: Array[float] = []
		var previous := Time.get_ticks_usec()
		for frame in 360:
			sheet.tick = frame
			sheet.refresh()
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			if frame >= 60: samples.append(float(now - previous) / 1000.0)
			previous = now
		var total := 0.0
		for sample in samples: total += sample
		print("VFX FIRE SMOKE BENCH ", "legacy " if sheet.legacy else "", RenderingServer.get_video_adapter_name(), " ", JSON.stringify({"frames":samples.size(), "mean_ms":snappedf(total / samples.size(), .001)}))
		quit(0)
		return
	var size := Vector2i(CELL * pixel_scale) * Vector2i(FRAMES, 9)
	for pass_index in 2:
		var night := pass_index == 1
		backdrop.night = night
		backdrop.queue_redraw()
		var ambient: CanvasModulate = null
		if night:
			ambient = CanvasModulate.new()
			ambient.color = WorldLighting.ambient_for(ScenarioCatalog.environment("ash_foundry"))
			root.add_child(ambient)
			PixelArt.set_atmosphere(Color("23394F"),ambient.color)
		else:
			PixelArt.set_atmosphere(Color("9BCDE0"))
		camera.position = Vector2(0, -8)
		sheet.refresh()
		for frame in 3: await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.crop(mini(size.x, image.get_width()), mini(size.y, image.get_height()))
		image.save_png(ProjectSettings.globalize_path(output) + ("/night.png" if night else "/day.png"))
		if ambient != null: ambient.queue_free()
	print("VFX FIRE SMOKE: captured into ", ProjectSettings.globalize_path(output))
	quit(0)
