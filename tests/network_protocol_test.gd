extends SceneTree

const PROTOCOL = preload("res://scripts/network_protocol.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	var fixtures: Array[Dictionary] = [
		{"kind":"hello","version":PROTOCOL.VERSION,"build":PROTOCOL.BUILD,"resume":""},
		{"kind":"lobby","characters":["branko","ivo"],"options":{"environment":"frozen_rail_yard","build_type":"workshop","position":"center"}},
		{"kind":"input","generation":2,"seq":42,"input":{"held":{"right":1.0,"fire":0.7},"pressed":["jump"],"released":["interact"],"aim":[1200.5,312.25],"mouse":true}},
		{"kind":"snapshot","seq":123,"generation":2,"paused":false,"world":{"players":[{"position":Vector2(322.5,430),"velocity":Vector2(124.0,0),"hp":95.5,"inventory":{"steel":3},"medical":{"bleeding":1,"fractured":false}}],"round":{"phase":"attack","wave":7,"time_left":0.0}}},
		{"kind":"effects","generation":2,"events":[
			{"category":"sound","payload":{"kind":"shot"}},
			{"category":"impact","payload":{"at":Vector2(918,412),"material":"metal","direction":Vector2.LEFT,"power":1.25}},
			{"category":"fx","payload":{"at":Vector2(412,430),"color":Color(0.75,0.5,0.25,1.0),"count":8}},
			{"category":"combat","payload":{"kind":"hit","data":{"player_id":2,"amount":16.0,"earned":1.6,"enemy_id":1234567890,"position":Vector2(918,402)}}},
			{"category":"combat","payload":{"kind":"achievement","data":{"id":"first_kill","title":"ERSTER KONTAKT","detail":"Eine Maschine zerstören."}}},
		]},
	]
	for fixture in fixtures:
		var encoded: PackedByteArray = PROTOCOL.encode(fixture)
		check(not encoded.is_empty(), "representative message encodes")
		check(encoded[0] == PROTOCOL.VERSION, "wire header has protocol version")
		check(encoded.decode_u32(1) == var_to_bytes(fixture).size(), "header records exact decompressed length")
		check(PROTOCOL.decode(encoded) == fixture, "actual ZSTD Variant round trip")
		check(encoded.slice(5).decompress(encoded.decode_u32(1),FileAccess.COMPRESSION_ZSTD) == var_to_bytes(fixture), "payload is valid ZSTD with bounded size")
	var rows: Array = []
	for index in 512:
		rows.append({"id":index,"position":Vector2(index*3.5,430),"velocity":Vector2(-45.25,0),"hp":float(index%120),"kind":"strider","dead":false})
	var populated := {"kind":"snapshot","generation":3,"seq":984,"world":{"entities":rows}}
	check(PROTOCOL.decode(PROTOCOL.encode(populated)) == populated, "512 entity snapshot preserves all state")
	check(PROTOCOL.encode(populated).size() < var_to_bytes(populated).size(), "world payload compresses")
	for length in range(6):
		var short := PackedByteArray()
		short.resize(length)
		check(PROTOCOL.decode(short).is_empty(), "truncated header rejected")
	var valid: PackedByteArray = PROTOCOL.encode(fixtures[0])
	var changed := valid.duplicate()
	changed[0] = 99
	check(PROTOCOL.decode(changed).is_empty(), "wrong envelope version rejected")
	for size in [0,1,7,PROTOCOL.MAX_DECODED+1,0xFFFFFFFF]:
		changed = valid.duplicate()
		changed.encode_u32(1,size)
		check(PROTOCOL.decode(changed).is_empty(), "invalid advertised allocation rejected before decompression")
	var huge := PackedByteArray()
	huge.resize(PROTOCOL.MAX_PACKET+1)
	check(PROTOCOL.decode(huge).is_empty(), "oversized wire packet rejected")
	huge.resize(PROTOCOL.MAX_DECODED)
	check(PROTOCOL.encode({"kind":"snapshot","payload":huge}).is_empty(), "oversized decoded message is not encoded")
	for value in [null, true, 123, "snapshot", [], {"payload":1}, {"kind":2}]:
		check(PROTOCOL.decode(frame_variant(value)).is_empty(), "root requires dictionary and string kind")
	for invalid in [NAN, INF, -INF, Vector2(NAN,0), Vector2(0,INF)]:
		var message := {"kind":"snapshot","nested":[{"value":invalid}]}
		check(PROTOCOL.encode(message).is_empty(), "nonfinite nested value cannot be sent")
		check(PROTOCOL.decode(frame_variant(message)).is_empty(), "nonfinite nested value rejected on actual wire")
	var finite_values: Array = [
		PackedFloat32Array([0.0,-5.5,3.125]), PackedFloat64Array([0.0,-1.0e200,1.0e200]),
		PackedVector2Array([Vector2.ZERO,Vector2(-127.25,4096.5)]),
		PackedColorArray([Color.TRANSPARENT,Color(0.25,0.5,0.75,1.0)]),
		PackedInt32Array([-2147483647,0,2147483647]),
		PackedInt64Array([-(1<<62),0,1<<62]),
		PackedStringArray(["Schicht","P2","ÜBERTRAGUNG"]),
		PackedByteArray([0,127,255]), Rect2(-20,-30,640,180), Color(1.5,0.25,0.5,1.0),
		Vector2i(-5,100), Rect2i(-20,-30,640,180),
	]
	for value in finite_values:
		var message := {"kind":"snapshot","nested":{"value":value}}
		check(not PROTOCOL.encode(message).is_empty(), "supported finite packed or geometry value encodes")
		check(PROTOCOL.decode(PROTOCOL.encode(message)) == message, "supported finite value preserves type and data")
	var unsafe_values: Array = [
		PackedFloat32Array([0.0,NAN]), PackedFloat32Array([INF,1.0]),
		PackedFloat64Array([NAN,1.0]), PackedFloat64Array([0.0,-INF]),
		PackedVector2Array([Vector2.ZERO,Vector2(NAN,1)]),
		PackedVector2Array([Vector2(0,INF)]),
		PackedColorArray([Color(0,0,NAN,1)]), PackedColorArray([Color(0,0,0,INF)]),
		Rect2(Vector2(NAN,0),Vector2.ONE), Rect2(Vector2.ZERO,Vector2(1,INF)),
		Color(NAN,0,0,1), Color(0,0,0,-INF),
		Vector3.ZERO, PackedVector3Array([Vector3.ZERO]), Transform2D.IDENTITY,
		PackedStringArray(["x".repeat(16385)]),
	]
	for value in unsafe_values:
		var message := {"kind":"snapshot","nested":[{"value":value}]}
		check(PROTOCOL.encode(message).is_empty(), "nonfinite or unsupported packed/geometry value cannot be sent")
		check(PROTOCOL.decode(frame_variant(message)).is_empty(), "nonfinite or unsupported packed/geometry value rejected on wire")
	var packed_boundary := PackedFloat32Array()
	packed_boundary.resize(16384)
	check(not PROTOCOL.encode({"kind":"snapshot","rows":packed_boundary}).is_empty(), "maximum packed item count accepted")
	packed_boundary.resize(16385)
	check(PROTOCOL.decode(frame_variant({"kind":"snapshot","rows":packed_boundary})).is_empty(), "oversized packed item count rejected on wire")
	var nested: Array = []
	for depth in 26:
		nested = [nested]
	check(PROTOCOL.decode(frame_variant({"kind":"snapshot","nested":nested})).is_empty(), "deeply nested data rejected on wire")
	var large_array: Array = []
	large_array.resize(16385)
	check(PROTOCOL.decode(frame_variant({"kind":"snapshot","rows":large_array})).is_empty(), "array item limit enforced on wire")
	var large_dictionary: Dictionary = {}
	for index in 8193:
		large_dictionary[index] = 0
	check(PROTOCOL.decode(frame_variant({"kind":"snapshot","rows":large_dictionary})).is_empty(), "dictionary entry limit enforced on wire")
	check(PROTOCOL.decode(frame_variant({"kind":"notice","text":"x".repeat(16385)})).is_empty(), "string length limit enforced on wire")
	var object := RefCounted.new()
	check(not PROTOCOL._safe(object,0), "objects cannot enter validated messages")
	check(not PROTOCOL._safe(Callable(self,"check"),0), "callables cannot enter validated messages")
	check(not PROTOCOL._safe(process_frame,0), "signals cannot enter validated messages")
	check(PROTOCOL.encode({"kind":"snapshot","payload":object}).is_empty(), "object cannot be encoded by sender")
	check(PROTOCOL.decode(frame_variant({"kind":"snapshot","payload":object})).is_empty(), "serialized object identity rejected without object construction")
	# A valid stream advertising too little memory is rejected by ZSTD. Godot
	# reports the expected decode error; suppress only this intentional bad input.
	changed = valid.duplicate()
	changed.encode_u32(1,8)
	var previous_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	var malformed: Dictionary = PROTOCOL.decode(changed)
	Engine.print_error_messages = previous_errors
	check(malformed.is_empty(), "compressed payload cannot exceed advertised allocation")
	print("Network protocol: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)

func frame_variant(value) -> PackedByteArray:
	var raw := var_to_bytes(value)
	var frame := PackedByteArray([PROTOCOL.VERSION])
	frame.resize(5)
	frame.encode_u32(1,raw.size())
	frame.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return frame

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(label)
