extends SceneTree
## Actual workers/SAN conserve charges across ownership and scene retirement.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var fixtures: Node

func _initialize() -> void: run.call_deferred()

func check(ok: bool, detail: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(detail)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children(): freeze(child)

func reset(patient: Worker, helper: Node2D) -> void:
	patient.medical.interrupt()
	patient.hp=60.0
	patient.medical.state="wounded"
	patient.medical.bleeding=0
	patient.medical.fractured=false
	patient.medical.recovery_time=0.0
	if helper is Worker: helper.medical.charges=2
	else: helper.medical_supplies=2

func refused(patient: Worker, helper: Node2D, label: String) -> void:
	reset(patient,helper)
	var hands: Dictionary=patient.inventory.duplicate()
	var helper_hands: Dictionary=helper.inventory.duplicate() if helper is Worker else {}
	check(not patient.medical.reachable_can_aid(helper),label+": unreachable")
	check(not patient.medical.begin_or_continue_aid(helper,MedicalCatalog.TREAT_TIME),label+": treatment refused")
	check(patient.hp==60.0 and MedicalCatalog.charge_count(helper)==2,label+": HP and both finite charges unchanged")
	check(patient.inventory==hands and (not helper is Worker or helper.inventory==helper_hands),label+": crafting cargo unchanged")
	check(patient.medical.progress_for(helper)==0.0,label+": no latent treatment progress")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	fixtures=Node.new()
	root.add_child(fixtures)
	var game: Node=load("res://scenes/main.tscn").instantiate()
	fixtures.add_child(game)
	game.start(2)
	freeze(game)
	var patient: Worker=game.players[0]
	var owner: Worker=game.players[1]
	patient.position=Vector2(1000,430)
	owner.position=Vector2(964,430)
	patient.inventory={"steel":2}
	owner.inventory={"ore":3}
	var medic: FieldMedic=game.medic
	medic.position=owner.position
	medic.velocity=Vector2.ZERO
	medic.climbing=false
	var other_game: Node=load("res://scenes/main.tscn").instantiate()
	fixtures.add_child(other_game)
	other_game.start(1)
	freeze(other_game)
	var foreign: Worker=other_game.players[0]
	foreign.position=owner.position
	var view := SubViewport.new()
	view.world_2d=World2D.new()
	fixtures.add_child(view)
	var separate: Worker=load("res://scenes/player.tscn").instantiate()
	separate.game=game
	separate.player_id=3
	separate.position=owner.position
	view.add_child(separate)
	freeze(separate)
	for unused in 3: await physics_frame
	reset(patient,owner)
	check(patient.medical.reachable_can_aid(owner),"Actual local worker reaches patient")
	check(patient.medical.begin_or_continue_aid(owner,MedicalCatalog.TREAT_TIME),"Actual local worker completes ordinary treatment")
	check(patient.hp==95.0 and owner.medical.charges==1 and patient.inventory=={"steel":2} and owner.inventory=={"ore":3},"Local treatment heals35, spends one real charge and preserves cargo")
	reset(patient,medic)
	check(patient.medical.reachable_can_aid(medic),"Actual local SAN reaches patient")
	check(patient.medical.begin_or_continue_aid(medic,MedicalCatalog.TREAT_TIME),"Actual local SAN completes the shared treatment")
	check(patient.hp==95.0 and medic.medical_supplies==1 and patient.inventory=={"steel":2},"SAN treatment heals35 and spends one real medical supply")
	refused(patient,foreign,"Foreign Game in the same physics world")
	refused(patient,separate,"Spoofed Game reference in an independent World2D")
	game.remove_child(owner)
	refused(patient,owner,"Detached helper")
	game.add_child(owner)
	game.remove_child(patient)
	refused(patient,owner,"Detached patient")
	game.add_child(patient)
	patient.remove_child(patient.medical)
	refused(patient,owner,"Detached patient medical component")
	patient.add_child(patient.medical)
	# A genuine partial hold is cancelled when its actor changes ownership.
	reset(patient,owner)
	check(not patient.medical.begin_or_continue_aid(owner,0.4) and patient.medical.progress_for(owner)>0,"Native partial hold begins without spending a charge")
	owner.game=other_game
	patient.medical.tick(0.01)
	check(patient.medical.progress_for(owner)==0 and owner.medical.aid_target==null and owner.medical.charges==2,"Ownership change cancels a held channel and releases both actors without debit")
	owner.game=game
	reset(patient,owner)
	check(patient.medical.begin_or_continue_aid(owner,MedicalCatalog.TREAT_TIME) and patient.hp==95.0 and owner.medical.charges==1,"Valid treatment resumes after rejected ownership probes")
	reset(patient,owner)
	patient.medical.begin_or_continue_aid(owner,0.4)
	owner.queue_free()
	check(not patient.medical.begin_or_continue_aid(owner,MedicalCatalog.TREAT_TIME) and patient.medical.progress_for(owner)==0 and owner.medical.charges==2,"Queued helper cancels its existing hold without completing or spending")
	check(owner.medical.aid_target==null,"Retiring helper retains no patient pointer")
	refused(patient,owner,"Queued helper before end-of-frame retirement")
	var component_helper: Worker=load("res://scenes/player.tscn").instantiate()
	component_helper.game=game
	component_helper.player_id=3
	component_helper.position=owner.position
	game.add_child(component_helper)
	freeze(component_helper)
	component_helper.remove_child(component_helper.medical)
	refused(patient,component_helper,"Detached helper medical component")
	component_helper.add_child(component_helper.medical)
	reset(patient,component_helper)
	check(patient.medical.begin_or_continue_aid(component_helper,MedicalCatalog.TREAT_TIME) and patient.hp==95.0 and component_helper.medical.charges==1,"Reattached genuine helper kit resumes ordinary finite treatment")
	component_helper.medical.queue_free()
	refused(patient,component_helper,"Queued helper medical component while helper actor remains live")
	patient.medical.queue_free()
	refused(patient,medic,"Queued patient medical component")
	# Use a separate genuine patient to cover the target and owning Game sides.
	var other_patient: Worker=load("res://scenes/player.tscn").instantiate()
	other_patient.game=game
	other_patient.player_id=4
	other_patient.position=patient.position
	game.add_child(other_patient)
	freeze(other_patient)
	other_patient.queue_free()
	refused(other_patient,medic,"Queued patient")
	var foreign_medic: FieldMedic=other_game.medic
	foreign_medic.position=foreign.position+Vector2(36,0)
	foreign_medic.velocity=Vector2.ZERO
	other_game.queue_free()
	refused(foreign,foreign_medic,"Queued owning Game with still-valid actor children")
	check(await Cleanup.free_scene(fixtures,self),"All actual world, worker and SAN fixtures release cleanly")
	print("MEDICAL OWNERSHIP: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
