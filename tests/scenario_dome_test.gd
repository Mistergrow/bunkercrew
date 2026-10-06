extends SceneTree
## Repositions the paid, destructible dome on all three selectable sites.
## All tests use actual glass polygons and physics; no layer exemptions.
class RoundState extends Node:
	var wave:=16
	var phase:="build"
class Upgrades extends Node:
	func has_upgrade(_id): return true
class WorkerStub extends Node2D:
	var player_id:=1
	var inventory: Dictionary={}
	func can_act(): return true
	func take_item(kind,count):
		if int(inventory.get(kind,0))<count: return false
		inventory[kind]-=count
		if inventory[kind]==0: inventory.erase(kind)
		return true
	func selected_material(): return ""
class Core extends Node2D:
	var hp:=1000.0
	func take_damage(amount): hp-=amount
class World extends Node2D:
	var scenario_combat: ScenarioCombat
	var rounds: RoundState
	var upgrades: Upgrades
	var dome: DomeController
	var flak_station: FlakStation
	var core: Core
	var ladders: Array[Rect2]=[]
	var floor_levels: Array[float]=[245,430]
	var players: Array=[]
	func sound(_id): pass
	func notify(_text): pass
	func impact(_at,_kind,_normal=Vector2.UP,_power=1.0): pass
	func fx(_at,_color,_count): pass
	func spawn_pickup(_kind,_amount,_at): pass
	func add_terrain(rect: Rect2):
		var body:=StaticBody2D.new()
		body.collision_layer=1
		var collision:=CollisionShape2D.new()
		var box:=RectangleShape2D.new()
		box.size=rect.size
		collision.shape=box
		body.position=rect.get_center()
		body.add_child(collision)
		add_child(body)
		return body
var checks:=0
var failures:=0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if ok: print("PASS ",label)
	else:
		failures+=1
		push_error(label)
func frames(count:=3):
	for frame in count:
		await physics_frame
		await process_frame
func ray(world: Node2D,from: Vector2,to: Vector2) -> Dictionary:
	return world.get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(from,to,2))
func run():
	InputSetup.install()
	for mode: String in ["left","center","right"]:
		var left: float={"left":90.0,"center":400.0,"right":710.0}[mode]
		var world:=World.new()
		root.add_child(world)
		world.scenario_combat=ScenarioCombat.new()
		world.scenario_combat.configure(mode,-250,1690,430,left,left+640,left+320)
		world.rounds=RoundState.new(); world.add_child(world.rounds)
		world.upgrades=Upgrades.new(); world.add_child(world.upgrades)
		world.core=Core.new(); world.core.position=Vector2(left+320,430); world.add_child(world.core)
		var worker:=WorkerStub.new(); world.add_child(worker)
		world.flak_station=FlakStation.new()
		world.flak_station.game=world
		world.flak_station.position=Vector2(left+130,245)
		world.flak_station.gun_position=Vector2(left+224,35)
		world.flak_station.platform=Rect2(left+168,35,112,12)
		world.flak_station.access=Rect2(left+202,-5,44,435)
		world.add_child(world.flak_station)
		world.dome=DomeController.new()
		world.dome.game=world
		world.dome.configure_for_scenario(left,left+640,left+224)
		world.add_child(world.dome)
		var dome:=world.dome
		dome.unlock()
		check(dome.segments.size()==14 and dome.fronts.size()==2,"%s has one continuous twelve-panel roof and both ground fronts"%mode)
		check(dome.roof_center==Vector2(left+320,245) and dome.roof_radii==Vector2(410,190),"%s dome is centered around the whole relocated bunker"%mode)
		check(dome.site==Vector2(left+428,430),"%s shelter controls occupy their own service bay clear of the furnace"%mode)
		worker.inventory=DomeController.COST.duplicate()
		for transfer in 20: dome.interact(worker,Balance.TRANSFER_TIME)
		dome.interact(worker,DomeController.FRAME_TIME)
		for transfer in 12: dome.interact(worker,Balance.TRANSFER_TIME)
		dome.interact(worker,DomeController.GLAZE_TIME)
		await frames()
		check(dome.built and worker.inventory.is_empty(),"%s dome consumes exact existing steel, alloy and glass recipe"%mode)
		for front in dome.fronts:
			var x: float=front.global_position.x
			check(not ray(world,Vector2(x-20,410),Vector2(x+20,410)).is_empty(),"%s front at%s has real lower glass"%[mode,x])
			check(ray(world,Vector2(x-20,350),Vector2(x+20,350)).is_empty(),"%s front at%s has a real open firing window"%[mode,x])
			check(is_equal_approx(front.to_global(front.start).y,245) and is_equal_approx(front.to_global(front.finish).y,430),"%s front at%s meets curved roof and ground without burying glass"%[mode,x])
		var flak_x:=left+224
		check(not ray(world,Vector2(flak_x,0),Vector2(flak_x,150)).is_empty(),"%s unbuilt flak leaves actual roof sealed"%mode)
		world.flak_station.unlock()
		worker.inventory={"steel":3,"concrete":2,"ammo":1}
		for transfer in 6: world.flak_station.interact(worker,Balance.TRANSFER_TIME)
		world.flak_station.interact(worker,2.5)
		await frames(5)
		check(world.flak_station.built and dome.flak_port_active and worker.inventory.is_empty(),"%s paid relocated flak opens dome service aperture"%mode)
		var inside_port:=ray(world,Vector2(flak_x,49),Vector2(flak_x,150))
		check(inside_port.is_empty(),"%s dynamic aperture uses relocated tower position, not legacy x530"%mode)
		check(not ray(world,Vector2(flak_x-72,0),Vector2(flak_x-72,200)).is_empty() and not ray(world,Vector2(flak_x+72,0),Vector2(flak_x+72,200)).is_empty(),"%s real glass remains on both sides of the tower"%mode)
		var simple:=true
		for panel in dome.segments:
			for polygon in panel.polygons: simple=simple and not Geometry2D.triangulate_polygon(polygon).is_empty()
		check(simple,"%s clipped roof polygons remain drawable and physical"%mode)
		for front in dome.fronts:
			var direction: float=1.0 if front.global_position.x<world.core.position.x else -1.0
			var enemy:=SiegeMachine.new()
			enemy.game=world; enemy.attack_direction=direction
			enemy.position=Vector2(front.position.x-direction*63,430)
			world.add_child(enemy); enemy.set_physics_process(false)
			enemy.target=enemy.nearest_obstacle()
			await frames()
			var before: float=front.hp
			check(enemy.target==front and enemy.attack_obstacle() and front.hp<before,"%s ground approach%s damages its actual glass front"%[mode,direction])
			enemy.free()
		var west: DomeSegment=dome.fronts[0]
		west.take_damage(9999)
		await frames()
		check(not west.is_blocking() and ray(world,Vector2(west.position.x-20,410),Vector2(west.position.x+20,410)).is_empty(),"%s destroyed western front opens actual ground collision"%mode)
		worker.inventory={"glass":1}
		dome.interact(worker,DomeController.REPAIR_TIME)
		await frames()
		check(west.hp==DomeController.REPAIR_HP and worker.inventory.is_empty() and not ray(world,Vector2(west.position.x-20,410),Vector2(west.position.x+20,410)).is_empty(),"%s one physical glass repairs western front and restores collision"%mode)
		await preload("res://tests/scene_cleanup.gd").free_scene(world,self)
	print("SCENARIO DOME: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
