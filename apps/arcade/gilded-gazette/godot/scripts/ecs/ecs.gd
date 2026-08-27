extends Node

## Ecs : autoload owning the world, both lanes, observer center, signals, data yo and events.
##
## godot-ecs never creates, ticks, or homes a world (train session); this is that decision,
## made once, so gameplay reaches it without threading a reference.
##
## [b]runner[/b] : [ECSSystem], main thread, insertion order, for scene tree work.[br]
## [b]scheduler[/b] : [ECSParallel] on [WorkerThreadPool], DAG batched by before/after
## + read/write conflicts, for pure data work. Needs more testing for some of them edgy cases.
## build_schedule() before dat 1st tick, important later when doing with the JsBridge ecosystem.


var world: ECSWorld

## The main-thread lane, ticked in insertion order.
var runner: ECSRunner

## The worker-pool lane. Null until [method build_schedule].
var scheduler: ECSScheduler


var observers: ECSObserverCenter

## Set false and neither lane ticks.
var running: bool = true

var _schedule_built: bool = false

func _ready() -> void:
	world = ECSWorld.new()
	runner = world.create_runner(&"main")
	observers = ECSObserverCenter.new(world)
	process_priority = -100

func _process(delta: float) -> void:
	if not running:
		return
	runner.run(delta)
	if _schedule_built:
		scheduler.run(delta)

func _exit_tree() -> void:
	if world:
		world.clear()

# ---- entities ----


func spawn(id: int = 0) -> ECSEntity:
	return world.create_entity(id)

## The world bus, the seam Maaack menus and React both speak through.
func notify(event_name: StringName, value: Variant = null) -> void:
	world.notify(event_name, value)

# ---- systems ----


func add_system(name: StringName, system: ECSSystem) -> ECSSystem:
	add_child(system)
	runner.add_system(name, system)
	return system

func remove_system(name: StringName) -> void:
	var system := runner.get_system(name)
	if system == null:
		return
	runner.remove_system(name)
	system.queue_free()


## Rebuilds the DAG: cheap at startup, expensive mid-frame.
func add_parallel_systems(systems: Array) -> void:
	if scheduler == null:
		scheduler = world.create_scheduler(&"main")
	scheduler.add_systems(systems)


func build_schedule() -> void:
	if scheduler == null:
		return
	scheduler.build()
	_schedule_built = true

# ---- observers ----


func add_observer(observer: ECSObserver) -> ECSObserver:
	add_child(observer)
	observers.register(observer)
	return observer


func remove_observer(observer: ECSObserver) -> void:
	observers.unregister(observer)
	observer.queue_free()
