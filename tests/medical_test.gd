extends SceneTree
## Controlled real-worker/physics checks for wounds, conserved supplies, channel
## interruption and critical recovery. NPC routing is tested separately.
class MedicalGame extends Node2D:
	var started := false
	var core: Node2D
	var upgrades
	var ladders: Array[Rect2] = []
	var events: Array[String] = []
	func sound(_kind): pass
	func fx(_pos,_color,_count): pass
	func notify(message): events.append(message)
	func impact(_pos,_kind,_direction=Vector2.LEFT,_power=1.0): pass

var checks := 0
var failures := 0
var game: MedicalGame
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func worker_at(x: float,id: int) -> Worker:
	var worker: Worker = load("res://scenes/player.tscn").instantiate()
	worker.game = game
	worker.player_id = id
	worker.position = Vector2(x,430)
	game.add_child(worker)
	worker.set_physics_process(false)
	worker.get_node("WorkerWeapon").set_physics_process(false)
	return worker
func fresh(p: Worker,hp: float=100.0):
	p.medical.interrupt()
	p.medical.bleeding = 0
	p.medical.fractured = false
	p.medical.state = "healthy" if hp==100 else "wounded"
	p.medical.recovery_time = 0
	p.medical.recovery_kind = ""
	p.medical.critical_remaining = 0
	p.medical.down_elapsed = 0
	p.hp = hp
	p.invulnerability = 0
	p.hurt_stun = 0
	p.down_time = 0
	p.knockback = 0
	p.velocity = Vector2.ZERO
	p.since_hit = 99
func wall_at(point: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.position = point
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8,80)
	shape.shape = rectangle
	body.add_child(shape)
	game.add_child(body)
	return body
