class_name JsBridgeObserver
extends ECSObserver

## JsBridgeObserver is now our router

func sub_observers() -> Array[Array]:
	var subs: Array[Array] = []
	for bus_name: StringName in GameEvents.OUTBOUND_WIRE:
		subs.append([q.on_event(bus_name), _fwd.bind(GameEvents.OUTBOUND_WIRE[bus_name])])
	return subs


func _fwd(_event: int, _entity: ECSEntity, payload: Variant, js_name: String) -> void:
	JsBridge.emit_event(js_name, payload if payload is Dictionary else {})
