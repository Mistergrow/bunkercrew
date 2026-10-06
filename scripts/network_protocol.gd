extends RefCounted
## Only Variant data crosses the wire; Object deserialization is never enabled.
const VERSION := 1
# Lobby chat, named participants and authoritative history must agree on peers.
const BUILD := "bunkercrew-net-20"
# The broker build stays stable, while peers must share world validation rules.
# Revision 3 adds the authoritative convoy boarding and roadside repair state.
# The relay remains a byte transport; its build and public service stay valid.
const WORLD_REVISION := 5
const MAX_PACKET := 512*1024
const MAX_DECODED := 2*1024*1024
const MAX_ZSTD_BLOCKS := 32
const VariantGuard := preload("res://scripts/network_variant_guard.gd")

static func encode(message: Dictionary) -> PackedByteArray:
	if not message.get("kind") is String or not _safe(message,0): return PackedByteArray()
	return encode_trusted(message)

static func encode_trusted(message: Dictionary) -> PackedByteArray:
	# Only locally constructed, already bounded gameplay envelopes use this path.
	var raw := var_to_bytes(message)
	if raw.size()>MAX_DECODED:
		return PackedByteArray()
	var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var result := PackedByteArray([VERSION])
	result.resize(5)
	result.encode_u32(1,raw.size())
	result.append_array(compressed)
	return result if result.size()<=MAX_PACKET else PackedByteArray()

static func decode(packet: PackedByteArray) -> Dictionary:
	if packet.size()<6 or packet.size()>MAX_PACKET or packet[0]!=VERSION:
		return {}
	var decoded_size := packet.decode_u32(1)
	if decoded_size<8 or decoded_size>MAX_DECODED:
		return {}
	var compressed := packet.slice(5)
	if not _zstd_frame(compressed, decoded_size): return {}
	# Godot's public decoder logs malformed input. A remote byte is not an
	# application error: keep these two bounded, synchronous native calls quiet.
	# There is no await, object construction or user callback in this interval.
	var print_errors := Engine.print_error_messages
	if Thread.is_main_thread(): Engine.print_error_messages = false
	var raw := compressed.decompress(decoded_size,FileAccess.COMPRESSION_ZSTD)
	if Thread.is_main_thread(): Engine.print_error_messages = print_errors
	if raw.size()!=decoded_size or not VariantGuard.new().validate(raw):
		return {}
	if Thread.is_main_thread(): Engine.print_error_messages = false
	var value = bytes_to_var(raw) # Never bytes_to_var_with_objects.
	if Thread.is_main_thread(): Engine.print_error_messages = print_errors
	if not value is Dictionary or not value.get("kind",null) is String:
		return {}
	return value if _safe(value,0) else {}

static func _safe(value,depth: int) -> bool:
	return _safe_value(value, depth, [VariantGuard.MAX_NODES])

static func _safe_value(value, depth: int, budget: Array) -> bool:
	budget[0] -= 1
	if budget[0] < 0: return false
	if depth>24:
		return false
	if value is Object or value is Callable or value is Signal:
		return false
	if value is float:
		return is_finite(value)
	if value is Vector2:
		return value.is_finite()
	if value is Rect2:
		return value.position.is_finite() and value.size.is_finite()
	if value is Color:
		return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
	if value is PackedByteArray:
		return value.size()<=MAX_DECODED
	if value is String or value is StringName:
		return value.length()<=16384
	if value is Dictionary:
		if value.size()>8192: return false
		if value.get_typed_key_builtin() not in VariantGuard.ALLOWED or value.get_typed_value_builtin() not in VariantGuard.ALLOWED: return false
		for key in value:
			if not _safe_value(key,depth+1,budget) or not _safe_value(value[key],depth+1,budget): return false
	elif value is Array:
		if value.size()>16384: return false
		if value.get_typed_builtin() not in VariantGuard.ALLOWED: return false
		for item in value:
			if not _safe_value(item,depth+1,budget): return false
	elif value is PackedFloat32Array or value is PackedFloat64Array or value is PackedVector2Array or value is PackedColorArray or value is PackedInt32Array or value is PackedInt64Array or value is PackedStringArray:
		if value.size()>16384: return false
		for item in value:
			if not _safe_value(item,depth+1,budget): return false
	elif not (value==null or value is bool or value is int or value is Vector2i or value is Rect2i):
		return false
	return true


static func _zstd_frame(data: PackedByteArray, expected_size: int) -> bool:
	# Require one ordinary bounded frame, its exact content size, no dictionary,
	# no skippable/concatenated frames, and complete block/trailer boundaries.
	# Zstandard format: facebook/zstd doc/zstd_compression_format.md.
	if data.size() < 6 or data.decode_u32(0) != 0xFD2FB528: return false
	var descriptor := int(data[4])
	if descriptor & 0x1B: return false # Reserved bits and dictionary ID.
	var single := bool(descriptor & 0x20)
	var offset := 5
	if not single:
		var window := int(data[offset])
		offset += 1
		var base := 1 << (10 + (window >> 3))
		if base + (base >> 3) * (window & 7) > MAX_DECODED: return false
	var size_flag := descriptor >> 6
	var size_bytes: int = [1 if single else 0, 2, 4, 8][size_flag]
	if size_bytes == 0 or offset + size_bytes > data.size(): return false
	var content_size := 0
	for index in size_bytes:
		# Refuse high bits before a signed shift can wrap an 8-byte declaration.
		if index >= 3 and data[offset + index] != 0: return false
		content_size |= int(data[offset + index]) << (index * 8)
	if size_bytes == 2: content_size += 256
	if content_size != expected_size: return false
	offset += size_bytes
	var blocks := 0
	while offset + 3 <= data.size():
		blocks += 1
		if blocks > MAX_ZSTD_BLOCKS: return false
		var header := int(data[offset]) | (int(data[offset + 1]) << 8) | (int(data[offset + 2]) << 16)
		offset += 3
		var block_type := (header >> 1) & 3
		var block_size := header >> 3
		if block_type == 3 or block_size > 131072: return false
		offset += 1 if block_type == 1 else block_size
		if offset > data.size(): return false
		if header & 1:
			return offset + (4 if descriptor & 4 else 0) == data.size()
	return false
