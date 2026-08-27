godot-gdunit-labs/gdUnit4 v6.2.1 (08ffc7c65b61b1b2edd545616061a99973c13ce1), MIT.

addons/gdUnit4/test was removed - that is gdUnit4's own self-test suite, ~2MB we
do not run. Everything else is upstream and untouched.

The whole addon is excluded from every export preset: plugin.gd is an @tool
EditorPlugin, and the asserts and runners have no business in a shipped build.
