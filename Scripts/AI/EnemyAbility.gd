extends Resource
class_name EnemyAbility

@export var tag: UnitStats.UnitTag = UnitStats.UnitTag.LIGHT

# Планирование: может поставить эффекты сразу и возвращает intent для телеграфа.
func plan(_bcc: BattleCommandController, _enemy: Node3D, _from_cell: Vector3i) -> Dictionary:
	return {}

# Исполнение: если ability сама исполняет действие в ENEMY_EXECUTE — вернёт true.
# Если false — BCC применит дефолтное поведение.
func execute(_bcc: BattleCommandController, _enemy: Node3D, _intent: Dictionary) -> bool:
	return false
