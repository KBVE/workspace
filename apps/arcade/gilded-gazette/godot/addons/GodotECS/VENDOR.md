godothub/godot-ecs vendored at 5f3eca675b2db99369048640755682ca41315e5d (2026-08-22), MIT.
test_suite.gd and test_scheduler.gd removed - they are the upstream demo harness.

Local patch: QueryCache stores the world as a WeakRef, not a strong reference.
Upstream AGENTS.md requires it ("Never store World or Entity references directly;
use WeakRef") and ECSEntity/ECSComponent already comply; QueryCache did not, so any
world that served a multi_view() was a world <-> cache cycle and never freed.
