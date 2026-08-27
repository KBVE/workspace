extends ECSComponent
class_name CViewer

## CViewer as one frame of viewer state.
## Plain fields, not ECSDataComponent: this changes at 60Hz and set_data() fires a signal.

var world_x: float = 0.0
var world_yaw: float = 0.0
