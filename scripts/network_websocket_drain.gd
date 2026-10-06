extends Node
## A WebSocket needs polling after queuing departure and its close handshake.
## Keep only the retired socket, independently of the departing game scene.
const CLOSE_SECONDS := 2.0
var _peer: WebSocketPeer
var _deadline_usec := 0
var _drain := false

static func retire(peer: WebSocketPeer, tree: SceneTree, drain: bool = false) -> void:
	if peer == null or peer.get_ready_state() == WebSocketPeer.STATE_CLOSED: return
	var closer := new()
	closer.process_mode = Node.PROCESS_MODE_ALWAYS
	closer._peer = peer
	closer._drain = drain
	closer._deadline_usec = Time.get_ticks_usec() + int(CLOSE_SECONDS * 1000000)
	# Push already queued frames before a caller can immediately quit its scene.
	peer.poll()
	if not drain: peer.close(1000, "Reconnecting")
	tree.root.add_child.call_deferred(closer)

func _process(_delta: float) -> void:
	_peer.poll()
	if _drain and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN and _peer.get_current_outbound_buffered_amount() == 0:
		_drain = false
		_peer.close(1000, "Leaving")
	if _peer.get_ready_state() == WebSocketPeer.STATE_CLOSED or Time.get_ticks_usec() >= _deadline_usec:
		_peer.close()
		_peer = null
		queue_free()
