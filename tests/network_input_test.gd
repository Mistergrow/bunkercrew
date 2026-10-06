extends SceneTree
const NetInput := preload("res://scripts/network_input.gd")
class Session extends Node:
	var active := false
	var is_host := true
	var local_player_id := 1
	var remote_input: Dictionary = {}
class Hud extends Node:
	var overlay := ""
class World extends Node2D:
	var network: Node
	var hud: Node
	var started := true
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _run() -> void:
	InputSetup.install()
	var world := World.new()
	world.network = Session.new()
	world.hud = Hud.new()
	world.add_child(world.network)
	world.add_child(world.hud)
	root.add_child(world)
	var host := Worker.new()
	host.player_id = 1
	host.game = world
	var guest := Worker.new()
	guest.player_id = 2
	guest.game = world
	world.add_child(host)
	world.add_child(guest)
	host.set_physics_process(false)
	guest.set_physics_process(false)
	Input.action_press("p2_right",0.7)
	check(is_equal_approx(NetInput.axis(guest,"left","right"),0.7),"Offline second-player analog strength is retained")
	check(NetInput.axis(host,"left","right")==0.0,"Offline player-two binding does not move player one")
	check(NetInput.mouse_aim(host) and not NetInput.mouse_aim(guest),"Offline mouse/controller aim roles remain unchanged")
	Input.action_release("p2_right")
	world.network.active = true
	world.network.remote_input = {"held":{"right":0.75,"fire":1.0,"interact":1.0},"pressed":["jump","reload"],"released":["drop"],"aim":[987.0,123.0],"mouse":true}
	check(is_equal_approx(NetInput.axis(guest,"left","right"),0.75),"Host receives remote analog movement independently")
	check(NetInput.is_pressed(guest,"fire") and NetInput.is_pressed(guest,"interact"),"Remote held fire and work reach their owner")
	check(not NetInput.is_pressed(host,"fire"),"Remote firing cannot trigger the host's weapon")
	check(NetInput.just_pressed(guest,"jump") and NetInput.just_pressed(guest,"reload"),"Remote edge pulses reach jump/reload")
	check(NetInput.just_released(guest,"drop"),"Remote releases preserve tap versus held drop")
	check(NetInput.mouse_aim(guest) and NetInput.aim_position(guest)==Vector2(987,123),"Remote participant uses their own mouse aim")
	Input.action_press("p2_fire")
	world.network.remote_input = {}
	check(not NetInput.is_pressed(guest,"fire"),"Host's local P2 bindings cannot control the online guest")
	Input.action_release("p2_fire")
	world.network.remote_input = {"held":{"interact":1.0},"pressed":["jump"]}
	world.network.remote_input.pressed = []
	check(not NetInput.just_pressed(guest,"jump") and NetInput.is_pressed(guest,"interact"),"Clearing edge pulses preserves held work without repeating jump")
	world.network.is_host = false
	world.network.local_player_id = 2
	Input.action_press("p1_left")
	Input.action_press("p1_fire")
	check(NetInput.axis(guest,"left","right")==-1 and NetInput.is_pressed(guest,"fire"),"Guest controls P2 with WASD and mouse bindings")
	check(not NetInput.is_pressed(host,"fire") and NetInput.axis(host,"left","right")==0,"Guest cannot drive host replica")
	var frame := NetInput.sample_local(world)
	check(frame.held.has("left") and frame.held.has("fire") and not frame.held.has("p1_left"),"Wire state uses explicit unprefixed actions")
	world.hud.overlay = "personal"
	check(NetInput.sample_local(world).held.is_empty() and not NetInput.is_pressed(guest,"fire"),"Local menus block gameplay and send released held state")
	world.hud.overlay = ""
	Input.action_release("p1_left")
	Input.action_release("p1_fire")
	world.network.active = false
	check(not NetInput.is_pressed(guest,"interact"),"Leaving a session cannot leave a remote work key stuck")
	await preload("res://tests/scene_cleanup.gd").free_scene(world,self)
	print("NETWORK INPUT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
