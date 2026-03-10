extends Resource
class_name Ability

# юнит-владелец способности
var owner: Node3D = null

# вызывается когда способность назначена юниту
func setup(_owner: Node3D) -> void:
	owner = _owner


# ---------- AI ----------
# планирование действия (для врагов)
func plan(_controller, _unit: Node3D, _from_cell: Vector3i) -> Dictionary:
	return {}

# выполнение действия
func execute(_controller, _unit: Node3D, _intent: Dictionary) -> bool:
	return false


# ---------- EVENTS ----------
# вход юнита в клетку
func on_cell_enter(_unit: Node3D, _cell: Vector3i) -> void:
	pass

# начало раунда
func on_round_start() -> void:
	pass

# конец раунда
func on_round_end() -> void:
	pass

# получение урона
func on_unit_damaged(_unit: Node3D, _damage: int) -> void:
	pass
