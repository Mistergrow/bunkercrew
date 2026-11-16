extends SceneTree
## Same bursts, same seeds, drawn two ways side by side at a whole-pixel camera
## scale: left the earlier CPU shapes (two-unit blob rows, row-stripe dissolve,
## template puffs, smooth rotated shards and lines), right the grid shapes of
## pixel_effect_art.gd (one texel per world unit, ordered-dither dissolve).
## Graphical display only:
##   godot --fixed-fps 60 --path . --script tests/pixel_grid_effects_capture.gd -- --no-profile-save [--out=<folder>] [--scale=2]
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
const PixelGrid := preload("res://scripts/pixel_grid.gd")
const AGES := [.05, .12, .25, .45, .70, .95, 1.20, 1.45]
var output := "res://artifacts/visual-pass2-grid/effects-grid"
var pixel_scale := 2.0

## The earlier drawing, kept here only as the comparison baseline.
class LegacyBurst extends ImpactBurst:
	func _ready() -> void:
		super._ready()
		material = null
		if is_instance_valid(hot_layer): hot_layer.material = PixelArt.unlit_material()
		if is_instance_valid(glow_layer): glow_layer.material = PixelArt.additive_material()
	func _draw() -> void:
		if retired or _preset.is_empty(): return
		if surface_material == "explosion":
			var reach := 27.0*sqrt(power)
			var gone := smoothstep(.45,1.0,age/MAX_LIFETIME)
			for index in range(_lobe_offset.size()-1,-1,-1):
				var time := age-_lobe_shape[index].y
				if time <= 0.0: continue
				var center := _lobe_center(index,time,reach)
				var radius := _lobe_radius(index,time,reach)
				var smoke := SMOKE_BODY.lerp(Color("5b4038"),maxf(0.0,1.0-time/.85)*.7)
				var alpha := .80*(1.0-gone*.45)
				var thin := gone*.8+float(index%3)*.06*gone
				PixelArt.blob(self,center,radius,Color(smoke,alpha),index+seed_value,thin)
				PixelArt.blob(self,center+Vector2(-.18,-.24)*radius,radius*.62,Color(smoke.lightened(.26),alpha),index+seed_value+3,thin)
				PixelArt.blob(self,center+Vector2(.22,.30)*radius,radius*.46,Color(smoke.darkened(.34),alpha*.8),index+seed_value+5,thin)
		for bit in bits:
			if bit.age >= bit.life or bit.type == "sparks": continue
			var opacity: float = 1.0 - float(bit.age) / float(bit.life)
			var color: Color = bit.color
			color.a = minf(1, opacity * 1.7)
			var point: Vector2 = Vector2(bit.pos).round()
			var size: float = bit.size
			if bit.type == "dust":
				color.a = opacity * (0.34 if surface_material in ["concrete","earth"] else 0.23)
				PixelArt.puff(self,point,roundf(size * (1.0 + float(bit.age) * 1.5)),color,int(float(bit.life)*100.0),true)
			else:
				var axis := Vector2.from_angle(float(bit.rotation)) * size
				var side := axis.orthogonal() * (0.4 if surface_material == "glass" else 0.65)
				draw_colored_polygon(PackedVector2Array([(point-axis).round(), (point+side).round(), (point+axis).round(), (point-side*0.8).round()]), color)
				draw_line((point-axis).round(), (point+side).round(), Color(color.lightened(0.28),color.a), 1)
	func _draw_hot() -> void:
		if retired or _preset.is_empty(): return
		if surface_material == "explosion":
			var reach := 27.0*sqrt(power)
			for index in range(_lobe_offset.size()-1,-1,-1):
				var time := age-_lobe_shape[index].y
				if time <= 0.0: continue
				var heat := clampf(1.0-time/.34,0.0,1.0)
				if heat <= 0.0: continue
				var center := _lobe_center(index,time,reach)
				var radius := _lobe_radius(index,time,reach)
				var alpha := smoothstep(.0,.30,heat)*.96
				var body := FIRE_RED.lerp(FIRE_ORANGE,smoothstep(.25,.62,heat))
				PixelArt.blob(hot_layer,center,radius,Color(body,alpha),index+seed_value)
				var lit := FIRE_RED.lightened(.2).lerp(FIRE_ORANGE.lightened(.2),smoothstep(.0,.45,heat)).lerp(FIRE_HOT,smoothstep(.45,.95,heat))
				PixelArt.blob(hot_layer,center+Vector2(-.18,-.24)*radius,radius*.62,Color(lit,alpha),index+seed_value+3)
		for bit in bits:
			if bit.type != "sparks" or bit.age >= bit.life: continue
			var opacity: float = 1.0 - float(bit.age) / float(bit.life)
			var color: Color = bit.color
			color.a = minf(1, opacity * 1.7)
			var point: Vector2 = Vector2(bit.pos).round()
			var trail: Vector2 = Vector2(bit.velocity).normalized() * minf(14, Vector2(bit.velocity).length() * 0.035)
			if surface_material == "explosion":
				var ember := FIRE_HOT.lerp(FIRE_ORANGE,smoothstep(.0,.35,1.0-opacity)).lerp(FIRE_RED,smoothstep(.45,1.0,1.0-opacity))
				hot_layer.draw_line(point - (trail * 0.5).round(), point, Color(ember, color.a * 0.5), 1)
				hot_layer.draw_rect(Rect2(point, Vector2(2,2)), Color(ember,color.a))
				continue
			hot_layer.draw_line(point - trail.round(), point, Color(color, color.a * 0.36), 3)
			hot_layer.draw_line(point - (trail * 0.65).round(), point, color, 1)
			hot_layer.draw_rect(Rect2(point, Vector2(2,2)), Color("fff3d3") if surface_material not in ["glass","arc"] else Color("dffcff"))
	func _draw_glow() -> void:
		if retired or _preset.is_empty(): return
		var hot: Color = _preset.hot
		if surface_material == "explosion":
			var reach := 27.0*sqrt(power)
			var flash := maxf(0.0,1.0-age/.07)
			if flash > 0.0:
				PixelArt.blob(glow_layer,direction*reach*.3,reach*2.1,Color(FIRE_ORANGE,.26*flash),seed_value)
				PixelArt.blob(glow_layer,direction*reach*.3,reach*1.25,Color(FIRE_HOT,.70*flash),seed_value+1)
			var burn := maxf(0.0,1.0-age/.46)
			if burn > 0.0:
				PixelArt.blob(glow_layer,direction*reach*.45+Vector2(0,-age*26.0),reach*(1.5+age*1.6),Color(FIRE_ORANGE,.15*burn*burn),seed_value+2)
			PixelArt.shockwave(glow_layer,Vector2.ZERO,5+age*170*sqrt(power),Color(hot,maxf(0.0,1.0-age/.15)*.32),seed_value)
		else:
			var radius: float = float(_preset.flash)*sqrt(power)
			var fade := maxf(0.0,1.0-age/.15)
			if radius > 0.0 and fade > 0.0: PixelArt.glow(glow_layer,Vector2.ZERO,radius,Color(hot,.20*fade),seed_value)

