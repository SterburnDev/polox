extends RefCounted
## Snapshot-based undo/redo: push a copy of the state *before* each change;
## undo/redo hand back the state to restore (or null if there's nothing).

var limit := 60
var _undo: Array = []
var _redo: Array = []


func _init(max_steps: int = 60) -> void:
	limit = max(1, max_steps)


func push(before: Variant) -> void:
	_undo.append(before)
	if _undo.size() > limit:
		_undo.pop_front()
	_redo.clear()


## Forgets the last push (for a change that turned out not to happen).
func drop_last() -> void:
	if not _undo.is_empty():
		_undo.pop_back()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo(current: Variant) -> Variant:
	if _undo.is_empty():
		return null
	_redo.append(current)
	return _undo.pop_back()


func redo(current: Variant) -> Variant:
	if _redo.is_empty():
		return null
	_undo.append(current)
	return _redo.pop_back()


func size() -> int:
	return _undo.size()
