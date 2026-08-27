extends ECSSystem
class_name SNotice

## SNotice opens whatever poster the player is pointing at.
##
## The reading itself happens in React: the sheet is printed matter, and the modal is
## a page, not a 3D overlay. What this system does is decide that a press or a click
## was aimed at a notice rather than at a seat or a door, and say which one.
##
## It consumes the intent it acts on, the way [SSeating] does, so one press does not
## also sit the player down on the bench in front of the poster.

func _on_update(_delta: float) -> void:
	for entry: Dictionary in multi_view([CInput, CPointer]):
		_read(entry[&"CInput"], entry[&"CPointer"])


func _read(intent: CInput, pointer: CPointer) -> void:
	if pointer.notice == null:
		return
	if not (intent.interact_requested or intent.pointer_clicked):
		return
	intent.interact_requested = false
	intent.pointer_clicked = false
	notify(GameEvents.NOTICE_READ, {"id": String(pointer.notice.notice_id)})
