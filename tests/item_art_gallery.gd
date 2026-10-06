extends SceneTree
## Prepared real items, native render only. Authored compact item silhouettes
## share carrying and ground identity; the actual floor view includes GPU pulse.
var game: Node
var captures: Array = []

class IdentityStrip extends Control:
	const ATLAS := preload("res://assets/workers/material_props.png")
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw() -> void:
		UiArt.plate(self,Rect2(200,140,1040,600))
		UiArt.text(self,Vector2(235,188),"Shared carry / drop identity",26)
		UiArt.text(self,Vector2(235,222),"Original authored item sprites; prepared native render at 3x scale.",15,UiArt.MUTED)
		var kinds := ["sand","ore","steel","scrap","concrete"]
		for index in kinds.size():
			var x := 300.0+index*200.0
			UiArt.centered(self,Vector2(x,271),ItemCatalog.names()[kinds[index]],21)
			draw_set_transform(Vector2(x,345),0,Vector2.ONE*3)
			WorkerPoseArt._draw_cargo(self,Vector2.ZERO,kinds[index])
			draw_set_transform(Vector2.ZERO)
			UiArt.centered(self,Vector2(x,402),"Carry",15,UiArt.MUTED)
			draw_set_transform(Vector2(x,531),0,Vector2.ONE*3)
			PickupArt.draw_world(self,kinds[index],0)
			draw_set_transform(Vector2.ZERO)
			UiArt.centered(self,Vector2(x,562),"Ground drop",15,UiArt.MUTED)
		UiArt.text(self,Vector2(235,609),"Concrete bucket: original compact size",20)
		draw_texture_rect_region(ATLAS,Rect2(595,651,63,69),Rect2(74,0,21,23))
		UiArt.text(self,Vector2(565,620),"Authored: 21 px",14,UiArt.MUTED)
		draw_set_transform(Vector2(880,720),0,Vector2.ONE*3)
		PickupArt.draw_world(self,"concrete",0)
		draw_set_transform(Vector2.ZERO)
		UiArt.text(self,Vector2(826,620),"World base: 21 px",14,UiArt.AMBER)

func _initialize() -> void: run.call_deferred()
func frames(count: int = 3) -> void:
	for _index in count: await process_frame
func capture(name: String,state: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://artifacts/item-art-captures/"+name+".png")
	captures.append({"name":name,"width":image.get_width(),"height":image.get_height(),"prepared_state":state})
func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("This gallery requires actual rendering")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1920,1080))
	DisplayServer.window_set_position(Vector2i(2000,80))
	DirAccess.make_dir_recursive_absolute("res://artifacts/item-art-captures")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	game.set_process(false)
	var player: Node = game.players[0]
	player.set_physics_process(false)
	player.inventory = {"sand":1,"ore":1,"steel":1,"scrap":1,"concrete":1}
	player.position = Vector2(game.scenario_bunker.room_right+320,430)
	await frames()
	var drops: Array = []
	for kind: String in ["sand","ore","steel","scrap","concrete"]:
		player.position.x = game.scenario_bunker.room_right+140+drops.size()*90
		player.selected_kind = kind
		await physics_frame
		if not player._drop_material_kind(kind,1):
			push_error("Actual drop failed: "+kind)
			await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
			quit(1)
			return
		drops.append(kind)
		await frames()
	await create_timer(0.7).timeout
	player.inventory = {"concrete":1}
	player.selected_kind = "concrete"
	player.drop_animation = 0.0
	player.position.x = game.scenario_bunker.room_right+65
	for pickup in get_nodes_in_group("pickups"):
		if pickup.game==game: pickup.set_physics_process(false)
	game.camera.set_process(false)
	game.camera.position_smoothing_enabled = false
	game.camera.position = Vector2(game.scenario_bunker.room_right+280,380)
	game.camera.zoom = Vector2.ONE*2.2
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	await frames(6)
	await capture("actual-ground-drops",{"scene":"ash_foundry","camera_zoom":2.2,"drops":drops,"inventory":player.inventory.duplicate(),"placement":"Five real Worker drop calls; finite inventory debit; pickups settled through actual physics; waves/AI held only for capture"})
	var layer := CanvasLayer.new()
	game.add_child(layer)
	var strip := IdentityStrip.new()
	layer.add_child(strip)
	await frames(6)
	await capture("carry-ground-identity",{"draw_scale":3,"authored_concrete_width":21,"current_concrete_width":21,"art":"Same original material_props.png source region and compact base size; actual carry and PickupArt drawing helpers"})
	var file := FileAccess.open("res://artifacts/item-art-captures/captures.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(captures,"\t"))
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	quit()
