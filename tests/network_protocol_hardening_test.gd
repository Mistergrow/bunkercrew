extends SceneTree
const Protocol := preload("res://scripts/network_protocol.gd")
const Guard := preload("res://scripts/network_variant_guard.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func frame(raw: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray([Protocol.VERSION])
	result.resize(5)
	result.encode_u32(1, raw.size())
	result.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return result

func _initialize() -> void:
	var original := {"kind":"hello", "version":1, "build":Protocol.BUILD, "resume":""}
	var valid: PackedByteArray = Protocol.encode(original)
	var truncated_ok := true
	for length in range(valid.size()):
		truncated_ok = Protocol.decode(valid.slice(0, length)).is_empty() and truncated_ok
	check(truncated_ok, "Every truncated ZSTD envelope is rejected without engine error spam")
	var extra := valid.duplicate()
	extra.append(0)
	check(Protocol.decode(extra).is_empty(), "Trailing compressed bytes are rejected")
	extra = valid.duplicate()
	extra.append_array(valid.slice(5))
	check(Protocol.decode(extra).is_empty(), "Concatenated ZSTD frames cannot bypass a single-frame size budget")
	var empty_blocks := PackedByteArray([0x28, 0xB5, 0x2F, 0xFD, 0x20, 8])
	for index in Protocol.MAX_ZSTD_BLOCKS + 1: empty_blocks.append_array(PackedByteArray([0, 0, 0]))
	empty_blocks.append_array(PackedByteArray([65, 0, 0, TYPE_DICTIONARY, 0, 0, 0, 0, 0, 0, 0]))
	check(not Protocol._zstd_frame(empty_blocks, 8), "Many empty ZSTD blocks cannot multiply frame-header work")
	var large_bytes := PackedByteArray()
	large_bytes.resize(1900000)
	var large_message := {"kind":"snapshot", "bytes":large_bytes}
	check(Protocol.decode(Protocol.encode(large_message)) == large_message, "A legitimate near-limit multi-block frame remains supported")
	for wrong_size in [8, 12, Protocol.MAX_DECODED]:
		extra = valid.duplicate()
		extra.encode_u32(1, wrong_size)
		check(Protocol.decode(extra).is_empty(), "Advertised allocation must equal the ZSTD content size")
	for flag in [1, 2, 8, 16]:
		extra = valid.duplicate()
		extra[9] |= flag
		check(Protocol.decode(extra).is_empty(), "Unknown dictionary/reserved ZSTD flags are rejected")
	var raw := PackedByteArray()
	raw.resize(8)
	raw.encode_u32(0, TYPE_DICTIONARY)
	raw.encode_u32(4, 0x7FFFFFFF)
	check(Protocol.decode(frame(raw)).is_empty(), "A tiny container claiming billions of entries fails before allocation")
	for kind in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_NODE_PATH, TYPE_RID]:
		raw.encode_u32(0, kind)
		check(Protocol.decode(frame(raw)).is_empty(), "Objects and executable/reference types never enter the native decoder")
	var typed: Array[int] = [1, 2, 3]
	var typed_dict: Dictionary[String, Vector2] = {"a":Vector2(3, 9)}
	check(Protocol.decode(Protocol.encode({"kind":"snapshot", "a":typed, "b":typed_dict})).a == typed, "Valid typed builtin arrays and dictionaries retain their values")
	raw = var_to_bytes({"kind":"snapshot", "typed":typed})
	var marker := PackedByteArray([TYPE_ARRAY, 0, 1, 0, TYPE_INT, 0, 0, 0])
	var at := find_bytes(raw, marker)
	check(at > 0, "Malformed typed-container fixture identifies actual encoded metadata")
	if at > 0:
		raw.encode_u32(at + 4, TYPE_OBJECT)
		check(Protocol.decode(frame(raw)).is_empty(), "Typed object containers are rejected before native construction")
	raw = var_to_bytes(original)
	raw.append_array(PackedByteArray([0, 0, 0, 0]))
	check(Protocol.decode(frame(raw)).is_empty(), "Trailing serialized values are rejected")
	var nul_rows: Array = []
	nul_rows.resize(16384)
	var fanout := {"kind":"snapshot", "rows":[nul_rows, nul_rows, nul_rows, nul_rows, nul_rows]}
	check(not Protocol._safe(fanout, 0) and Protocol.encode(fanout).is_empty(), "Aggregate node budget bounds many individually legal containers at encode time")
	check(Protocol.decode(frame(var_to_bytes(fanout))).is_empty(), "Aggregate node budget also applies to adversarial actual wire data")
	var invalid_utf8 := var_to_bytes({"kind":"hello", "value":"ZZ"})
	at = find_bytes(invalid_utf8, PackedByteArray([90, 90]))
	if at >= 0:
		invalid_utf8[at] = 255
	check(Protocol.decode(frame(invalid_utf8)).is_empty(), "Invalid UTF-8 returns a rejection without remote-triggered log spam")
	# Corrupt valid compression and valid Variant bytes, retaining bounded frame
	# headers. Some mutations are valid messages; every result must remain data.
	var rng := RandomNumberGenerator.new()
	rng.seed = 917201
	var started := Time.get_ticks_usec()
	for index in 600:
		extra = valid.duplicate()
		extra[rng.randi_range(5, extra.size() - 1)] ^= rng.randi_range(1, 255)
		Protocol.decode(extra)
	check(Engine.print_error_messages, "Malformed decoder paths restore the caller's error reporting setting")
	Engine.print_error_messages = false
	Protocol.decode(valid)
	var remained_muted := not Engine.print_error_messages
	Engine.print_error_messages = true
	check(remained_muted, "A caller that muted engine reports keeps its original setting")
	print("600 bounded corruption probes: %.2f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	check(Protocol.decode(valid) == original, "Corruption cannot poison later valid packets")
	var entities: Array = []
	for index in 512:
		entities.append({"id":index,"position":Vector2(index * 3.0,430),"hp":90.0,"kind":"strider","dead":false})
	var snapshot := {"kind":"snapshot","seq":1,"world":{"entities":entities}}
	var snapshot_packet: PackedByteArray = Protocol.encode(snapshot)
	started = Time.get_ticks_usec()
	var snapshot_ok := true
	for index in 5: snapshot_ok = Protocol.decode(snapshot_packet) == snapshot and snapshot_ok
	check(snapshot_ok, "Structural preflight preserves a representative 512-entity snapshot")
	print("512-entity full preflight/decode mean: %.2f ms" % ((Time.get_ticks_usec() - started) / 5000.0))
	print("Network protocol hardening: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func find_bytes(haystack: PackedByteArray, needle: PackedByteArray) -> int:
	for index in range(haystack.size() - needle.size() + 1):
		if haystack.slice(index, index + needle.size()) == needle: return index
	return -1
