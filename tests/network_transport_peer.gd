extends SceneTree
## Subprocess fixture used by network_transport_test.py. UPnP is always off.

const TRANSPORT = preload("res://scripts/network_transport.gd")
var transport
var host := false
var elapsed := 0.0
var received := 0
var done := false
var unreliable_received := false
var finishing := false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	host = OS.get_environment("LASTSHIFT_TRANSPORT_ROLE") == "host"
	transport = TRANSPORT.new()
	root.add_child(transport)
	transport.error.connect(func(message: String): finish(false, message))
	transport.packet.connect(on_packet)
	transport.connected.connect(on_connected)
	var port := OS.get_environment("LASTSHIFT_TRANSPORT_PORT").to_int()
	var result: Error = transport.host(port, false) if host else transport.join("127.0.0.1",port)
	if result != OK:
		finish(false, "open failed")
	elif host:
		print("TRANSPORT_HOST_READY")

func on_connected() -> void:
	if not host:
		transport.send("input:move_right".to_utf8_buffer())
		var data := PackedByteArray()
		data.resize(65536)
		for index in data.size():
			data[index] = index % 251
		transport.send(data)

func on_packet(data: PackedByteArray) -> void:
	if host:
		if data == "complete".to_utf8_buffer():
			transport.disconnect_guest()
			if transport.send("late snapshot".to_utf8_buffer()) != ERR_UNCONFIGURED:
				finish(false, "send must stop immediately after disconnect request")
				return
			finish(received==2, "host packet count")
			return
		received += 1
		transport.send(data)
	else:
		if data == PackedByteArray([250, 17, 33, 99]):
			unreliable_received = true
			complete_guest()
			return
		if received == 0 and data != "input:move_right".to_utf8_buffer():
			finish(false, "input mismatch")
			return
		if received == 1:
			if data.size()!=65536:
				finish(false, "snapshot size")
				return
			for index in data.size():
				if data[index] != index % 251:
					finish(false, "snapshot payload mismatch")
					return
		received += 1
		complete_guest()

func complete_guest() -> void:
	if received != 2 or not unreliable_received or finishing:
		return
	finishing = true
	transport.send("complete".to_utf8_buffer())
	await create_timer(0.15).timeout
	finish(true, "guest echoed both exact packets and received independent unreliable channel")

func _process(delta: float) -> bool:
	elapsed += delta
	if host and received == 2 and not done:
		transport.send(PackedByteArray([250, 17, 33, 99]), false)
	if elapsed > 8.0 and not done:
		finish(false, "transport test timeout")
	return false

func finish(ok: bool, message: String) -> void:
	if done:
		return
	done = true
	print("TRANSPORT_PASS " if ok else "TRANSPORT_FAIL ", "host " if host else "guest ", message)
	if transport != null:
		transport.close()
		transport.queue_free()
	quit(0 if ok else 1)
