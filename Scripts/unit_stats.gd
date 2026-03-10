extends Node
class_name UnitStats

signal hp_changed(hp: int, max_hp: int)

enum Faction { PLAYER, ENEMY }
enum UnitState { READY, SPENT }
enum AIRole { MELEE, RANGED }
enum AttackEffect { DAMAGE, PUSH, NONE }
enum UnitTag { HEAVY, LIGHT, OBSTACLE, ENEMY_BUILDING, HIVE, TRAPPER }
enum SpawnRole { ATTACK, SUPPORT, DEFENSE, BUILDING }

@export var abilities: Array[Ability] = []
@export var spawn_role: SpawnRole = SpawnRole.ATTACK
@export var spawn_priority: int = 0
@export var display_name: String = ""
@export var tags: Array[UnitTag] = []
@export var attack_effect: AttackEffect = AttackEffect.DAMAGE
@export var push_power: int = 0

@export var max_hp: int = 6

# ВАЖНО: hp больше НЕ export, чтобы его не меняли напрямую из инспектора и кода.
var hp: int = 0

@export var damage: int = 1

@export var faction: Faction = Faction.PLAYER
@export_range(0, 20, 1) var move_range: int = 3

@export var ai_role: AIRole = AIRole.MELEE

@export var shoot_range: int = 1
@export var shoot_min_range: int = 1

var state: UnitState = UnitState.READY

func _ready() -> void:
	# На случай, если кто-то забудет вызвать reset_runtime().
	# Стартуем полным, если hp ещё не инициализирован.
	if hp <= 0:
		hp = max(1, max_hp)

func reset_runtime() -> void:
	set_hp(max_hp)

func is_dead() -> bool:
	return hp <= 0

func set_hp(value: int) -> void:
	var clamped: int = clamp(value, 0, max(1, max_hp))
	if clamped == hp:
		return
	hp = clamped
	hp_changed.emit(hp, max_hp)

func apply_damage(amount: int) -> void:
	var dmg: int = max(amount, 0)
	if dmg == 0:
		return
	set_hp(hp - dmg)

func heal(amount: int) -> void:
	var h: int = max(amount, 0)
	if h == 0:
		return
	set_hp(hp + h)

func has_tag(tag: UnitTag) -> bool:
	return tags.has(tag)

func get_tags_text_ru() -> String:
	# Строка для UI: "Тяжёлый, Постройка врага"
	if tags.is_empty():
		return "—"

	var parts: PackedStringArray = PackedStringArray()
	for t: UnitTag in tags:
		match t:
			UnitTag.HEAVY:
				parts.append("Тяжёлый")
			UnitTag.LIGHT:
				parts.append("Лёгкий")
			UnitTag.OBSTACLE:
				parts.append("Препятствие")
			UnitTag.HIVE:
				parts.append("Улей")
			UnitTag.TRAPPER:
				parts.append("Трапер")
			UnitTag.ENEMY_BUILDING:
				parts.append("Постройка врага")
			_:
				parts.append("Неизвестно")

	return ", ".join(parts)
