class_name RainCatalog
extends RefCounted
## World-space pixel rain: few longer foreground streaks, many finer distant drops.
const BANDS := [
	{"count":44,"speed":190.0,"length":5.0,"alpha":0.13,"width":1.0,"parallax":-0.20,"depth":0.0},
	{"count":52,"speed":315.0,"length":9.0,"alpha":0.25,"width":1.0,"parallax":0.0,"depth":1.0},
	{"count":24,"speed":485.0,"length":16.0,"alpha":0.36,"width":2.0,"parallax":0.24,"depth":2.0},
]
const PRIMARY_COUNT := 120
const WET_CONTACT := 0.032
const SKY_RAY_LENGTH := 1800.0
