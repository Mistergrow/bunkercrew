extends SceneTree
## The shared GPU pulse changes cached item drawing while its real origin,
## physical support, ownership and finite quantity remain fixed.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var view: SubViewport

class CountedPickup extends ResourcePickup:
	var draw_count := 0
	func _draw() -> void:
		draw_count += 1
		super._draw()

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func frames(count: int = 3) -> void:
	for _index in count: await process_frame
func opaque_bounds(picture: Image) -> Rect2i:
	var result := Rect2i()
	var found := false
	for y in picture.get_height():
		for x in picture.get_width():
			if picture.get_pixel(x,y).a<0.7: continue
			if not found:
				result=Rect2i(x,y,1,1)
				found=true
			else: result=result.expand(Vector2i(x,y))
	return result
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var native := DisplayServer.get_name()!="headless" and "--capture" in OS.get_cmdline_user_args()
	var world := Node2D.new()
	if native:
		root.size = Vector2i(320,180)
		root.position = Vector2i(2000,80)
		root.set_flag(Window.FLAG_NO_FOCUS,true)
		view=SubViewport.new()
		view.world_2d=World2D.new()
		view.size=Vector2i(320,192)
		view.transparent_bg=true
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		view.add_child(world)
	else: root.add_child(world)
	var pile := CountedPickup.new()
	pile.kind="concrete"
	pile.amount=1
	pile.position=Vector2(160,162)
	pile.scale=Vector2.ONE*6 if native else Vector2.ONE
	world.add_child(pile)
	pile.set_physics_process(false)
	var other := ResourcePickup.new()
	other.kind="steel"
	other.position=Vector2(500,162)
	world.add_child(other)
	other.set_physics_process(false)
	check(pile.material==other.material and pile.material==PickupArt.cutout_material(),"All actual floor items share one pulse/cutout material")
	check(not pile.is_processing() and not other.is_processing(),"Ordinary items retain no per-frame process or redraw callback")
	check(ItemCatalog.data("concrete").art.world_width==21,"A dropped bucket retains its original compact base width")
	var initial_position := pile.position
	var initial_amount := pile.amount
	await frames(5)
	var initial_draws := pile.draw_count
	if native:
		DirAccess.make_dir_recursive_absolute("res://artifacts/pickup-pulse")
		var changed := false
		var first: Image = null
		var smallest := 1000000
		var largest := 0
		for index in 13:
			await RenderingServer.frame_post_draw
			var picture:=view.get_texture().get_image()
			var bounds:=opaque_bounds(picture)
			check(bounds.size!=Vector2i.ZERO and bounds.end.y<=163,"The visible bucket stays above its unchanged local ground contact")
			smallest=mini(smallest,bounds.size.x)
			largest=maxi(largest,bounds.size.x)
			if first==null: first=picture
			else: changed=changed or first.get_data()!=picture.get_data()
			check(picture.save_png("res://artifacts/pickup-pulse/%02d.png"%index)==OK,"Native pulse frame captured")
			await create_timer(0.24).timeout
		check(changed and largest>smallest,"The native GPU pulse is visible while cached draw commands remain unchanged")
		check(largest-smallest<=10 and largest<=134,"Six-times diagnostic view confirms the pulse stays within three percent plus raster rounding")
		check(pile.draw_count==initial_draws,"Three seconds of visible pulse require no extra item draw callbacks")
	else: await frames(12)
	check(pile.position==initial_position and pile.amount==initial_amount and pile.fall_speed==0.0,"Visual pulse never changes pickup origin, physical state or finite quantity")
	check(pile.elapsed==0.0 and pile.draw_count==initial_draws,"The pulse adds no changing gameplay/snapshot animation clock")
	check(await Cleanup.free_scene(world,self),"Pulse fixtures release cleanly")
	if is_instance_valid(view):
		view.queue_free()
		await process_frame
	print("PICKUP PULSE: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
