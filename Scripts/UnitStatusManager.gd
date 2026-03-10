extends Node
class_name UnitStatusManager

var _rooted_by: Dictionary = {} # key: int(unit_id) -> int(owner_id)

func is_rooted(unit: Node3D) -> bool:
	if unit == null:
		return false
	return _rooted_by.has(unit.get_instance_id())

func is_rooted_by_owner(unit: Node3D, owner_unit: Node3D) -> bool:
	if unit == null or owner_unit == null:
		return false

	var unit_id: int = unit.get_instance_id()
	var owner_id: int = owner_unit.get_instance_id()

	if not _rooted_by.has(unit_id):
		return false

	return int(_rooted_by[unit_id]) == owner_id

func apply_root(unit: Node3D, owner_unit: Node3D) -> void:
	if unit == null or owner_unit == null:
		return
	_rooted_by[unit.get_instance_id()] = owner_unit.get_instance_id()

func clear_root(unit: Node3D) -> void:
	if unit == null:
		return
	_rooted_by.erase(unit.get_instance_id())

func clear_all_for_unit(unit: Node3D) -> void:
	if unit == null:
		return

	var unit_id: int = unit.get_instance_id()
	if _rooted_by.has(unit_id):
		_rooted_by.erase(unit_id)

	var erase_keys: Array[int] = []
	for key_any: Variant in _rooted_by.keys():
		var target_id: int = int(key_any)
		var owner_id: int = int(_rooted_by[target_id])
		if owner_id == unit_id:
			erase_keys.append(target_id)

	for target_id: int in erase_keys:
		_rooted_by.erase(target_id)

func begin_round() -> void:
	pass
