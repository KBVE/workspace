extends RefCounted
class_name ECSScope

## ECSScope is for entities and systems that live exactly as long as their owner.
## 08/24/2026 - I had some weakref issues, long story.

var _entities: Array[ECSEntity] = []
var _systems: Array[StringName] = []


func spawn(id: int = 0) -> ECSEntity:
	var entity := Ecs.spawn(id)
	_entities.append(entity)
	return entity


func add_system(name: StringName, system: ECSSystem) -> ECSSystem:
	_systems.append(name)
	return Ecs.add_system(name, system)


## Destroys everything spawned through this scope, should be safe to call twice.
func dispose() -> void:
	for entity: ECSEntity in _entities:
		if entity.valid():
			entity.destroy()
	_entities.clear()
	for name: StringName in _systems:
		Ecs.remove_system(name)
	_systems.clear()
