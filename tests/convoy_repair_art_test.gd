extends SceneTree
## Cosmetic geometry must stay faithful to the actual axle/road without
## taking ownership of progress, fuel, crew or authoritative coordinates.
const VehicleArt := preload("res://scripts/convoy_vehicle_art.gd")
const Presentation := preload("res://scripts/convoy_presentation.gd")
var checks := 0
var failures := 0

class Seat extends Node2D:
	var occupant: Node2D

class Truck extends Node2D:
	var game: Node
	var facing := 1.0
	var velocity := Vector2.ZERO
	var suspension := 0.0
	var wheel_phase := 2.4
	var destroyed := false
	var seats: Array[Node2D] = []
	var visual: Node2D
	var journey_state: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func state(truck: Node2D, step: String, work: float, side: float=1.0) -> Dictionary:
	truck.facing=side
	truck.journey_state={"phase":"repair","repair_step":step,"repair_work":work,"repair_bolts":2 if step=="tighten" else 3 if step=="lower" else 0,"repair_cursor":.6,"repair_operator":0,"phase_time":2.15}
	var original: Dictionary=truck.journey_state.duplicate(true)
	var original_position: Vector2=truck.position
	var result := VehicleArt.repair_visual_state(truck)
	check(original==truck.journey_state and truck.position==original_position and truck.suspension==0 and truck.wheel_phase==2.4,"Cosmetic "+step+" sample leaves authority and wheel clock untouched")
	return result

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world:=Node2D.new()
	root.add_child(world)
	var truck:=Truck.new()
	truck.position=Vector2(1910,430)
	world.add_child(truck)
	truck.visual=Node2D.new()
	truck.add_child(truck.visual)
	for unused in 4:
		var seat:=Seat.new()
		truck.add_child(seat)
		truck.seats.append(seat)
	var presentation:=Presentation.new()
	truck.add_child(presentation)
	presentation.set_process(false)
	var details: Node2D=presentation.get_node("ServiceDetails")
	check(presentation.z_index<0 and presentation.z_index+details.z_index>truck.visual.z_index,"Light beams stay behind hull while actual timing/handle can render ahead of it")
	check(details.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"Foreground service layer retains native pixel sampling")
	var flat := state(truck,"jack",0)
	check(flat.active and flat.flat and not flat.loose and flat.lift==0,"Initial breakdown visibly collapses the mounted tyre before any tool input")
	var lifted := state(truck,"jack",1)
	check(lifted.lift==1 and lifted.hub_position.x==flat.hub_position.x and lifted.hub_position.y<flat.hub_position.y,"Pumping raises the cosmetic rear hub while preserving the authoritative axle x")
	var mounted := state(truck,"remove",0)
	var half_removed := state(truck,"remove",.5)
	var removed := state(truck,"remove",1)
	check(mounted.loose and mounted.flat and removed.flat,"Removal carries the deflated tyre away from the revealed hub")
	check(mounted.wheel_position==mounted.hub_position and mounted.hub_position==Vector2(-65,-15) and half_removed.wheel_position.x<mounted.wheel_position.x and removed.wheel_position.x<half_removed.wheel_position.x,"Removing the rear tyre has a finite continuous path from the raised cosmetic hub")
	check(removed.wheel_position.y+5==0 and removed.wheel_rotation==0,"Collapsed rubber ends on the local physical road plane, without rotation sinking its sidewall")
	var spare := state(truck,"fit",0)
	var fitted := state(truck,"fit",1)
	check(spare.loose and not spare.flat and spare.wheel_position.y+12==0,"The upright replacement rests on the actual road before lifting")
	check(spare.wheel_position.x==removed.wheel_position.x and fitted.wheel_position==mounted.wheel_position,"The spare uses the same handling station and returns exactly to the unchanged rear hub")
	for step in ["jack","remove","fit","tighten","lower"]:
		var right := state(truck,step,.55)
		var left := state(truck,step,.55,-1)
		check(is_equal_approx(right.wheel_position.x,-left.wheel_position.x) and right.wheel_position.y==left.wheel_position.y,"Mirrored "+step+" keeps ground contact and uses the same authoritative wheel anchor")
	var tightened := state(truck,"tighten",.55)
	check(tightened.bolts==2 and not tightened.flat and not tightened.loose,"Two completed real nuts retain a round mounted tyre and identify the remaining nut")
	var lower := state(truck,"lower",.65)
	check(is_equal_approx(float(lower.lift),.35) and lower.bolts==3,"Lowering retracts the jack only after all three actual bolts")
	for phase in ["garage","boarding","driving","reboarding","complete"]:
		truck.journey_state.phase=phase
		var hidden := VehicleArt.repair_visual_state(truck)
		check(not hidden.active and not hidden.flat and not hidden.loose,"Old repair fields leave no phantom tyre or service art during "+phase)
	truck.journey_state={}
	check(not VehicleArt.repair_visual_state(truck).active,"Legacy snapshots without a journey never display a fictitious panne")
	var children_before:=presentation.get_child_count()
	for unused in 100: presentation.update_state(.05)
	check(presentation.get_child_count()==children_before and presentation.get_node("ServiceDetails")==details,"Replica draws reuse exactly one foreground node instead of allocating service nodes each tick")
	var atlas:=Presentation.REPAIR_PARTS
	var atlas_rect:=Rect2(Vector2.ZERO,Vector2(atlas.get_width(),atlas.get_height()))
	var crops_valid:=true
	for region: Rect2 in Presentation.REPAIR_REGIONS.values(): crops_valid=crops_valid and atlas_rect.encloses(region)
	var jack: Rect2=Presentation.REPAIR_REGIONS.jack
	crops_valid=crops_valid and jack.encloses(Rect2(jack.position+Vector2(0,433),Vector2(365,81))) and jack.encloses(Rect2(jack.position+Vector2(76,146),Vector2(157,284)))
	check(crops_valid,"Existing immutable repair atlas and articulated jack crops stay fully in bounds")
	var service_atlas_rect:=Rect2(Vector2.ZERO,Vector2(VehicleArt.SERVICE_ATLAS.get_size()))
	var separate_regions:=true
	var service_regions: Array=VehicleArt.SERVICE_REGIONS.values()
	for index in service_regions.size():
		separate_regions=separate_regions and service_atlas_rect.encloses(service_regions[index])
		for other in range(index+1,service_regions.size()):
			separate_regions=separate_regions and not service_regions[index].intersects(service_regions[other])
	check(separate_regions,"Generated healthy, ruptured, flat tyre and exposed hub crops stay isolated and in bounds")
	world.free()
	await process_frame
	print("CONVOY REPAIR ART: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
