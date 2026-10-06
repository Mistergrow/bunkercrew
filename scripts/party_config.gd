class_name PartyConfig
extends RefCounted
## New parties have four distinct starters. Saved parties retain their identities.
const MAX_PLAYERS := 4
static var DEFAULT_CHARACTERS: Array[String] = CharacterCatalog.starter_ids()
const COLORS := [Color("dfb35e"), Color("8dc9c8"), Color("a9c98b"), Color("d7a0ba")]

static func normalize_characters(characters: Array, count: int = MAX_PLAYERS) -> Array[String]:
	var result: Array[String] = []
	for slot in clampi(count, 1, MAX_PLAYERS):
		var selected: String = str(characters[slot]) if slot < characters.size() else DEFAULT_CHARACTERS[slot]
		result.append(selected if CharacterCatalog.contains(selected) else DEFAULT_CHARACTERS[slot])
	return result

static func unique_characters(characters: Array) -> Array[String]:
	var result := normalize_characters(characters)
	var used: Array[String] = []
	for slot in result.size():
		if result[slot] in used:
			for starter: String in DEFAULT_CHARACTERS:
				if starter not in result:
					result[slot] = starter
					break
		used.append(result[slot])
	return result

static func player_color(id: int) -> Color:
	return COLORS[clampi(id - 1, 0, MAX_PLAYERS - 1)]
