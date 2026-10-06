extends SceneTree
## Real item transfers and paid production, with optional separately packaged
## extension fixture. This script never registers or mutates runtime catalogs.
const Registry := preload("res://scripts/content_registry.gd")
const Messages := preload("res://scripts/network_messages.gd")
const Schema := preload("res://scripts/network_replication_schema.gd")
const World := preload("res://scripts/network_world.gd")
const Storage := preload("res://scripts/medic_storage.gd")
const COPPER := "beta.fixture:copper"
const PLAN := "beta.fixture:copper_kit"
var checks := 0
var failures := 0
var game: Node
var player: Node

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("ITEM CATALOG %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)
func frames(count: int = 3) -> void:
	for _index in count: await process_frame
func scene() -> Node:
	var world: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	world.start_scenario(2,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	world.rounds.set_process(false)
	world.medic.set_physics_process(false)
	for worker in world.players: worker.set_physics_process(false)
	return world
func command(recipe_ref: Variant) -> Dictionary:
	return {"kind":"command","generation":1,"command":"craft","args":{"action":"supply","recipe":recipe_ref}}
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless" or "--capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/item-crafting-captures")
	root.get_texture().get_image().save_png("res://artifacts/item-crafting-captures/"+name+".png")
func forged_orders(bench: Node) -> void:
	var old := {"selection":{1:0},"orders":{"1:0":{"materials":{"steel":1},"remaining":1.4,"working":true,"ready":false,"owner":1,"recipe":0,"transfer":0.0}},"elapsed":1.0}
	check(Schema.valid_state("field_workshop",old),"Historic paid numeric order stays valid without a recipe_id")
	for patch in [{"recipe":999},{"recipe_id":"unknown:plan"},{"recipe_id":"armor_1"},{"owner":2},{"materials":{"steel":3}},{"materials":{"unknown:item":1}},{"working":true,"ready":true},{"remaining":-1.0},{"transfer":1.0}]:
		var bad: Dictionary = old.duplicate(true)
		bad.orders["1:0"].merge(patch,true)
		check(not Schema.valid_state("field_workshop",bad),"Malformed paid order rejected before mutation: "+str(patch))
	bench.orders = old.orders.duplicate(true)
	check(bench.order_view(player,0).materials.steel==1,"Legacy owner:index key still resolves to the original jaw trap")
	bench.orders.clear()
func run() -> void:
	check(Registry.diagnostics().is_empty(),"Loaded content has no missing references or invalid definitions: "+str(Registry.diagnostics()))
	if not Registry.diagnostics().is_empty():
		quit(1)
		return
	check(ItemCatalog.contains("concrete") and not ItemCatalog.contains("unregistered:item"),"Items resolve by stable registered identity")
	check(Balance.RESOURCE_NAMES==ItemCatalog.names() and Balance.RESOURCE_COLORS==ItemCatalog.colors(),"Compatibility names/colors share the item catalog")
	check(Balance.RESOURCE_NAMES.is_read_only() and CraftingCatalog.recipes().is_read_only() and CraftingCatalog.recipe(0).cost.is_read_only(),"Caller access cannot mutate authoritative definitions")
	check(CraftingCatalog.id(0)=="jaw_trap" and CraftingCatalog.id(4)=="sentry_kit" and CraftingCatalog.index("armor_1")==2,"Five historic recipe indices preserve their stable identities")
	check(Balance.RECIPES.size()==5 and Balance.RECIPES.mixer.output=="concrete" and Balance.RECIPES.furnace.alternates.scrap=="ore","Machine recipes preserve exact outputs and scrap replacement")
	check(ItemCatalog.data("concrete").art.region!=ItemCatalog.data("steel").art.region and ItemCatalog.data("concrete").art.has("pour_region") and not ItemCatalog.data("steel").art.has("pour_region"),"Bucket and stacked steel have distinct art; only concrete can pour")
	check(float(ItemCatalog.data("concrete").art.world_width)==21.0,"Grounded bucket keeps its original compact size and authored container identity")
	check(ItemCatalog.data("scrap").art.texture=="res://assets/loot/salvage_atlas.png" and ItemCatalog.region(ItemCatalog.data("scrap").art.region)==PickupArt.SALVAGE_REGIONS[0],"Carried scrap uses the same authored salvage heap as grounded drops and inventory icons")
	var reads := Registry.read_count()
	for _index in 20:
		ItemCatalog.names()
		ItemCatalog.ordered()
		CraftingCatalog.recipe(0)
	check(Registry.read_count()==reads,"Repeated runtime catalog access does not read JSON again")
	check(Messages.valid(command("armor_1"),true) and Messages.valid(command(2),true),"Commands accept stable IDs and original numeric references")
	for invalid in ["unknown:recipe",-1,999,0.5,true,null]: check(not Messages.valid(command(invalid),true),"Unknown or ambiguous command reference rejected: "+str(invalid))
	game = scene()
	player = game.players[0]
	var bench: Node = game.workshop
	check(player.add_item("unregistered:item",1)==0 and player.inventory.is_empty(),"Actual inventory refuses undefined items rather than creating invisible cargo")
	check(await preload("res://tests/scenario_excavation_fixture.gd").clear_field(game,0,player),"Actual first floor is excavated for the recipe test")
	bench.refresh_access()
	player.position = bench.position+Vector2(8,0)
	player.inventory = {}
	forged_orders(bench)
	if "--extension-fixture" in OS.get_cmdline_user_args(): await extension(bench)
	else:
		check(CraftingCatalog.recipes().size()==5 and not ItemCatalog.contains(COPPER),"Default game retains its five recipes and has no fixture content")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("ITEM CATALOG: %d/%d passed" % [checks-failures,checks])
	quit(0 if failures==0 else 1)
func extension(bench: Node) -> void:
	check(ItemCatalog.contains(COPPER) and CraftingCatalog.index(PLAN)==5,"Pack adds a sixth recipe and a genuinely new item")
	if not ItemCatalog.contains(COPPER) or CraftingCatalog.index(PLAN)!=5: return
	check(Storage.MATERIALS.has(COPPER) and CampaignCatalog.CARGO_KINDS.has(COPPER),"Explicit storage/cargo item flags reach their real consumers")
	player.inventory = {COPPER:1,"steel":1}
	player.selected_kind = "steel"
	player.cycle_material()
	check(player.selected_material()==COPPER,"Actual worker inventory cycles to a newly registered material")
	player.position = Vector2(game.scenario_bunker.room_right+160,430)
	await physics_frame
	check(player._drop_material_kind(COPPER,1),"Actual drop command places the new item after a finite inventory debit")
	await frames()
	var dropped: Node
	for pickup in get_nodes_in_group("pickups"):
		if pickup.game==game and pickup.kind==COPPER: dropped=pickup
	check(is_instance_valid(dropped) and dropped.amount==1 and not player.inventory.has(COPPER),"Ground pickup retains exact registered identity and quantity")
	if is_instance_valid(dropped):
		dropped.interact(player,Balance.TRANSFER_TIME)
		check(player.inventory.get(COPPER,0)==1,"Real pickup interaction restores the same new item")
	player.position = bench.position+Vector2(8,0)
	var crate: Node = load("res://scripts/convoy_supply.gd").new()
	crate.game = game
	crate.position = player.position+Vector2(-24,0)
	crate.kind = COPPER
	crate.amount = 0
	game.add_child(crate)
	await physics_frame
	player.selected_kind = COPPER
	crate.deposit(player,Balance.TRANSFER_TIME)
	check(crate.amount==1 and not player.inventory.has(COPPER),"Real storage deposits the registered item without duplication")
	crate.interact(player,Balance.TRANSFER_TIME)
	check(crate.amount==0 and player.inventory.get(COPPER,0)==1,"Real storage withdraws the same item")
	crate.queue_free()
	await frames()
	player.inventory = {"steel":1,"scrap":1}
	check(game.hud.open_crafting(player,bench),"Extended catalog opens through the production menu")
	var panel: Control = game.hud.crafting_panel
	if not is_instance_valid(panel): return
	await frames()
	check(panel.recipe_buttons.size()==CraftingCatalog.recipes().size() and panel.recipe_buttons.size()>=6,"Menu creates every registered recipe picture")
	panel.recipe_buttons[5].grab_focus()
	await frames()
	var button: Button = panel.recipe_buttons[5]
	var picture_rect := Rect2(button.global_position,button.size)
	var strip_rect := Rect2(panel.recipe_scroll.global_position,panel.recipe_scroll.size)
	check(panel.selected_index==5 and panel.recipe_scroll.scroll_horizontal>0 and strip_rect.encloses(picture_rect),"Controller focus scrolls the sixth picture fully into view")
	await capture("sixth-recipe")
	panel.confirm_button.pressed.emit()
	check(bench.order_view(player,5).working and player.inventory.is_empty() and bench.orders.has("1:"+PLAN),"Explicit confirmation creates a paid stable-ID work order")
	var authority := World.new()
	authority.bind(game)
	var snapshot := authority.capture()
	check(authority._validate(snapshot),"Real world snapshot includes new recipe/item definitions")
	var guest := scene()
	var replica := World.new()
	replica.bind(guest)
	replica.client = true
	check(replica.apply(snapshot) and guest.workshop.order_view(guest.players[0],5).get("recipe_id")==PLAN,"Guest applies the extended paid order with the same stable identity")
	await preload("res://tests/scene_cleanup.gd").free_scene(guest,self)
	current_scene = game
	bench._process(0.3)
	player.inventory = {"sand":5}
	check(not bench.request(player,"collect",PLAN) and bench.order_view(player,5).ready and player.inventory.sand==5,"Two-item output waits for full capacity without partial credits")
	player.inventory.clear()
	check(bench.request(player,"collect",PLAN) and player.inventory.get(COPPER,0)==2 and not bench.order_view(player,5).ready,"Collection delivers the complete finite output once")
	check(not bench.request(player,"collect",PLAN) and player.inventory.get(COPPER,0)==2,"Repeated collection cannot duplicate the output")
	game.hud.close_crafting()
	var other: Node = game.players[1]
	other.position = bench.position+Vector2(-8,0)
	other.inventory = {"steel":1,"scrap":1}
	game.network._handle_command("craft",{"action":"supply","recipe":PLAN},2)
	check(bench.order_view(other,5).working and other.inventory.is_empty() and player.inventory.get(COPPER,0)==2,"Stable-ID network command debits only its authenticated worker")
	check(Messages.valid(command(PLAN),true) and Messages.valid(command(5),true),"Sixth recipe is valid through ID and bounded legacy-index compatibility")
	var valid_order := {"selection":bench.selection.duplicate(),"orders":bench.orders.duplicate(true),"elapsed":bench.elapsed}
	check(Schema.valid_state("field_workshop",valid_order),"Extended authoritative workshop state passes semantic validation")
	var numeric_legacy: Dictionary = valid_order.duplicate(true)
	numeric_legacy.orders["2:5"] = numeric_legacy.orders["2:"+PLAN]
	numeric_legacy.orders.erase("2:"+PLAN)
	check(Schema.valid_state("field_workshop",numeric_legacy),"Explicit matching recipe ID permits an older numeric extension key")
	bench.orders = numeric_legacy.orders
	check(bench.order_view(other,5).get("recipe_id")==PLAN and bench.order_for(other,5).working and not bench.orders.has("2:"+PLAN),"Reading compatible numeric extension orders cannot create an empty duplicate")
	bench.orders = valid_order.orders
	var wrong: Dictionary = valid_order.duplicate(true)
	wrong.orders["2:"+PLAN].recipe_id = "jaw_trap"
	check(not Schema.valid_state("field_workshop",wrong),"Mismatched stable ID and index are rejected")
	var large_index := CraftingCatalog.index("beta.fixture:large_plan")
	if large_index>=0:
		check(game.hud.open_crafting(player,bench),"Long authored recipe opens through the same menu")
		panel = game.hud.crafting_panel
		await frames()
		panel._select(large_index)
		await frames()
		var detail_bar: VScrollBar = panel.detail_scroll.get_v_scroll_bar()
		check(detail_bar.is_visible_in_tree() and detail_bar.focus_mode==Control.FOCUS_ALL and panel.detail_canvas.custom_minimum_size.y>panel.detail_scroll.size.y,"Long descriptions and cost lists scroll inside the fixed detail area")
		var down := InputEventAction.new()
		down.action = "ui_down"
		down.pressed = true
		root.push_input(down,true)
		await frames()
		check(root.gui_get_focus_owner()==detail_bar,"Controller can enter the recipe detail scrollbar")
		detail_bar.value = detail_bar.max_value
		await frames()
		check(panel.detail_scroll.scroll_vertical>0,"Material rows at the end of long recipes remain reachable")
		await capture("long-recipe-details")
		game.hud.close_crafting()
