extends Node
class_name MovementResolver

signal step_processed(unit: Node3D, from_cell: Vector3i, to_cell: Vector3i)
signal movement_stopped(unit: Node3D, at_cell: Vector3i, reason: String)

var battle_state: BattleState = null
var ability_manager: AbilityManager = null

func setup(state: BattleState, am: AbilityManager) -> void:
	battle_state = state
	ability_manager = am

# path включает start->...->goal (как в build_path)
# Возвращает true если хоть на 1 клетку сдвинулись
func execute_path(unit: Node3D, path: Array[Vector3i]) -> bool:
	if battle_state == null:
		return false
	if unit == null:
		return false
	if path.size() < 2:
		return false

	if not battle_state.can_start_move(unit):
		emit_signal("movement_stopped", unit, battle_state.get_unit_cell(unit), "cannot_start_move")
		return false

	battle_state.on_move_started(unit)

	var moved_any: bool = false

	for i: int in range(1, path.size()):
		var current_cell: Vector3i = battle_state.get_unit_cell(unit)
		var next_cell: Vector3i = path[i]

		if current_cell == BattleState.INVALID_CELL:
			emit_signal("movement_stopped", unit, current_cell, "invalid_current_cell")
			break

		if current_cell == next_cell:
			continue

		if not battle_state.can_enter_cell(unit, current_cell, next_cell):
			emit_signal("movement_stopped", unit, current_cell, "blocked")
			break

		var mp_left: int = battle_state.get_mp_left(unit)
		var step_cost: int = battle_state.get_move_step_cost(unit, current_cell, next_cell)
		if step_cost <= 0 or step_cost > mp_left:
			emit_signal("movement_stopped", unit, current_cell, "no_mp")
			break

		battle_state.spend_mp(unit, step_cost)

		var moved_ok: bool = battle_state.move_unit(unit, current_cell, next_cell)
		if not moved_ok:
			emit_signal("movement_stopped", unit, current_cell, "move_failed")
			break

		moved_any = true

		var entered_cell: Vector3i = battle_state.get_unit_cell(unit)
		if battle_state.cell_entities != null:
			var entered_entities: Array[CellEntity] = battle_state.cell_entities.get_entities_at(entered_cell)
			var kinds: PackedStringArray = PackedStringArray()
			for entity: CellEntity in entered_entities:
				if entity != null:
					kinds.append(String(entity.kind))
			print("[STEP ENTITIES] cell=", entered_cell, " entities=", ", ".join(kinds))

		if ability_manager != null:
			ability_manager.on_cell_enter(unit, entered_cell)

		var stop_now: bool = battle_state.resolve_on_enter_cell(unit, current_cell, entered_cell)
		emit_signal("step_processed", unit, current_cell, entered_cell)

		if stop_now:
			emit_signal("movement_stopped", unit, entered_cell, "stopped_by_trigger")
			return moved_any

	return moved_any
