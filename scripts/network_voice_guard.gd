extends RefCounted
## Short catch-up bursts are disposable; sustained abuse belongs to one peer.
const RATE := 55.0
const SAMPLE_USEC := 250000
const SUSTAINED_USEC := 2000000
var updated := -1
var count := 0
var over_since := -1

func observe(now_usec: int, streams: int = 1) -> bool:
	if updated < 0: updated = now_usec
	count += 1
	var elapsed := now_usec - updated
	if elapsed < SAMPLE_USEC: return true
	var excessive := float(count)*1000000.0/elapsed > RATE*3.0*streams
	if excessive:
		if over_since < 0: over_since = updated
	else:
		over_since = -1
	updated = now_usec
	count = 0
	return over_since < 0 or now_usec-over_since < SUSTAINED_USEC
