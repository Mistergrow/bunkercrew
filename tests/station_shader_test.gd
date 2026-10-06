extends SceneTree
## Actual production scene pixels: local shading may change surface color only.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Effects := preload("res://scripts/station_shader_effects.gd")
const PATHS := ["res://scenes/station.tscn", "res://scenes/glass_furnace.tscn", "res://scenes/alloy_furnace.tscn", "res://scenes/ammo_press.tscn"]

class WeatherStub extends Node:
	var reduced_effects := false

class Fixture extends Node2D:
	var weather: WeatherStub
	func sound(_kind): pass
	func fx(_position, _color, _count): pass

var checks := 0
var failures := 0
var viewport: SubViewport

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("STATION SHADER %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
		push_error(label)

func capture() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	return pixels

func changed(first: Image, second: Image, bounds: Rect2i) -> int:
	var count := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				count += 1
	return count

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Station shader validation needs a graphical renderer")
		quit(1)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(240, 220)
	viewport.world_2d = World2D.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var fixture := Fixture.new()
	viewport.add_child(fixture)
	fixture.weather = WeatherStub.new()
	fixture.add_child(fixture.weather)
	var directory := "res://artifacts/station-shaders"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for path in PATHS:
		var machine = load(path).instantiate()
		if path.ends_with("/station.tscn"):
			machine.kind = "furnace"
		machine.position = Vector2(120, 200)
		machine.game = fixture
		fixture.add_child(machine)
		machine.set_process(false)
		machine.working = true
		machine.elapsed = 2.4
		machine.production_time = machine.duration() * 0.4
		var effects = machine.get_node("MaterialEffects")
		await capture()
		check(effects.on_screen, "%s activates only after its real canvas notifier enters view" % machine.kind)
		effects.set_process(false)
		machine.material = null
		machine.queue_redraw()
		var original := await capture()
		effects._refresh()
		var shaded := await capture()
		check(machine.material.shader == Effects.SURFACE_SHADER, "%s shares the same compiled surface shader" % machine.kind)
		var alpha_same := true
		for y in viewport.size.y:
			for x in viewport.size.x:
				if original.get_pixel(x, y).a != shaded.get_pixel(x, y).a:
					alpha_same = false
		check(alpha_same, "%s keeps every alpha pixel and silhouette unchanged" % machine.kind)
		check(changed(original, shaded, Rect2i(0, 0, 240, 80)) == 0, "%s preserves labels and progress bars" % machine.kind)
		check(changed(original, shaded, Rect2i(0, 195, 240, 25)) == 0, "%s cannot light its ground shadow or output tray" % machine.kind)
		var changes := changed(original, shaded, Rect2i(0, 80, 240, 115))
		check(changes > (20 if machine.kind == "ammo_press" else 200), "%s visibly lights existing machine surfaces (%d pixels)" % [machine.kind, changes])
		if machine.kind != "ammo_press":
			var chamber: Vector4 = Effects.SETTINGS[machine.kind].chamber
			check(changed(original, shaded, Rect2i(int(chamber.x) + 120, int(chamber.y) + 200, int(chamber.z), int(chamber.w))) == 0, "%s retains all authored flame/arc pixels inside its chamber" % machine.kind)
		original.save_png(directory + "/%s-before.png" % machine.kind)
		shaded.save_png(directory + "/%s-after.png" % machine.kind)
		var updates: int = effects.uniform_updates
		for frame in 60:
			effects._refresh()
		check(effects.uniform_updates == updates, "%s avoids repeat GPU uniform uploads for an unchanged animation tick" % machine.kind)
		machine.elapsed = 3.1
		effects._refresh()
		var later := await capture()
		check(changed(shaded, later, Rect2i(0, 80, 240, 115)) > 5, "%s material light animates while source drawing remains fixed" % machine.kind)
		effects.set_process(true)
		machine.set_process(true)
		await process_frame
		paused = true
		var frozen := await capture()
		var frozen_clock: float = machine.elapsed
		await create_timer(0.06, true).timeout
		var still := await capture()
		check(machine.elapsed == frozen_clock and frozen.get_data() == still.get_data(), "%s clock and rendered pixels freeze during pause" % machine.kind)
		paused = false
		machine.set_process(false)
		effects.set_process(false)
		fixture.weather.reduced_effects = true
		effects._refresh()
		check(machine.material == null, "%s removes the extra material pass entirely with F3" % machine.kind)
		fixture.weather.reduced_effects = false
		machine.working = false
		machine.output_amount = 0
		effects._refresh()
		check(machine.material == null, "%s idle state uses the original material" % machine.kind)
		machine.output_amount = 2
		effects._refresh()
		check(machine.material == null, "%s completed stock does not emit production light" % machine.kind)
		machine.output_amount = 0
		machine.binder = 0
		effects._refresh()
		check(machine.material == null, "%s inactive resource-depleted state stays unlit" % machine.kind)
		machine.working = true
		machine.position.x = 1000
		effects.set_process(true)
		await capture()
		await capture()
		updates = effects.uniform_updates
		await create_timer(0.05).timeout
		check(not effects.on_screen and not effects.is_processing() and effects.uniform_updates == updates, "%s performs no shader updates when offscreen" % machine.kind)
		check(await Cleanup.free_scene(machine, self), "%s releases its notifier and material cleanly" % path.get_file())
	check(await Cleanup.free_scene(viewport, self), "Renderer fixture releases cleanly")
	print("STATION SHADERS: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
