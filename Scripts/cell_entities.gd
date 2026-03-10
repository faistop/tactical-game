extends Node
class_name CellEntities

var _by_cell: Dictionary = {} # Vector3i -> Array[CellEntity]

func add_entity(entity: CellEntity) -> void:
	if entity == null:
		return

	var arr: Array[CellEntity] = get_entities_at(entity.cell)
	arr.append(entity)
	_by_cell[entity.cell] = arr

func get_entities_at(cell: Vector3i) -> Array[CellEntity]:
	var result: Array[CellEntity] = []

	if not _by_cell.has(cell):
		return result

	var raw: Array = _by_cell[cell] as Array
	for item: Variant in raw:
		var entity: CellEntity = item as CellEntity
		if entity != null:
			result.append(entity)

	return result

func has_entities_at(cell: Vector3i) -> bool:
	return not get_entities_at(cell).is_empty()

func has_kind_at(cell: Vector3i, kind: StringName) -> bool:
	var arr: Array[CellEntity] = get_entities_at(cell)
	for entity: CellEntity in arr:
		if entity != null and entity.kind == kind:
			return true
	return false

func get_first_by_kind(cell: Vector3i, kind: StringName) -> CellEntity:
	var arr: Array[CellEntity] = get_entities_at(cell)
	for entity: CellEntity in arr:
		if entity != null and entity.kind == kind:
			return entity
	return null

func has_spawn_blocker_at(cell: Vector3i) -> bool:
	var arr: Array[CellEntity] = get_entities_at(cell)
	for entity: CellEntity in arr:
		if entity != null and entity.blocks_spawn:
			return true
	return false

func has_enter_blocker_at(cell: Vector3i) -> bool:
	var arr: Array[CellEntity] = get_entities_at(cell)
	for entity: CellEntity in arr:
		if entity != null and entity.blocks_enter:
			return true
	return false

func clear_cleanable_at(cell: Vector3i) -> bool:
	var arr: Array[CellEntity] = get_entities_at(cell)
	if arr.is_empty():
		return false

	var kept: Array[CellEntity] = []
	var removed_any: bool = false

	for entity: CellEntity in arr:
		if entity == null:
			continue
		if entity.cleanable:
			removed_any = true
		else:
			kept.append(entity)

	if kept.is_empty():
		_by_cell.erase(cell)
	else:
		_by_cell[cell] = kept

	return removed_any

func remove_entity(entity: CellEntity) -> void:
	if entity == null:
		return

	var arr: Array[CellEntity] = get_entities_at(entity.cell)
	if arr.is_empty():
		return

	var kept: Array[CellEntity] = []
	for item: CellEntity in arr:
		if item != entity:
			kept.append(item)

	if kept.is_empty():
		_by_cell.erase(entity.cell)
	else:
		_by_cell[entity.cell] = kept

func clear_entities_of_owner(owner_unit: Node3D) -> void:
	if owner_unit == null:
		return

	var cells: Array[Vector3i] = []
	for key: Variant in _by_cell.keys():
		cells.append(key as Vector3i)

	for cell: Vector3i in cells:
		var arr: Array[CellEntity] = get_entities_at(cell)
		var kept: Array[CellEntity] = []

		for entity: CellEntity in arr:
			if entity == null:
				continue
			if entity.owner_unit != owner_unit:
				kept.append(entity)

		if kept.is_empty():
			_by_cell.erase(cell)
		else:
			_by_cell[cell] = kept

func tick_round() -> void:
	var cells: Array[Vector3i] = []
	for key: Variant in _by_cell.keys():
		cells.append(key as Vector3i)

	for cell: Vector3i in cells:
		var arr: Array[CellEntity] = get_entities_at(cell)
		var kept: Array[CellEntity] = []

		for entity: CellEntity in arr:
			if entity == null:
				continue

			if entity.duration_rounds > 0:
				entity.duration_rounds -= 1

			if entity.duration_rounds == 0:
				continue

			kept.append(entity)

		if kept.is_empty():
			_by_cell.erase(cell)
		else:
			_by_cell[cell] = kept

func place_entity(entity: CellEntity) -> bool:
	if entity == null:
		return false
	if has_kind_at(entity.cell, entity.kind):
		print("[ENTITY PLACE FAIL] duplicate kind=", entity.kind, " cell=", entity.cell)
		return false

	add_entity(entity)
	print("[ENTITY PLACED] kind=", entity.kind, " cell=", entity.cell)
	return true

func get_stop_on_enter_at(cell: Vector3i, unit: Node3D, battle_state: BattleState) -> bool:
	var arr: Array[CellEntity] = get_entities_at(cell)

	for entity: CellEntity in arr:
		if entity == null:
			continue
		if not entity.trigger_on_enter:
			continue

		if entity.kind == &"trap":
			print("[TRAP ENTER] unit=", unit.name, " cell=", cell, " owner=", entity.owner_id)
			var apply_root_flag: bool = bool(entity.data.get("apply_root", false))
			if apply_root_flag and battle_state != null and entity.owner_unit != null:
				battle_state.apply_root(unit, entity.owner_unit)

			if entity.remove_after_trigger:
				remove_entity(entity)

			var stop_flag: bool = bool(entity.data.get("stop", true))
			if stop_flag:
				print("[TRAP STOP] unit=", unit.name, " stop=true at ", cell)
				return true

	return false
