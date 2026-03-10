extends EnemyAbility
class_name TrapperAbility

func _init() -> void:
	tag = UnitStats.UnitTag.TRAPPER

func plan(bcc: BattleCommandController, enemy: Node3D, from_cell: Vector3i) -> Dictionary:
	var intent: Dictionary = {}

	if enemy == null:
		return intent

	var bs: BattleState = bcc.battle_state
	if bs == null:
		return intent

	# цель — как у твоего AI (используем существующую функцию BCC)
	var target: Node3D = bcc._ai_pick_target(enemy, from_cell)
	if target == null:
		return intent

	var t_cell: Vector3i = bs.get_unit_cell(target)

	# ставим ловушки только если цель в соседней клетке
	var trap_cells: Array[Vector3i] = _get_trap_cells(from_cell, t_cell)
	if trap_cells.is_empty():
		return intent

	# ЛОВУШКИ АКТИВНЫ СРАЗУ (в ход игрока)
	for c: Vector3i in trap_cells:
		bs.place_trap(c, enemy)

	intent[IntentKeys.INTENT_MOVE_TO] = from_cell
	intent[IntentKeys.INTENT_KIND] = IntentKeys.KIND_TRAP
	intent[IntentKeys.INTENT_CELLS] = trap_cells
	return intent

func execute(_bcc: BattleCommandController, _enemy: Node3D, _intent: Dictionary) -> bool:
	# трапер “атакует” в фазу планирования (ставит ловушки).
	# На execute ему делать нечего.
	return true

func _get_trap_cells(trapper_cell: Vector3i, target_cell: Vector3i) -> Array[Vector3i]:
	var traps: Array[Vector3i] = []

	var dx: int = target_cell.x - trapper_cell.x
	var dz: int = target_cell.z - trapper_cell.z

	if abs(dx) + abs(dz) != 1:
		return traps

	if dx != 0:
		traps.append(target_cell + Vector3i(0, 0, 1))
		traps.append(target_cell + Vector3i(0, 0, -1))
		return traps

	traps.append(target_cell + Vector3i(1, 0, 0))
	traps.append(target_cell + Vector3i(-1, 0, 0))
	return traps
