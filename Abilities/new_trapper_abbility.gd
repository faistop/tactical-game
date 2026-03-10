extends Ability
class_name NewTrapperAbility

func plan(controller, unit: Node3D, _from_cell: Vector3i) -> Dictionary:
	if controller == null or unit == null:
		return {}

	var bcc: BattleCommandController = controller as BattleCommandController
	if bcc == null or bcc.battle_state == null or bcc.units_root == null:
		return {}

	var bs: BattleState = bcc.battle_state
	if bs.cell_entities == null:
		return {}

	var trapper_cell: Vector3i = bs.get_unit_cell(unit)
	if trapper_cell == BattleState.INVALID_CELL:
		return {}

	var player_units: Array[Node3D] = _get_player_units_sorted_by_distance(bcc, bs, unit, trapper_cell)
	if player_units.is_empty():
		return {}

	var primary_target: Node3D = player_units[0]
	var chosen_target: Node3D = primary_target

	if bs.is_rooted_by_owner(primary_target, unit):
		for candidate: Node3D in player_units:
			if candidate == null or candidate == primary_target:
				continue
			if not bs.is_rooted_by_owner(candidate, unit):
				chosen_target = candidate
				break

	var target_cell: Vector3i = bs.get_unit_cell(chosen_target)
	var trap_cells: Array[Vector3i] = _get_diagonal_trap_cells_around_target(bs, trapper_cell, target_cell)

	if trap_cells.is_empty() and chosen_target != primary_target:
		target_cell = bs.get_unit_cell(primary_target)
		trap_cells = _get_diagonal_trap_cells_around_target(bs, trapper_cell, target_cell)

	if trap_cells.is_empty():
		return {}

	var intent: Dictionary = {}
	intent[IntentKeys.INTENT_KIND] = IntentKeys.KIND_TRAP
	intent[IntentKeys.INTENT_CELLS] = trap_cells
	return intent

func execute(controller, unit: Node3D, intent: Dictionary) -> bool:
	if controller == null or unit == null:
		return false

	var bcc: BattleCommandController = controller as BattleCommandController
	if bcc == null or bcc.battle_state == null:
		return false

	var bs: BattleState = bcc.battle_state
	if bs.cell_entities == null:
		return false

	if intent == null or intent.is_empty():
		return false

	var kind_v: Variant = intent.get(IntentKeys.INTENT_KIND, null)
	if kind_v == null or typeof(kind_v) != TYPE_STRING_NAME:
		return false

	var kind: StringName = kind_v as StringName
	if kind != IntentKeys.KIND_TRAP:
		return false

	var cells_v: Variant = intent.get(IntentKeys.INTENT_CELLS, null)
	if cells_v == null or typeof(cells_v) != TYPE_ARRAY:
		return false

	var raw_cells: Array = cells_v
	if raw_cells.is_empty():
		return false

	var placed_any: bool = false

	for item: Variant in raw_cells:
		if typeof(item) != TYPE_VECTOR3I:
			continue

		var cell: Vector3i = item as Vector3i

		if not bs._in_bounds(cell):
			continue
		if bs.is_occupied(cell):
			continue
		if bs.cell_entities.has_kind_at(cell, &"trap"):
			continue

		var entity: CellEntity = TrapEntityFactory.create(cell, unit)
		print("[TRAP PLACE] unit=", unit.name, " cell=", cell)
		if bs.cell_entities.place_entity(entity):
			placed_any = true

	return placed_any

func _get_player_units_sorted_by_distance(
	bcc: BattleCommandController,
	bs: BattleState,
	trapper: Node3D,
	trapper_cell: Vector3i
) -> Array[Node3D]:
	var result: Array[Node3D] = []

	for child_any: Node in bcc.units_root.get_children():
		var u: Node3D = child_any as Node3D
		if u == null or u == trapper:
			continue

		var st: UnitStats = bs.get_stats(u)
		if st == null:
			continue
		if st.faction != UnitStats.Faction.PLAYER:
			continue

		result.append(u)

	result.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var acell: Vector3i = bs.get_unit_cell(a)
		var bcell: Vector3i = bs.get_unit_cell(b)

		var ad: int = abs(acell.x - trapper_cell.x) + abs(acell.z - trapper_cell.z)
		var bd: int = abs(bcell.x - trapper_cell.x) + abs(bcell.z - trapper_cell.z)

		if ad == bd:
			var aid: int = a.get_instance_id()
			var bid: int = b.get_instance_id()
			return aid < bid

		return ad < bd
	)

	return result

func _get_diagonal_trap_cells_around_target(
	bs: BattleState,
	trapper_cell: Vector3i,
	target_cell: Vector3i
) -> Array[Vector3i]:
	var dx: int = target_cell.x - trapper_cell.x
	var dz: int = target_cell.z - trapper_cell.z

	var candidates: Array[Vector3i] = []

	# Трапер слева/справа от героя -> ловушки сверху и снизу героя
	if abs(dx) >= abs(dz):
		candidates.append(target_cell + Vector3i(0, 0, 1))
		candidates.append(target_cell + Vector3i(0, 0, -1))
	# Трапер сверху/снизу от героя -> ловушки слева и справа героя
	else:
		candidates.append(target_cell + Vector3i(1, 0, 0))
		candidates.append(target_cell + Vector3i(-1, 0, 0))

	var result: Array[Vector3i] = []

	for cell: Vector3i in candidates:
		if not bs._in_bounds(cell):
			continue
		if bs.is_occupied(cell):
			continue
		if bs.cell_entities.has_kind_at(cell, &"trap"):
			continue
		result.append(cell)

	return result
