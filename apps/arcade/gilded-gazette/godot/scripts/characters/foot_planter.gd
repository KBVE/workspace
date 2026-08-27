extends SkeletonModifier3D
class_name FootPlanter

## FootPlanter keeps the feet on the deck the clips were not authored for.
##
## The walk clips were animated for a character of a fixed height on a floor at zero.
## This rig is scaled to a stature and stands on a deck a metre and a quarter up, and
## the two disagree by a few centimetres that read as sinking or skating. Worse, they
## disagree by a different amount in every clip, so the error changes as the gait
## blends and a foot slides while it should be planted.
##
## Two bone IK per leg, and the hips drop when neither leg can reach. Nothing here
## decides when it applies: [member weight] is written by [SFootPlanting], which turns
## it off in the air where there is no floor to plant against.

## Metres, in this rig's own space. Only used where the ray finds nothing, which is off
## the end of the world rather than anywhere the player can stand.
@export var floor_height_metres: float = 0.0

## How far above and below the foot to look for something to stand on. Up, because a
## foot mid-stride can be inside a step it is about to land on; down, because it can be
## over one it is about to fall to.
@export var probe_up_metres: float = 0.5
@export var probe_down_metres: float = 1.0

## How much of the correction to apply. Zero leaves the clips exactly as authored.
@export_range(0.0, 1.0) var weight: float = 1.0

## How far the ankle sits above the sole, so the foot rests on the deck rather than
## through it. Measured from the rig, and scaled with it.
@export var ankle_height_metres: float = 0.075

## The most the hips will drop to let a foot reach. Past this the leg is allowed to
## fall short, because a character folding in half is worse than a foot in the air.
@export var deepest_hip_drop_metres: float = 0.35

const LEGS := [
	{"upper": &"LeftUpperLeg", "lower": &"LeftLowerLeg", "foot": &"LeftFoot"},
	{"upper": &"RightUpperLeg", "lower": &"RightLowerLeg", "foot": &"RightFoot"},
]

const HIPS_BONE := &"Hips"


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or is_zero_approx(weight):
		return

	var wanted: Array[float] = []
	for leg: Dictionary in LEGS:
		var foot := skeleton.find_bone(leg["foot"])
		if foot < 0:
			return
		wanted.append(_rise_under(skeleton, skeleton.get_bone_global_pose(foot).origin))

	# the hips follow the foot that has furthest to reach down, so the legs keep their
	# authored bend instead of snapping straight to make up the difference
	var drop: float = minf(minf(wanted[0], wanted[1]), 0.0)
	drop = maxf(drop, -deepest_hip_drop_metres) * weight
	var hips := skeleton.find_bone(HIPS_BONE)
	if hips >= 0 and not is_zero_approx(drop):
		var pose := skeleton.get_bone_global_pose(hips)
		pose.origin.y += drop
		skeleton.set_bone_global_pose(hips, pose)

	for i in LEGS.size():
		_plant(skeleton, LEGS[i], wanted[i] * weight)


## How far the foot at [param at] has to move to stand on whatever is under it, in the
## skeleton's own units. The search is done in world space because that is where the
## floor is, and the rig is both scaled and offset away from it.
func _rise_under(skeleton: Skeleton3D, at: Vector3) -> float:
	var to_world := skeleton.global_transform
	var scale: float = to_world.basis.get_scale().y
	var world := to_world * at
	var space := skeleton.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		world + Vector3.UP * probe_up_metres,
		world - Vector3.UP * probe_down_metres)
	query.exclude = _own_bodies()
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return floor_height_metres + ankle_height_metres - at.y
	return (hit["position"].y + ankle_height_metres * scale - world.y) / maxf(scale, 0.0001)


## The character's own collider, which a ray dropped from inside him would otherwise
## find before it found the floor. Walked up the tree rather than wired in, so a
## passenger rig gets the same treatment as the player without anyone remembering to.
func _own_bodies() -> Array[RID]:
	var node: Node = self
	while node != null:
		if node is CollisionObject3D:
			return [(node as CollisionObject3D).get_rid()]
		node = node.get_parent()
	return []


## Puts one foot [param rise] metres from where the clip left it, and bends the knee to
## suit. The bend plane is the one the animation was already using, so a leg that was
## authored bowed stays bowed rather than snapping to face front.
func _plant(skeleton: Skeleton3D, leg: Dictionary, rise: float) -> void:
	var upper := skeleton.find_bone(leg["upper"])
	var lower := skeleton.find_bone(leg["lower"])
	var foot := skeleton.find_bone(leg["foot"])
	if upper < 0 or lower < 0 or foot < 0:
		return

	var hip_pose := skeleton.get_bone_global_pose(upper)
	var knee_pose := skeleton.get_bone_global_pose(lower)
	var foot_pose := skeleton.get_bone_global_pose(foot)
	var hip := hip_pose.origin
	var knee := knee_pose.origin
	var target := foot_pose.origin + Vector3(0.0, rise, 0.0)

	var thigh := hip.distance_to(knee)
	var shin := knee.distance_to(foot_pose.origin)
	if thigh <= 0.0 or shin <= 0.0:
		return

	var to_target := target - hip
	var reach := to_target.length()
	# never fully straight: a leg at exactly thigh + shin has no plane to bend in, and
	# the knee direction becomes whatever the arithmetic rounds to
	reach = clampf(reach, absf(thigh - shin) + 0.001, thigh + shin - 0.001)
	var along := to_target.normalized()

	var bend_plane := (knee - hip).slide(along)
	if bend_plane.length_squared() < 0.000001:
		bend_plane = Vector3.FORWARD.slide(along)
	bend_plane = bend_plane.normalized()

	# cosine rule: how far off the straight line to the target the knee sits
	var cos_hip := clampf((thigh * thigh + reach * reach - shin * shin)
		/ (2.0 * thigh * reach), -1.0, 1.0)
	var placed_knee := hip + (along * cos_hip + bend_plane * sin(acos(cos_hip))) * thigh

	_aim(skeleton, upper, hip_pose, knee, placed_knee)
	var moved_knee := skeleton.get_bone_global_pose(lower)
	moved_knee.origin = placed_knee
	skeleton.set_bone_global_pose(lower, moved_knee)
	_aim(skeleton, lower, moved_knee, foot_pose.origin, target)


## Rotates [param bone] so the point it was aiming at ends up where it should be. The
## whole basis is turned rather than rebuilt, so the bone keeps its roll and the foot
## does not spin on the ankle.
func _aim(skeleton: Skeleton3D, bone: int, pose: Transform3D,
		was_at: Vector3, goes_to: Vector3) -> void:
	var was := (was_at - pose.origin).normalized()
	var goes := (goes_to - pose.origin).normalized()
	if was.length_squared() < 0.5 or goes.length_squared() < 0.5:
		return
	if was.dot(goes) > 0.99999:
		return
	pose.basis = Basis(Quaternion(was, goes)) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
