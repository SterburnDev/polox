extends RefCounted
## Sliding-window client-side rate limiter. Free tiers punish bursts, so we
## space requests ourselves instead of eating HTTP 429s.

var per_minute: int = 20
var _stamps: Array[float] = []
## Set from a 429 Retry-After header; nothing is sent before this time.
var blocked_until: float = 0.0


func _init(limit: int = 20) -> void:
	per_minute = max(1, limit)


func _prune(now: float) -> void:
	while not _stamps.is_empty() and _stamps[0] <= now - 60.0:
		_stamps.pop_front()


## Seconds to wait before the next request may be sent (0 = go now).
func wait_time(now: float) -> float:
	_prune(now)
	var wait := maxf(0.0, blocked_until - now)
	if _stamps.size() >= per_minute:
		wait = maxf(wait, _stamps[0] + 60.0 - now)
	return wait


func record(now: float) -> void:
	_prune(now)
	_stamps.append(now)


## Requests still available in the current window. Background chatter uses
## this to stay out of the way of the player's own conversations.
func remaining(now: float) -> int:
	_prune(now)
	if now < blocked_until:
		return 0
	return per_minute - _stamps.size()


func block_for(seconds: float, now: float) -> void:
	blocked_until = maxf(blocked_until, now + seconds)