func run():
	InputSetup.install()
	game = MedicalGame.new()
	root.add_child(game)
	game.core = Node2D.new()
	game.core.position = Vector2(100,430)
	game.add_child(game.core)
	var p1 := worker_at(500,1)
	var p2 := worker_at(464,2)
	var p3 := worker_at(536,3)
	await physics_frame
	check(p1.medical.charges==2 and not p1.medical.needs_medical_help() and p1.medical.state=="healthy","Each selected worker begins healthy with two separate medical charges")
	p1.take_damage(12)
	check(p1.hp==88 and p1.medical.bleeding==0 and not p1.medical.fractured,"Minor injuries damage HP without adding a wound to every hit")
	fresh(p1)
	p1.progression.armor_tier = 2
	check(is_equal_approx(p1.take_damage(50),32.5) and not p1.medical.fractured and p1.medical.bleeding==2,"Trauma thresholds use actual post-armor damage")
	p1.progression.armor_tier = 0
	fresh(p1)
	p1.take_damage(45)
	check(p1.medical.bleeding==2 and p1.medical.fractured and p1.medical.state=="wounded","A heavy hit creates a persistent visible bleed and leg fracture")
	check(is_equal_approx(p1.movement_multiplier(),MedicalCatalog.FRACTURE_SPEED) and is_equal_approx(p1.work_multiplier(),MedicalCatalog.FRACTURE_WORK),"The fracture actually slows walking, climbing and held work")
	p1._update_health(5.0)
	check(is_equal_approx(p1.hp,48.0) and p1.since_hit==5.0 and p1.invulnerability==0,"Bleeding removes seven real HP over five seconds without resetting enemy-hit timing")
	check(not p1.get_node("MedicalAidTarget").can_interact(p1) and p1.get_node("MedicalAidTarget").can_interact(p2),"The separate medical target excludes self and accepts a reachable healthy partner")
	p2.position.y = 399
	check(not p1.medical.reachable_can_aid(p2),"Medical help cannot pass between different bunker floors")
	p2.position = Vector2(445,430)
	check(not p1.medical.reachable_can_aid(p2),"A helper must physically reach the patient")
	p2.position = Vector2(464,430)
	var cover := wall_at(Vector2(482,400))
	await physics_frame
	await physics_frame
	check(not p1.medical.reachable_can_aid(p2),"A real terrain ray prevents medical treatment through a wall")
	cover.free()
	await physics_frame
	p2.medical.charges = 0
	check(not p1.medical.begin_or_continue_aid(p2,10.0) and p1.hp==48,"An empty helper cannot create treatment or free health")
	p2.medical.charges = 2
	p1.medical.begin_or_continue_aid(p2,1.0)
	check(p2.medical.aid_target==p1 and p2.medical.aid_kind=="splint" and p1.medical.progress_for(p2)>0,"A held channel exposes the correct patient, splint action and actual progress for animation")
	check(not p1.medical.begin_or_continue_aid(p3,10.0) and p3.medical.charges==2 and p1.medical.progress_for(p2)<0.5,"Two helpers cannot combine timers or duplicate treatment")
	p2.position.x -= 7
	p1.medical.begin_or_continue_aid(p2,0.1)
	check(p1.medical.progress_for(p2)==0 and p2.medical.aid_target==null and p2.medical.charges==2,"Moving away interrupts the channel without spending its reserved charge")
	p2.position = Vector2(464,430)
	p1.medical.begin_or_continue_aid(p2,1.0)
	p1.invulnerability = 0
	p1.take_damage(2)
	check(p1.medical.progress_for(p2)==0 and p2.medical.aid_target==null and p2.medical.charges==2,"A new patient hit immediately cancels treatment without consuming supplies")
	p1._update_health(0.2)
	p1.medical.begin_or_continue_aid(p2,1.0)
	p2.take_damage(12)
	check(p1.medical.progress_for(p2)==0 and p2.medical.aid_target==null and p2.medical.charges==2,"A helper hit also cancels outgoing medical work atomically")
	p2._update_health(0.2)
	p1.medical.begin_or_continue_aid(p2,1.0)
	p1.medical.tick(0.3)
	check(p1.medical.progress_for(p2)==0 and p2.medical.charges==2,"Releasing the held interaction cancels after a short gap instead of banking progress")
	p1.medical.begin_or_continue_aid(p2,1.0)
	Input.action_press("p2_fire")
	p1.medical.tick(0.01)
	check(p1.medical.progress_for(p2)==0 and p2.medical.charges==2,"Weapon input interrupts medical work instead of firing and treating simultaneously")
	Input.action_release("p2_fire")
	p1.medical.begin_or_continue_aid(p2,1.0)
	fresh(p3,70)
	p3.position = Vector2(455,430)
	p3.medical.begin_or_continue_aid(p2,0.5)
	check(p1.medical.progress_for(p2)==0 and p2.medical.aid_target==p3,"A helper switching patients cannot retain a second hidden channel")
	p3.medical.interrupt()
	p2.inventory = {"ammo":2,"ore":2}
	var cargo := p2.inventory.duplicate(true)
	var xp_before: float = p2.progression.xp
	var hp_before := p1.hp
	check(p1.medical.begin_or_continue_aid(p2,MedicalCatalog.TREAT_TIME),"A complete uninterrupted held treatment succeeds")
	check(p1.medical.bleeding==0 and not p1.medical.fractured and is_equal_approx(p1.hp,hp_before+35) and p2.medical.charges==1,"Exactly one charge stops bleeding, splints the fracture and restores 35 HP")
	check(p1.medical.bandaged and p1.medical.splinted,"Only completed care leaves a persistent visible dressing and splint")
	check(p2.inventory==cargo and p2.progression.xp==xp_before and p1.movement_multiplier()==1.0 and p1.work_multiplier()==1.0,"Medical supplies neither consume cargo nor farm XP, and healed limbs regain normal movement/work")
	fresh(p1)
	check(not p1.medical.begin_or_continue_aid(p2,10.0) and p2.medical.charges==1,"A fully healthy person cannot consume a charge or over-heal")
	p1.inventory = {"alloy":2,"ammo":1}
	p1.take_damage(1000)
	check(p1.is_downed() and p1.medical.state=="downed" and p1.medical.critical_remaining==45 and p1.hp==0,"Lethal damage creates a recoverable downed patient with a 45-second stability timer")
	check(not p1.medical.bandaged and not p1.medical.splinted,"New relevant trauma replaces the old dressing/splint with an untreated injury")
	var down_cargo := p1.inventory.duplicate(true)
	p1._update_health(46.0)
	check(p1.is_downed() and p1.medical.state=="critical" and p1.medical.critical_remaining==0 and p1.down_time>0 and p1.hp==0,"Expired stability becomes critical without auto-revival or loss of compatibility state")
	check(p1.medical.aid_duration()==8.0 and p1.medical.status_text()==LocaleText.text("KRITISCH · Wiederbeleben 8s") and p1.take_damage(100)==0,"A critical body remains available for longer resuscitation and cannot be damaged repeatedly")
	p1.medical.begin_or_continue_aid(p2,7.9)
	check(p1.is_downed() and p2.medical.charges==1,"Critical treatment cannot finish before all eight held seconds")
	check(p1.medical.begin_or_continue_aid(p2,0.11) and not p1.is_downed() and p1.hp==35 and p2.medical.charges==0,"Critical resuscitation spends one real charge and restores 35 percent health in place")
	check(p1.inventory==down_cargo and p1.position==Vector2(500,430) and p1.medical.bleeding==0 and not p1.medical.fractured,"Revival preserves all cargo and the body's position while stabilizing every wound")
	check(not p1.can_act() and p1.medical.recovery_kind=="resuscitate" and p1.medical.recovery_time==1.1,"The 1.1-second rise has a separate animation state and blocks early movement/fire")
	p1._update_health(1.11)
	check(p1.can_act() and p1.invulnerability>0 and p1.medical.recovery_time==0,"Finishing the rise restores actions while the remaining revival shield still protects")
	fresh(p1)
	p2.medical.charges = 1
	p1.take_damage(1000)
	p1.medical.critical_remaining = 0.1
	p1.medical.begin_or_continue_aid(p2,4.9)
	p1.medical.tick(0.11)
	p1.medical.begin_or_continue_aid(p2,0.1)
	check(p1.medical.state=="critical" and is_equal_approx(p1.medical.progress_for(p2),5.0/8.0) and p2.medical.aid_kind=="resuscitate" and p2.medical.charges==1,"Becoming critical during aid preserves work already done but extends the required channel to eight seconds")
	check(p1.medical.begin_or_continue_aid(p2,3.01) and p2.medical.charges==0,"The extended critical channel completes once with one conserved charge")
	fresh(p2,80)
	p2.position = Vector2(136,430)
	p2.medical.charges = 0
	p2.medical.bleeding = 1
	p2.since_hit = 0
	p2._update_health(3.9)
	check(p2.medical.charges==0 and p2.hp<80,"Core proximity does not instantly refill supplies or hide an active bleed")
	p2._update_health(0.2)
	p2._update_health(5.91)
	check(p2.medical.charges==1 and p2.medical.bleeding==1 and p2.hp<75,"A still-wounded helper refills one charge after six eligible seconds, avoiding an empty-kit coop deadlock")
	p2.medical.bleeding = 0
	p2.medical.fractured = true
	p2._update_health(30)
	check(p2.medical.charges==2 and p2.medical.fractured,"Core restocking caps at two and does not silently remove a fracture")
	fresh(p1,1)
	p1.medical.bleeding = 3
	p1._update_health(1)
	check(p1.is_downed() and p1.hp==0,"Untreated bleeding can incapacitate a low-health worker through the normal KO path")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("MEDICAL CHECKS: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
