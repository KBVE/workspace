"""Fudster CLI - a thin wrapper around the kbve core modules.

Entry point: ``fudster`` (registered via ``[project.scripts]``).

    fudster info
    fudster serve --host 0.0.0.0 --port 8086
    fudster claude usage
    fudster grpc health --target localhost:50051
    fudster gdrive pdf-to-md <file-id>

The `nx` sub-group did not come across from the Nx workspace. It rendered the
project graph and the security audit into Starlight MDX by way of
``kbve.nx.graph`` and ``kbve.nx.security``, and neither the module nor the Nx
graph it read exists here -- moon replaced both.
"""

from __future__ import annotations

import json

import click


# ── Root CLI group ───────────────────────────────────────────────────

@click.group()
def main() -> None:
    """Fudster CLI — workspace tooling powered by kbve core."""


# ── version ──────────────────────────────────────────────────────────

@main.command()
def version() -> None:
    """Show fudster and kbve versions."""
    import fudster as _fudster
    from kbve import __version__ as _kbve_version
    click.echo(f"fudster {_fudster.__version__}")
    click.echo(f"kbve    {_kbve_version}")


# ── info ─────────────────────────────────────────────────────────────

@main.command()
@click.option(
    "--json", "as_json", is_flag=True, default=False,
    help="Output as JSON instead of a table.",
)
def info(as_json: bool) -> None:
    """Show the kbve modules installed here and whether each imports.

    Discovered rather than listed. This read a hand-maintained registry in
    kbve.utils.module_info, which had to be edited in step with the package and
    was not: it still advertised kbve.nx after the module was gone. Walking the
    package cannot drift, and the description comes from each module's own
    docstring, which is where it was going to be written anyway.

    "missing" is the useful column: most of kbve is behind the [server] and
    [blender] extras, so a module that does not import here usually means an
    extra that is not installed rather than anything broken.
    """
    import importlib
    import pkgutil

    import kbve

    modules = []
    for found in sorted(pkgutil.iter_modules(kbve.__path__),
                        key=lambda m: m.name):
        name = f"kbve.{found.name}"
        try:
            doc = (importlib.import_module(name).__doc__ or "").strip()
            description = doc.splitlines()[0] if doc else ""
            available = True
        except Exception as exc:  # noqa: BLE001 - report it, do not raise
            description = f"{type(exc).__name__}: {exc}"
            available = False
        modules.append({"name": name, "description": description,
                        "available": available})

    if as_json:
        import json as _json
        click.echo(_json.dumps(modules, indent=2))
    else:
        click.echo("kbve modules:\n")
        for m in modules:
            status = click.style("ok", fg="green") if m["available"] \
                else click.style("missing", fg="red")
            click.echo(f"  [{status}] {m['name']}")
            if m["description"]:
                click.echo(f"         {m['description']}")
        click.echo()


# ── serve ─────────────────────────────────────────────────────────────

@main.command()
@click.option("--host", default="0.0.0.0", help="Bind host.")
@click.option("--port", default=8000, type=int, help="HTTP port.")
@click.option("--grpc-port", default=50051, type=int, help="gRPC port.")
@click.option("--log-level", default="info", help="Log level.")
@click.option(
    "--env-file", type=click.Path(), default=None,
    help="Path to .env file for config.",
)
def serve(
    host: str, port: int, grpc_port: int,
    log_level: str, env_file: str | None,
) -> None:
    """Start a kbve microservice with health checks."""
    import asyncio
    from kbve import AppServer, ServerConfig
    from kbve.config import apply_env_file
    from kbve.health import HealthCheck, create_health_router

    if env_file:
        loaded = apply_env_file(env_file)
        click.echo(f"Loaded {loaded} vars from {env_file}")

    config = ServerConfig(
        http_host=host,
        http_port=port,
        grpc_host=host,
        grpc_port=grpc_port,
        log_level=log_level,
    )

    hc = HealthCheck()
    hc.add("self", lambda: True)

    server = AppServer(config=config)
    router = create_health_router(hc)
    server.http.app.include_router(router)

    addr = host + ":" + str(port)
    click.echo(
        f"Starting kbve server on {addr}"
        f" (gRPC: {grpc_port})"
    )
    asyncio.run(server.serve())


# ── config ───────────────────────────────────────────────────────────