class Stage extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-2000,-1200,4000,1200),Color("6f8fae"))
		draw_rect(Rect2(-2000,0,4000,800),Color("2a2b27"))
		draw_rect(Rect2(-2000,0,4000,3),Color("c9d3d6"))

func _initialize() -> void:
	run.call_deferred()

func _argument(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return fallback

## --bench: the same load drawn by either path (36 bursts: explosions, metal
## and concrete impacts re-fired as they expire), mean frame time over 4 s.
func bench(stage: Node2D, legacy: bool) -> Dictionary:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var kinds := ["explosion", "metal", "concrete"]
	var live: Array = []
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in 300:
		live = live.filter(func(burst): return is_instance_valid(burst) and not burst.retired)
		var index := 0
		while live.size() < 36:
			var burst: ImpactBurst = (LegacyBurst.new() if legacy else ImpactBurst.new())
			burst.surface_material = kinds[(frame + index) % 3]
			burst.position = Vector2(-600 + ((frame * 7 + index * 53) % 1200), -1)
			burst.direction = Vector2.UP
			burst.power = 1.4
			burst.seed_value = 100 + frame * 37 + index
			stage.add_child(burst)
			live.append(burst)
			index += 1
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if frame >= 60: samples.append(float(now - previous) / 1000.0)
		previous = now
	for burst in live:
		if is_instance_valid(burst): burst.queue_free()
	await process_frame
	var total := 0.0
	for sample in samples: total += sample
	return {"path": "legacy" if legacy else "grid", "frames": samples.size(), "mean_ms": snappedf(total / samples.size(), .001)}

func run() -> void:
	output = _argument("--out=", output)
	pixel_scale = float(_argument("--scale=", "2"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1920, 1080)
	await process_frame
	var stage := Stage.new()
	root.add_child(stage)
	var camera := Camera2D.new()
	stage.add_child(camera)
	camera.zoom = PixelGrid.zoom_for(pixel_scale, root)
	camera.position = PixelGrid.snap_center(Vector2(0, -60), camera.zoom, root)
	camera.make_current()
	var floor_body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(4000, 40)
	shape.shape = box
	shape.position = Vector2(0, 20)
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	if "--bench" in OS.get_cmdline_user_args():
		var results: Array = []
		for legacy: bool in [true, false, true, false]:
			results.append(await bench(stage, legacy))
		print("PIXEL GRID EFFECTS BENCH ", RenderingServer.get_video_adapter_name(), " ", JSON.stringify(results))
		quit(0)
		return
	for kind: String in ["explosion", "metal", "concrete"]:
		var bursts: Array = []
		for side in 2:
			var burst: ImpactBurst = (LegacyBurst.new() if side == 0 else ImpactBurst.new())
			burst.surface_material = kind
			burst.position = Vector2(-150 if side == 0 else 150, -1)
			burst.direction = Vector2.UP
			burst.power = 1.4
			burst.seed_value = 4242
			stage.add_child(burst)
			bursts.append(burst)
		var shown := 0
		while shown < AGES.size():
			await physics_frame
			if bursts[0].age >= float(AGES[shown]) or not is_instance_valid(bursts[0]) or bursts[0].retired:
				await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				image.save_png(ProjectSettings.globalize_path(output) + "/%s_%02d.png" % [kind, shown])
				shown += 1
				if not is_instance_valid(bursts[0]) or bursts[0].retired: break
		for burst in bursts:
			if is_instance_valid(burst): burst.queue_free()
		await process_frame
	print("PIXEL GRID EFFECTS: captured into ", ProjectSettings.globalize_path(output))
	quit(0)
