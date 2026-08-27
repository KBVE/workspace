cmake_minimum_required(VERSION 3.21)

# &why -> the build is three tools that have to run in one order:

# &parity -> the `ci` target runs what .github/workflows/release-itch.yml runs.

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/godot/project.godot" _project_godot)
string(REGEX MATCH "config/version=\"([0-9]+\\.[0-9]+\\.[0-9]+)\"" _ "${_project_godot}")
set(GAME_VERSION "${CMAKE_MATCH_1}")

project(gilded_gazette VERSION ${GAME_VERSION} LANGUAGES NONE)

set(WEB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vite")
set(GODOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/godot")

find_program(NPM_EXECUTABLE NAMES npm REQUIRED)
find_program(GODOT_EXECUTABLE NAMES godot godot4 Godot
  DOC "Godot 4.7 editor binary; templates required for the web export")
if(NOT GODOT_EXECUTABLE)
  message(FATAL_ERROR "godot not found. Pass -DGODOT_EXECUTABLE=/path/to/godot")
endif()

message(STATUS "gilded-gazette ${GAME_VERSION}")
message(STATUS "  npm   ${NPM_EXECUTABLE}")
message(STATUS "  godot ${GODOT_EXECUTABLE}")

set(GODOT_HEADLESS ${GODOT_EXECUTABLE} --headless --path ${GODOT_DIR})

# ---- &deps : node modules | browsers ----

add_custom_target(deps
  COMMAND ${NPM_EXECUTABLE} ci
  WORKING_DIRECTORY ${WEB_DIR}
  COMMENT "npm ci")

add_custom_target(browsers
  COMMAND ${NPM_EXECUTABLE} exec -- playwright install --with-deps chromium
  WORKING_DIRECTORY ${WEB_DIR}
  COMMENT "installing the Playwright chromium")

# ---- &codegen : shared/ -> both runtimes ----

# &one -> shared/state.json, shared/events.json and shared/data are compiled into
#         godot/scripts/ecs/*.gd and vite/src/**. Never edit the outputs.
add_custom_target(gen
  COMMAND ${NPM_EXECUTABLE} run gen
  WORKING_DIRECTORY ${WEB_DIR}
  COMMENT "generating contract + content")

add_custom_target(gen-check
  COMMAND ${NPM_EXECUTABLE} run gen:check
  WORKING_DIRECTORY ${WEB_DIR}
  COMMENT "checking generated files are current")

# ---- &godot : import | scene | test | export ----

# &first -> a new class_name is not in the global cache until an import runs, and
#           build_train_scene.gd saves a scene with NO script attached if the
#           script it loads fails to parse. Import before anything that builds.
add_custom_target(godot-import
  COMMAND ${GODOT_HEADLESS} --import
  COMMENT "importing Godot assets")

# &generated -> scenes/train/train.scn is built, not hand-edited. OVERWRITE=1 or
#               the builder refuses and writes train_generated.scn instead.
add_custom_target(scene
  COMMAND ${CMAKE_COMMAND} -E env OVERWRITE=1
          ${GODOT_HEADLESS} -s res://tools/build_train_scene.gd --quit-after 5
  COMMENT "rebuilding scenes/train/train.scn")
add_dependencies(scene godot-import)

add_custom_target(godot-test
  COMMAND ${GODOT_HEADLESS} -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd
          --ignoreHeadlessMode -a res://tests
  COMMENT "gdUnit4 suite")
add_dependencies(godot-test godot-import)

# &shell -> build:shell emits godot/web/shell.html, which the export template
#           consumes, so it has to run before the export and not after.
add_custom_target(web-shell
  COMMAND ${NPM_EXECUTABLE} run build:shell
  WORKING_DIRECTORY ${WEB_DIR}
  COMMENT "building the Godot web shell")

# &into -> the export lands in vite/public/godot, so vite must build AFTER this.
add_custom_target(godot-export
  COMMAND ${GODOT_EXECUTABLE} --headless --path ${GODOT_DIR}
          --export-release "Web" ${WEB_DIR}/public/godot/index.html
  COMMENT "exporting Godot to vite/public/godot")
add_dependencies(godot-export web-shell godot-import)

# ---- &web : typecheck | build | e2e ----

add_custom_target(web-typecheck
  COMMAND ${NPM_EXECUTABLE} run typecheck
  WORKING_DIRECTORY ${WEB_DIR}
  COMMENT "tsc --noEmit")

add_custom_target(web-build
  COMMAND ${NPM_EXECUTABLE} run build
  WORKING_DIRECTORY ${WEB_DIR}
  COMMENT "vite build")
add_dependencies(web-build godot-export)

# &serves -> playwright.config.ts starts e2e/server.mjs over vite/dist, so the
#            web build has to exist first or every spec times out on a 404.
add_custom_target(e2e
  COMMAND ${NPM_EXECUTABLE} run e2e
  WORKING_DIRECTORY ${WEB_DIR}
  COMMENT "Playwright end to end")
add_dependencies(e2e web-build)

# ---- &aggregate ----

add_custom_target(check)
add_dependencies(check gen-check web-typecheck godot-test)

add_custom_target(test)
add_dependencies(test godot-test e2e)

# &order -> gen-check, then Godot, then web, then e2e. Same as the release
#           workflow, so a green `ci` here means a green push.
add_custom_target(ci)
add_dependencies(ci gen-check godot-test e2e)

add_custom_target(clean-artifacts
  COMMAND ${CMAKE_COMMAND} -E rm -rf ${WEB_DIR}/dist ${WEB_DIR}/public/godot
          ${GODOT_DIR}/.godot ${GODOT_DIR}/reports
  COMMENT "removing dist, the exported pck and the Godot import cache")
