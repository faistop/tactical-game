extends Control
class_name UnitHpBar

@export var pip_size: Vector2 = Vector2(10.0, 10.0)
@export var pip_gap: int = 2

@export var color_full: Color = Color(0.2, 0.9, 0.2, 1.0)
@export var color_empty: Color = Color(0.2, 0.2, 0.2, 0.8)

@onready var _pips_box: HBoxContainer = $Panel/Pips as HBoxContainer

var _max_hp: int = 1
var _hp: int = 1

func set_values(new_hp: int, new_max_hp: int) -> void:
	_max_hp = max(1, new_max_hp)
	_hp = clamp(new_hp, 0, _max_hp)

	_pips_box.add_theme_constant_override(&"separation", pip_gap)

	_rebuild_if_needed()
	_refresh_colors()

func _rebuild_if_needed() -> void:
	# Если количество пипсов совпадает — не пересоздаем
	if _pips_box.get_child_count() == _max_hp:
		return

	# Удаляем старые СРАЗУ (queue_free удаляет в конце кадра и даёт визуальный глитч)
	while _pips_box.get_child_count() > 0:
		var n: Node = _pips_box.get_child(0)
		_pips_box.remove_child(n)
		n.free()

	# Создаем новые квадраты
	for i in range(_max_hp):
		var pip: ColorRect = ColorRect.new()
		pip.custom_minimum_size = pip_size
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_pips_box.add_child(pip)

func _refresh_colors() -> void:
	var count: int = _pips_box.get_child_count()
	for i in range(count):
		var pip := _pips_box.get_child(i) as ColorRect
		if pip == null:
			continue
		pip.color = color_full if i < _hp else color_empty
