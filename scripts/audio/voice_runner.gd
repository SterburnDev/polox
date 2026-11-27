extends Node
## Lightweight root helper owned by VoiceEngine for active HTTPRequests and AudioStreamPlayers.
## Ensures all children are stopped and freed cleanly at scene exit (no ObjectDB leaks).


func stop_all() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			var p := child as AudioStreamPlayer
			p.stop()
			p.stream = null
		elif child is HTTPRequest:
			(child as HTTPRequest).cancel_request()
		child.queue_free()


func _exit_tree() -> void:
	stop_all()