@main.command("config")
@click.option(
    "--env-file", type=click.Path(exists=True), default=None,
    help="Path to .env file.",
)
@click.option("--prefix", default="", help="Env var prefix to filter.")
@click.option(
    "--json", "as_json", is_flag=True, default=False,
    help="Output as JSON.",
)
def config_cmd(
    env_file: str | None, prefix: str, as_json: bool,
) -> None:
    """Show resolved configuration from environment and .env files."""
    from kbve.config import EnvConfig

    cfg = EnvConfig.from_env(
        prefix=prefix,
        env_file=env_file,
    )

    if as_json:
        click.echo(json.dumps(cfg.as_dict(), indent=2))
    else:
        values = cfg.as_dict()
        if not values:
            click.echo("No configuration values found.")
            return
        pfx = f" (prefix: {prefix})" if prefix else ""
        header = "Configuration" + pfx
        click.echo(header + ":\n")
        for key, val in sorted(values.items()):
            click.echo(f"  {key} = {val}")
        click.echo()


# ── claude sub-group ─────────────────────────────────────────────────

@main.group("claude")
def claude_group() -> None:
    """Claude Code utilities — usage tracking, version info."""


@claude_group.command("usage")
@click.option(
    "--json", "as_json", is_flag=True, default=False,
    help="Output as JSON.",
)
@click.option(
    "--timeout", default=15.0, type=float,
    help="Timeout in seconds.",
)
def claude_usage(as_json: bool, timeout: float) -> None:
    """Show Claude Code usage for the current session."""
    from kbve.ai.claude import get_usage

    usage = get_usage(timeout=timeout)

    if as_json:
        click.echo(json.dumps(usage.as_dict(), indent=2))
    elif usage.error:
        click.secho(f"Error: {usage.error}", fg="red")
    else:
        click.echo("Claude Code usage:\n")
        if usage.cost_usd is not None:
            click.echo("  Cost: $" + format(usage.cost_usd, ".4f"))
        if usage.total_tokens is not None:
            click.echo("  Total tokens: " + format(usage.total_tokens, ","))
        if usage.input_tokens is not None:
            click.echo("  Input tokens: " + format(usage.input_tokens, ","))
        if usage.output_tokens is not None:
            click.echo("  Output tokens: " + format(usage.output_tokens, ","))
        if usage.cache_read_tokens is not None:
            click.echo(
                "  Cache read: " + format(usage.cache_read_tokens, ",")
            )
        if usage.cache_write_tokens is not None:
            click.echo(
                "  Cache write: " + format(usage.cache_write_tokens, ",")
            )
        if usage.percent_used is not None:
            click.echo(f"  Used: {usage.percent_used}%")
        if usage.duration_s is not None:
            click.echo(f"  Duration: {usage.duration_s}s")
        click.echo()


@claude_group.command("version")
def claude_version() -> None:
    """Show installed Claude Code version."""
    from kbve.ai.claude import get_claude_version

    result = get_claude_version()
    if result.success:
        click.echo(f"Claude Code: {result.stdout}")
    else:
        click.secho(f"Error: {result.stderr}", fg="red")
        raise SystemExit(1)


@claude_group.command("status")
@click.option(
    "--json", "as_json", is_flag=True, default=False,
    help="Output as JSON.",
)
def claude_status(as_json: bool) -> None:
    """Check if Claude Code is available and report status."""
    from kbve.ai.claude import get_claude_version, get_usage

    ver = get_claude_version()
    usage = get_usage(timeout=5.0)

    status = {
        "installed": ver.success,
        "version": ver.stdout if ver.success else None,
        "usage_available": usage.available and usage.error is None,
        "cost_usd": usage.cost_usd,
        "percent_used": usage.percent_used,
    }

    if as_json:
        click.echo(json.dumps(status, indent=2))
    else:
        if ver.success:
            click.secho(f"  Claude Code: {ver.stdout}", fg="green")
        else:
            click.secho("  Claude Code: not found", fg="red")

        if usage.available and usage.error is None:
            if usage.cost_usd is not None:
                click.echo("  Cost: $" + format(usage.cost_usd, ".4f"))
            if usage.percent_used is not None:
                click.echo(f"  Used: {usage.percent_used}%")
        elif usage.error:
            click.echo(f"  Usage: {usage.error}")
        click.echo()


# ── grpc sub-group ───────────────────────────────────────────────────

