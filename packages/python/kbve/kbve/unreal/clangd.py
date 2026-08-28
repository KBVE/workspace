import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from .ubt import (EngineNotFound, generate_clang_db_command, host_platform,
                  resolve_engine_root)


def write_clangd_pointer(repo_root: Path, db_dir: Path) -> Path:
    rel = Path(db_dir).resolve().relative_to(Path(repo_root).resolve())
    out = Path(repo_root) / ".clangd"
    out.write_text("CompileFlags:\n  CompilationDatabase: " + str(rel) + "\n")
    return out


def locate_generated_db(engine_root: Path, project_dir: Path) -> Path | None:
    for candidate in [
        Path(project_dir) / "compile_commands.json",
        Path(engine_root) / "compile_commands.json",
    ]:
        if candidate.exists():
            return candidate
    return None


def find_repo_root(start: Path) -> Path:
    for root in [start, *start.parents]:
        if (root / ".git").exists():
            return root
    return start


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="kbve-unreal-clangd")
    # Both of these named one project in one repository -- the .uproject path
    # and `chuckEditor`, a UBT target belonging to a game that is not even the
    # one the path pointed at. A default that is wrong everywhere but one
    # checkout is worse than no default: it turns "you did not say which
    # project" into "that file does not exist".
    parser.add_argument("--project", required=True,
                        help=".uproject to generate a database for, "
                             "relative to the repository root")
    parser.add_argument("--target", required=True,
                        help="UBT target name, e.g. <Game>Editor")
    parser.add_argument("--config", default="Development")
    parser.add_argument("--platform", default=host_platform(),
                        help="UBT target platform (default: this host)")
    parser.add_argument("--engine-root")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    repo_root = find_repo_root(Path.cwd().resolve())
    uproject = (repo_root / args.project).resolve()
    if not uproject.exists():
        print(f"uproject not found: {uproject}", file=sys.stderr)
        return 2

    try:
        engine_root = resolve_engine_root(
            uproject,
            override=Path(args.engine_root) if args.engine_root else None,
        )
    except EngineNotFound as exc:
        print(str(exc), file=sys.stderr)
        return 2
    if not args.dry_run and not engine_root.exists():
        print(
            f"engine not found: {engine_root} (override with --engine-root or KBVE_UE_ROOT)",
            file=sys.stderr,
        )
        return 2

    cmd = generate_clang_db_command(
        engine_root=engine_root,
        uproject=uproject,
        target=args.target,
        config=args.config,
        platform=args.platform,
    )
    if args.dry_run:
        print(" ".join(cmd))
        return 0

    result = subprocess.run(cmd)
    if result.returncode != 0:
        print(f"UBT failed with exit code {result.returncode}", file=sys.stderr)
        return result.returncode

    project_dir = uproject.parent
    db = locate_generated_db(engine_root, project_dir)
    if db is None:
        print("UBT succeeded but compile_commands.json not found", file=sys.stderr)
        return 2
    target_db = project_dir / "compile_commands.json"
    if db != target_db:
        shutil.move(str(db), str(target_db))

    pointer = write_clangd_pointer(repo_root, project_dir)
    print(f"database: {target_db}")
    print(f"pointer:  {pointer}")
    return 0
