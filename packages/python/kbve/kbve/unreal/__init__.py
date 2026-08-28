"""Unreal Engine tooling: a compile database, and syntax checks against it.

Two commands, both stdlib only. They shell out to Unreal Build Tool and to the
clang invocation UBT recorded; nothing here imports an engine binding, so the
package installs and imports on a machine with no engine at all.

    kbve-unreal-clangd --project <path.uproject> --target <Game>Editor
    kbve-unreal-check  Source/Game/Private/Thing.cpp

`clangd` asks UBT for a compile_commands.json, moves it next to the .uproject,
and writes a `.clangd` at the repository root pointing at it -- which is what
makes an editor's language server work in an Unreal tree.

`check` reads that database back and re-runs a single file's own compile
command with -fsyntax-only, which is the difference between a syntax check and
a twenty-minute build. Headers are not in the database because nothing compiles
them directly, so a header resolves to a sibling translation unit -- its .cpp,
or one in the matching Private/ directory, or anything in the same module --
and is force-included into it.

Exit status: 0 clean, 1 diagnostics, 2 the tool could not run.
"""

from .check import build_check_invocation, default_db_path  # noqa: F401
from .ubt import (EngineNotFound, build_script,  # noqa: F401
                  generate_clang_db_command, host_platform,
                  parse_engine_association, resolve_engine_root)

__all__ = [
    "EngineNotFound",
    "build_check_invocation",
    "build_script",
    "default_db_path",
    "generate_clang_db_command",
    "host_platform",
    "parse_engine_association",
    "resolve_engine_root",
]
