extends SiegeMachine
## Three finite wave slots form one human fireteam. Gameplay reuses the audited
## obstacle targeting, while anatomy, hitboxes and defeat are explicitly human.
const INFANTRY_ART=preload("res://scripts/ground_infantry_art.gd")
const ROLE_ART=preload("res://scripts/infantry_role_art.gd")
var squad_slot := 0
var stance := 0.0
var gore_mask := 0
var infantry: Node2D
var _wreck_created := false

func _ready() -> void:
	super._ready()
	add_to_group("human_enemies")
	for part in [body_part,legs_part,weapon_part,motion]:
		part.visible=false
		part.set_process(false)
	infantry=INFANTRY_ART.new()
	infantry.name="InfantryRig"
	infantry.soldier=self
	add_child(infantry)
	wetness._apply_material(infantry,false)
	if kind=="rifle_guard": attack_reach+=float(maxi(0,squad_slot-1))*34.0
	_pose_parts()

func _physics_process(delta: float) -> void:
	if dead: return
	super._physics_process(delta)
	stance=move_toward(stance,0.0 if moving else 1.0,delta*3.8)
	_pose_parts()

func _pose_parts() -> void:
	if not is_instance_valid(infantry): return
	infantry.update_pose()
	weapon_part.transform=Transform2D.IDENTITY
	weapon_part.position=Vector2(infantry.gun.origin.x*attack_direction,infantry.gun.origin.y)*visual_scale
	weapon_part.rotation=infantry.gun.get_rotation()*attack_direction
	weapon_part.scale=Vector2(attack_direction,1)*visual_scale
	body_height=-float(infantry.pose.shoulder.y)*visual_scale
	var hitbox:=get_node_or_null("MachineHitbox") as CollisionShape2D
	if is_instance_valid(hitbox):
		var role:=ROLE_ART.spec(kind)
		var height:=lerpf(float(role.standing_height),float(role.kneeling_height),stance)*visual_scale
		hitbox.shape.size=Vector2(float(profile.hitbox.x),height)
		hitbox.position.y=-height*.5
	infantry.queue_redraw()

func weapon_muzzle() -> Vector2:
	return ROLE_ART.spec(kind).muzzle

func weather_feet() -> Array[Vector2]:
	if not is_instance_valid(infantry): return []
	return [infantry.to_global(infantry.pose.feet[0]),infantry.to_global(infantry.pose.feet[1])]

func weather_segments() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not is_instance_valid(infantry): return result
	var body:=WorkerPoseArt.torso_transform(infantry.pose)
	var head: Transform2D=infantry.head_transform()
	var crown: float=ROLE_ART.spec(kind).crown
	ActorWeatherGeometry._segment(result,infantry,head*Vector2(-6,crown+1),head*Vector2(4,crown),"cloth" if kind in ["scout","marksman"] else "metal")
	ActorWeatherGeometry._segment(result,infantry,head*Vector2(4,crown),head*Vector2(9,crown+4),"cloth" if kind in ["scout","marksman"] else "metal")
	ActorWeatherGeometry._segment(result,infantry,body*Vector2(-19 if kind in ["heavy_gunner","combat_medic"] else -9,-2),body*Vector2(8,-2),"cloth")
	return result

func take_damage(amount: float) -> void:
	if dead or not is_finite(amount) or amount<=0: return
	if is_instance_valid(game) and not game.has_method("combat_contact") and game.has_method("impact") and int(get_meta("impact_contact_frame",-1))!=Engine.get_physics_frames():
		game.impact(global_position-Vector2(0,body_height),"flesh",Vector2(-attack_direction,0),clampf(amount/32,.5,1.4))
	var applied:=minf(hp,amount)
	hp=maxf(0,hp-amount)
	hit_flash=.2
	stagger=.16
	if is_instance_valid(game) and game.has_method("combat_contact"):
		game.combat_contact(self,applied,hp<=0)
	if hp<=0: die()
	else: queue_redraw()

func die() -> void:
	if dead: return
	dead=true
	CampaignSalvage.drop_for_enemy(game,self)
	collision_layer=0
	remove_from_group("enemies")
	if is_instance_valid(game):
		if "stats" in game: game.stats.kills=int(game.stats.get("kills",0))+1
		if game.has_method("spawn_pickup"):
			game.spawn_pickup("scrap",int(profile.scrap),global_position+Vector2(-12,-8))
			game.spawn_pickup("core",int(profile.cores),global_position+Vector2(12,-8))
	spawn_motion_wreck()
	queue_free()

func spawn_motion_wreck() -> void:
	if _wreck_created or not is_instance_valid(game) or not is_instance_valid(infantry): return
	_wreck_created=true
	var remains:=get_tree().get_nodes_in_group("infantry_remains").filter(func(node):return node.get_parent()==game and not node.is_queued_for_deletion())
	if remains.size()>=16: remains[0].queue_free()
	var fallen:=INFANTRY_ART.new()
	fallen.corpse=true
	fallen.fall_start=infantry.pose.duplicate(true)
	fallen.fall_gun=infantry.gun
	fallen.gun=infantry.gun
	fallen.pose=fallen.fall_start.duplicate(true)
	fallen.troop_kind=kind
	fallen.squad_slot=squad_slot
	fallen.gore_mask=gore_mask
	fallen.effects=game.get("combat_gore")
	fallen.set_meta("combat_actor_id",str(get_meta("network_entity_id","")))
	fallen.position=game.to_local(global_position)
	fallen.scale=Vector2(attack_direction,1)*visual_scale
	fallen.z_index=4
	game.add_child(fallen)

func _draw() -> void:
	draw_rect(Rect2(-17,-1,34,3),Color(0,0,0,.26))
	if hp<max_hp: Art.bar(self,Rect2(-17*visual_scale,(-73+stance*10)*visual_scale,34*visual_scale,3),hp/max_hp,Art.RED)
	if is_instance_valid(abilities): abilities.draw_telegraph()
