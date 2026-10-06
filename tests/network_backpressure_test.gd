extends SceneTree
const Protocol:=preload("res://scripts/network_protocol.gd")
class WorldProbe extends RefCounted:
	var captures:=0
	func capture() -> Dictionary:
		captures+=1
		return {}
class SessionProbe extends "res://scripts/network_session.gd":
	var sent:Array=[]
	var send_ok:=true
	func _send(message:Dictionary,_reliable:=true,_target_id:int=0) -> bool:
		if send_ok: sent.append(message.duplicate(true))
		return send_ok
class AudioProbe extends RefCounted:
	var live_music: Node
class GameProbe extends Node:
	var started:=false
	var combat_events:Node
	var audio := AudioProbe.new()
var checks:=0
var failures:=0
func _initialize() -> void: _run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func _run() -> void:
	var game:=GameProbe.new()
	root.add_child(game)
	var session:=SessionProbe.new()
	session.game=game
	game.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.active=true
	session.is_host=true
	session.peer_connected=true
	session._authenticated=true
	session.state="playing"
	session._generation=2
	var world:=WorldProbe.new()
	session.world=world
	for i in 50: session._send_snapshot()
	check(session._snapshot_seq==4 and session.sent.size()==4,"A stalled client cannot queue more than four full snapshots")
	check(world.captures==4,"Throttled snapshots do not repeatedly build and compress the world")
	session._packet(Protocol.encode({"kind":"snapshot_ack","generation":1,"seq":4}))
	check(session._snapshot_ack==0,"Old-generation acknowledgements cannot release the queue")
	session._packet(Protocol.encode({"kind":"snapshot_ack","generation":2,"seq":100}))
	check(session._snapshot_ack==0,"Unsent future state cannot be acknowledged")
	session._packet(Protocol.encode({"kind":"snapshot_ack","generation":2,"seq":2}))
	for i in 10: session._send_snapshot()
	check(session._snapshot_seq==6 and world.captures==6,"Two acknowledgements permit exactly two fresh snapshots")
	session._packet(Protocol.encode({"kind":"snapshot_ack","generation":2,"seq":1}))
	check(session._snapshot_ack==2,"Delayed acknowledgements cannot move the window backwards")
	session._snapshot_ack=6
	session.send_ok=false
	session._send_snapshot()
	check(session._snapshot_seq==6,"A failed send does not reserve an unreachable sequence")
	session.send_ok=true
	session.sent.clear()
	session.is_host=false
	session._received_seq=6
	session._process(.21)
	session._process(.21)
	var acks:=session.sent.filter(func(value):return value.kind=="snapshot_ack")
	check(acks.size()==2 and acks[0].seq==6 and acks[1].seq==6,"The receiver repeats acknowledgements so dropped acknowledgements recover without new snapshots")
	session.active=false
	game.queue_free()
	await process_frame
	print("NETWORK BACKPRESSURE: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
