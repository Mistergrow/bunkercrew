extends RefCounted
## AudioServer retires playback handles on later mixer/main-thread updates.
## A fixed delay can end too early under software rendering or Dummy audio.

static func free_scene(scene: Node, tree: SceneTree) -> bool:
	var pending: Array[WeakRef] = []
	var audio_players := scene.find_children("*", "AudioStreamPlayer", true, false)
	audio_players.append_array(scene.find_children("*", "AudioStreamPlayer2D", true, false))
	for player in audio_players:
		if player.has_stream_playback():
			pending.append(weakref(player.get_stream_playback()))
	_collect_retired_playbacks(scene,pending)
	if tree.current_scene == scene:
		tree.current_scene = null
	scene.queue_free()
	# queue_free itself and the AudioServer's deferred handle cleanup both need
	# main-loop updates. Keep no strong reference to a playback while waiting.
	var deadline := Time.get_ticks_msec() + 5000
	while true:
		await tree.process_frame
		var still_alive := is_instance_valid(scene)
		for playback in pending:
			still_alive = still_alive or playback.get_ref() != null
		if not still_alive:
			return true
		if Time.get_ticks_msec() >= deadline:
			push_error("Scene cleanup timed out: a scene or audio playback was not released")
			return false
	return false

static func _collect_retired_playbacks(node: Node,pending: Array[WeakRef]) -> void:
	# Preview changes may have stopped a previous stream before this teardown.
	# The mixer can still own those handles after the player has a new stream.
	if node.has_method("get_retired_music_playbacks"):
		for playback: WeakRef in node.get_retired_music_playbacks():
			pending.append(playback)
	if node.has_method("get_retired_audio_playbacks"):
		for playback: WeakRef in node.get_retired_audio_playbacks():
			pending.append(playback)
	for child in node.get_children():
		_collect_retired_playbacks(child,pending)
