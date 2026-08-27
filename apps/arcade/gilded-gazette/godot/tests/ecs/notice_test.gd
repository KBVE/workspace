extends GdUnitTestSuite

## Every notice authored under shared/data/notices hangs somewhere a player can read it.
##
## The sheets are content, not scene: a posting added to the mdx has to appear in the
## consist without anything here changing, and a sheet whose texture never shipped has
## to fail loudly rather than hang an untextured white rectangle in the carriage.

const TRAIN := "res://scenes/train/train.scn"


func test_every_authored_notice_hangs_in_the_consist() -> void:
	var train: Node3D = load(TRAIN).instantiate()
	add_child(train)
	await await_millis(200)

	var consist: Consist = train.find_child("Consist", true, false)
	assert_object(consist).is_not_null()

	var posted := consist.notice_anchors()
	assert_int(posted.size()).is_equal(GameContent.notices().size())

	for anchor: Dictionary in posted:
		var sheet: MeshInstance3D = anchor["sheet"]
		assert_object(sheet.mesh).is_not_null()
		var paper := (sheet.mesh as QuadMesh).material as StandardMaterial3D
		assert_object(paper.albedo_texture).is_not_null()
		# clear of the seat backs, which stand 1.33 above a floor at 1.2735
		assert_float(anchor["at"].y).is_greater(Consist.FLOOR_Y + 1.33)
		# stuck to a wall rather than hanging over the aisle
		assert_float(absf(anchor["at"].z)).is_greater(Consist.INTERIOR_HALF_Z - 0.1)

	train.queue_free()


func test_a_notice_names_a_carriage_the_train_actually_has() -> void:
	for notice: Dictionary in GameContent.notices():
		var carriage := int(notice.get("carriage", -1))
		assert_int(carriage).is_greater_equal(0)
		assert_int(carriage).is_less(GameContent.carriage_locations().size())
