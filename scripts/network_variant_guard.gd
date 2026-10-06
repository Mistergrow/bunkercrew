extends RefCounted
## Structural preflight for Godot 4.7's Variant wire format, before allocation.
## Object/script containers, unknown flags and trailing bytes are never accepted.
## Format reference: Godot core/io/marshalls.cpp (4.7).
const MAX_NODES := 65536
const ALLOWED := [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME,
	TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_RECT2I, TYPE_COLOR, TYPE_DICTIONARY,
	TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY,
	TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_COLOR_ARRAY]
var data: PackedByteArray
var offset := 0
var remaining := MAX_NODES

func validate(raw: PackedByteArray) -> bool:
	data = raw
	offset = 0
	remaining = MAX_NODES
	return _value(0, TYPE_DICTIONARY) and offset == data.size()

func _take(size: int) -> bool:
	if size < 0 or size > data.size() - offset: return false
	offset += size
	return true

func _u32() -> int:
	if not _take(4): return -1
	return data.decode_u32(offset - 4)

func _string() -> bool:
	var length := _u32()
	# UTF-8 has at most four bytes per permitted source character. The final
	# semantic check enforces the character count after native UTF-8 decoding.
	if length < 0 or length > 65536: return false
	return _take((length + 3) & ~3)

func _container_type(flags: int) -> int:
	if flags == 0: return TYPE_NIL
	if flags != 1: return -1
	var kind := _u32()
	return kind if kind in ALLOWED else -1

func _value(depth: int, expected: int = TYPE_NIL) -> bool:
	remaining -= 1
	if depth > 24 or remaining < 0: return false
	var header := _u32()
	if header < 0: return false
	var kind := header & 255
	if kind not in ALLOWED or (expected != TYPE_NIL and kind != expected): return false
	var flags := header >> 16
	# Bits 8–15 are unused; only the precise flags supported below may pass.
	if header & 0xFF00: return false
	if kind == TYPE_DICTIONARY or kind == TYPE_ARRAY:
		if flags & ~(15 if kind == TYPE_DICTIONARY else 3): return false
		var key_type := _container_type(flags & 3)
		var value_type := _container_type((flags >> 2) & 3) if kind == TYPE_DICTIONARY else TYPE_NIL
		if key_type < 0 or value_type < 0: return false
		var count := _u32()
		if count < 0 or count > (8192 if kind == TYPE_DICTIONARY else 16384): return false
		var nodes := count * (2 if kind == TYPE_DICTIONARY else 1)
		if nodes > remaining or nodes * 4 > data.size() - offset: return false
		for index in count:
			if not _value(depth + 1, key_type): return false
			if kind == TYPE_DICTIONARY and not _value(depth + 1, value_type): return false
		return true
	var wide := flags == 1
	if flags != 0 and not (wide and kind in [TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2, TYPE_RECT2, TYPE_PACKED_VECTOR2_ARRAY]): return false
	match kind:
		TYPE_NIL: return true
		TYPE_BOOL: return _take(4)
		TYPE_INT, TYPE_FLOAT: return _take(8 if wide else 4)
		TYPE_VECTOR2: return _take(16 if wide else 8)
		TYPE_VECTOR2I: return _take(8)
		TYPE_RECT2: return _take(32 if wide else 16)
		TYPE_RECT2I, TYPE_COLOR: return _take(16)
		TYPE_STRING, TYPE_STRING_NAME: return _string()
	var packed_count := _u32()
	if packed_count < 0: return false
	if kind == TYPE_PACKED_BYTE_ARRAY:
		return packed_count <= 2097152 and _take((packed_count + 3) & ~3)
	if packed_count > 16384 or packed_count > remaining: return false
	remaining -= packed_count
	if kind == TYPE_PACKED_STRING_ARRAY:
		for index in packed_count:
			if not _string(): return false
		return true
	var stride := 4
	if kind in [TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY]: stride = 8
	elif kind == TYPE_PACKED_VECTOR2_ARRAY: stride = 16 if wide else 8
	elif kind == TYPE_PACKED_COLOR_ARRAY: stride = 16
	return _take(packed_count * stride)
