Мы работаем над проектом в Godot

chatgpt, отвечай кратко. все предложенные изменения указывай четко куда нужно вставлять. если нужно заменить код, то указывай что на что нужно заменить.


Architecture overview is in README.

Engine: Godot 4.6
Developer level: beginner
Map size: around 11x11 grid

описание игры:
Into The Breach like игра, где игрок атакует, а не защищается
игрок на тактику и расчет, вся информация видна
цель - уничтожить улей (hive). уничтожение возможно как прямым уроном, так и очисткой клеток (враги заражают клетки и могу строить там)
весь урон важен. HP обычно от 1 до 4
Движение, блокировка прохода, телепорты, возведение структур, контроль клеток - основа

боевая система:
у героев игрока 2 action points. Атака, движение, очистка клетки (но каждое действие только один раз). 
Движение можно разделять. Походить две клетки из четырех, сделать любые действия другими героями, вернуться к походившему и походить им еще раз. Если передвижение было задействовано и потом этим же героем было потрачено второе AP - движение обнуляется. герой считается полностью походившим.
Проходить через врагов нельзя, через своих можно. Расчет передвижения идет по каждой клетке (не телепорт)
большая часть логики врагов не просто нанести урон игроку, а остановить его передвижение к улью.
клетки могут стоить разное количество очков передвижения (лес х2, болото х2 на вход в клетку и х2 на выход из нее, но просто х2 если герой проходит по клетке дальше и не останавливается)

NOTES
По возможности использовать уже имеющиеся скрипты.
системы могут добавляться, функции могут меняться. проект еще в стадии разработки. если видишь, что для моего запроса нужна отдельная система (и видишь, что ее нет), то предложи ее

Architecture notes
BattleState should be the main authority for unit placement and cell data.
Movement logic should not be duplicated in multiple systems.
Ability effects should preferably be implemented through AbilityManager.
Unit removal should be centralized.


Основные скрипты:
scripts/battle/battle_state.gd  
scripts/battle/battle_command_controller.gd  
scripts/battle/movement_resolver.gd  
scripts/battle/pathfinder.gd  
scripts/abilities/ability_manager.gd  
scripts/units/unit_stats.gd

схема сцены ITB like поля

BattleScene (Node3D)
├── Board (Node3D)
│   ├── Grid (GridMap)
│   ├── BoardCollision (StaticBody3D)
│   │   └── CollisionShape3D   # плоскость/меш под поле, один коллайдер
│   └── Markers (Node3D)       # опционально: стартовые точки/спавн-метки
│
├── Units (Node3D)             # сюда инстансятся все юниты (player/enemy)
├── VFX (Node3D)               # попадания, частицы, временные эффекты
├── CameraRig (Node3D)
│   ├── Camera3D
│   └── DirectionalLight3D
│
├── Systems (Node)
│   ├── BattleState (Node3D)               # central source of truth for battle data, stores units, occupied cells, traps, statuses and validates actions
│   ├── BattleInputController (Node3D)     # ВВОД: Player commands and battle flow.
│   ├── BattleCommandController (Node3D)   # controls player interaction and battle flow
│   ├── HighlightManager (Node3D)          # ПОДСВЕТКА: MOVE/ATTACK/INFO
│   ├── UnitSpawner (Node3D)               # СПАВН/PLACEMENT, сигнал placement_finished
│   ├── TurnManager (Node)                 # (чуть позже) порядок ходов/фазы
│   ├── Pathfinder (Node)                  # Movement calculations 
│   ├── AbilityManager (Node)              # Ability lookup and execution.
│   └── MovementResolver (Node)            # Executes movement and movement effects.
│ 
└── UI (CanvasLayer)
    ├── Hud (Control)                       # кнопки, подсказки, панель юнита
    │    ├── EnemyInfoPanel
    │    ├── ActionButtons (HBoxContainer)
    │    └── UnitHoverHP
    └── Debug (Control)        