@main.group("grpc")
def grpc_group() -> None:
    """gRPC utilities — health check, proto compilation."""


@grpc_group.command("health")
@click.argument("target", default="localhost:50051")
@click.option("--timeout", default=5.0, type=float, help="Timeout in seconds.")
def grpc_health(target: str, timeout: float) -> None:
    """Check gRPC health of a remote server."""
    import asyncio
    from kbve.grpc.client import check_health

    result = asyncio.run(check_health(target, timeout=timeout))
    if result["healthy"]:
        click.secho(
            f"  {target} -> {result['status']}", fg="green",
        )
    else:
        err = result.get("error", "")
        msg = f"  {target} -> {result['status']}"
        if err:
            msg += f" ({err})"
        click.secho(msg, fg="red")
    raise SystemExit(0 if result["healthy"] else 1)


@grpc_group.command("compile")
@click.argument("proto_files", nargs=-1, required=True)
@click.option(
    "--proto-path", default=".", type=click.Path(exists=True),
    help="Directory to search for imports.",
)
@click.option(
    "--python-out", default=".", type=click.Path(),
    help="Output directory for _pb2.py files.",
)
@click.option(
    "--grpc-out", default=None, type=click.Path(),
    help="Output directory for _pb2_grpc.py files.",
)
@click.option(
    "--pyi-out", default=None, type=click.Path(),
    help="Output directory for .pyi type stubs.",
)
def grpc_compile(
    proto_files: tuple[str, ...],
    proto_path: str,
    python_out: str,
    grpc_out: str | None,
    pyi_out: str | None,
) -> None:
    """Compile .proto files to Python."""
    from kbve.grpc.compiler import compile_proto

    exit_code = compile_proto(
        proto_files=list(proto_files),
        proto_path=proto_path,
        python_out=python_out,
        grpc_out=grpc_out,
        pyi_out=pyi_out,
    )
    if exit_code == 0:
        click.secho(
            f"Compiled {len(proto_files)} proto file(s)", fg="green",
        )
    else:
        msg = "Proto compilation failed (exit " + str(exit_code) + ")"
        click.secho(msg, fg="red")
    raise SystemExit(exit_code)


# ── gdrive sub-group ────────────────────────────────────────────────

@main.group("gdrive")
def gdrive_group() -> None:
    """Google Drive utilities — PDF extraction, conversion."""


@gdrive_group.command("pdf-to-md")
@click.argument("url")
@click.option(
    "--output", "-o", type=click.Path(), default=None,
    help="Write Markdown to a file instead of stdout.",
)
@click.option(
    "--image-dir", type=click.Path(), default=None,
    help="Directory to save extracted page images.",
)
@click.option(
    "--no-ocr", is_flag=True, default=False,
    help="Skip OCR even if pytesseract is available.",
)
@click.option(
    "--headed", is_flag=True, default=False,
    help="Run the browser with a visible window.",
)
@click.option(
    "--scroll-pause", type=float, default=0.6,
    help="Seconds between scroll steps (default: 0.6).",
)
def gdrive_pdf_to_md(
    url: str,
    output: str | None,
    image_dir: str | None,
    no_ocr: bool,
    headed: bool,
    scroll_pause: float,
) -> None:
    """Extract a view-only Google Drive PDF and convert to Markdown.

    Accepts a Google Drive share/view link, opens it in a headless
    browser, captures every rendered page image, and produces Markdown
    output (with OCR text when pytesseract is installed).

    \b
    Example:
        fudster gdrive pdf-to-md "https://drive.google.com/file/d/ABC123/view"
        fudster gdrive pdf-to-md URL -o output.md --image-dir ./pages
    """
    from fudster.apps.gdrive_pdf import extract_gdrive_pdf

    click.echo(f"Extracting PDF from: {url}")

    try:
        md = extract_gdrive_pdf(
            url,
            headless=not headed,
            output_dir=image_dir,
            scroll_pause=scroll_pause,
            use_ocr=not no_ocr,
        )
    except ValueError as exc:
        click.secho(f"Error: {exc}", fg="red")
        raise SystemExit(1)
    except ImportError as exc:
        click.secho(f"Missing dependency: {exc}", fg="red")
        raise SystemExit(1)

    if output:
        from pathlib import Path
        Path(output).write_text(md, encoding="utf-8")
        click.secho(f"Markdown written to {output}", fg="green")
    else:
        click.echo(md)
