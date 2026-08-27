# GdUnitTestSuite
extends GdUnitTestSuite

## &regression -> Ecs is an autoload, so its world outlives every scene. Before
##                ECSScope, re-entering the train scene left the previous visit's
##                entities in the world and stacked a second set on top.
## &regression -> ECSRunner.remove_system() drops the pool entry but leaves the
##                system node parented to the Ecs autoload, so disposal has to
##                free it or the children pile up per visit.

var _scope: ECSScope


func before_test() -> void:
	_scope = ECSScope.new()


func after_test() -> void:
	_scope.dispose()


func test_dispose_destroys_every_entity_it_spawned() -> void:
	var before := Ecs.world.get_entity_keys().size()
	for i in range(5):
		_scope.spawn().add(CCarriage.new())
	assert_int(Ecs.world.get_entity_keys().size()).is_equal(before + 5)
	_scope.dispose()
	assert_int(Ecs.world.get_entity_keys().size()).override_failure_message(
		"dispose() left entities behind; a re-entered scene would double them"
	).is_equal(before)


func test_dispose_frees_the_system_node_not_just_the_pool_entry() -> void:
	var before := Ecs.get_child_count()
	_scope.add_system(&"scope_test_clock", SClock.new())
	assert_int(Ecs.get_child_count()).is_equal(before + 1)
	_scope.dispose()
	await await_idle_frame()
	assert_int(Ecs.get_child_count()).override_failure_message(
		"the system node is still parented to Ecs; queue_free was skipped"
	).is_equal(before)


func test_dispose_is_safe_to_call_twice() -> void:
	_scope.spawn().add(CCarriage.new())
	_scope.dispose()
	_scope.dispose()


func test_a_second_scope_does_not_inherit_the_first() -> void:
	var before := Ecs.world.get_entity_keys().size()
	_scope.spawn().add(CCarriage.new())
	var second := ECSScope.new()
	second.spawn().add(CCarriage.new())
	second.dispose()
	assert_int(Ecs.world.get_entity_keys().size()).is_equal(before + 1)
