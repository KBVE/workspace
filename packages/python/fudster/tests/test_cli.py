"""Integration tests for fudster.cli module using Click CliRunner."""

import json

import pytest
from click.testing import CliRunner

from fudster.cli import main


# ── CLI group ────────────────────────────────────────────────────────

def test_cli_help():
    runner = CliRunner()
    result = runner.invoke(main, ["--help"])
    assert result.exit_code == 0
    assert "Fudster CLI" in result.output


# ── version ──────────────────────────────────────────────────────────

def test_version():
    runner = CliRunner()
    result = runner.invoke(main, ["version"])
    assert result.exit_code == 0
    assert "fudster" in result.output
    assert "kbve" in result.output
    # Against the manifest, not a literal. __version__ was hardcoded at 0.1.0
    # while pyproject said 1.0.3, and this test asserted the hardcode -- so it
    # passed for as long as the two disagreed.
    import tomllib
    from pathlib import Path
    manifest = Path(__file__).resolve().parents[1] / "pyproject.toml"
    expected = tomllib.loads(manifest.read_text())["project"]["version"]
    assert expected in result.output


# ── info ─────────────────────────────────────────────────────────────
#
# `info` walks kbve with pkgutil now. It used to read a hand-maintained
# registry in kbve.utils.module_info, and these tests asserted the contents of
# that list -- including kbve.nx, which outlived the module it described.
# Asserting discovery instead means they cannot go stale the same way.

def test_info_lists_modules_that_are_actually_installed():
    runner = CliRunner()
    result = runner.invoke(main, ["info"])
    assert result.exit_code == 0
    # Base install, no extras needed.
    for name in ("kbve.seo", "kbve.mdx", "kbve.svg", "kbve.config"):
        assert name in result.output


def test_info_does_not_invent_modules():
    """The old registry advertised kbve.nx after the module was deleted."""
    runner = CliRunner()
    result = runner.invoke(main, ["info"])
    assert "kbve.nx" not in result.output


def test_info_json_is_a_list_of_records():
    runner = CliRunner()
    result = runner.invoke(main, ["info", "--json"])
    assert result.exit_code == 0
    data = json.loads(result.output)
    assert data, "kbve has submodules; an empty list means discovery failed"
    assert {"name", "description", "available"} <= set(data[0])
    assert all(m["name"].startswith("kbve.") for m in data)


def test_info_reports_server_modules_as_available():
    """fudster depends on kbve[server], so these import here."""
    runner = CliRunner()
    result = runner.invoke(main, ["info", "--json"])
    by_name = {m["name"]: m for m in json.loads(result.output)}
    for name in ("kbve.server", "kbve.grpc", "kbve.health"):
        assert by_name[name]["available"], f"{name}: {by_name[name]['description']}"


def test_info_describes_a_module_from_its_docstring():
    runner = CliRunner()
    result = runner.invoke(main, ["info", "--json"])
    seo = next(m for m in json.loads(result.output) if m["name"] == "kbve.seo")
    assert seo["description"], "descriptions come from each module's own docstring"


# ── serve ────────────────────────────────────────────────────────────

def test_serve_help():
    runner = CliRunner()
    result = runner.invoke(main, ["serve", "--help"])
    assert result.exit_code == 0
    assert "--host" in result.output
    assert "--port" in result.output
    assert "--grpc-port" in result.output
    assert "--env-file" in result.output


# ── config ───────────────────────────────────────────────────────────

def test_config_empty():
    runner = CliRunner()
    result = runner.invoke(main, ["config"])
    assert result.exit_code == 0


def test_config_with_env_file(tmp_path):
    f = tmp_path / ".env"
    f.write_text("TESTCLI_PORT=9090\nTESTCLI_HOST=127.0.0.1\n")

    runner = CliRunner()
    result = runner.invoke(main, [
        "config",
        "--env-file", str(f),
        "--prefix", "TESTCLI",
    ])
    assert result.exit_code == 0
    assert "port" in result.output
    assert "9090" in result.output


def test_config_json(tmp_path):
    f = tmp_path / ".env"
    f.write_text("JSONCFG_A=1\nJSONCFG_B=two\n")

    runner = CliRunner()
    result = runner.invoke(main, [
        "config",
        "--env-file", str(f),
        "--prefix", "JSONCFG",
        "--json",
    ])
    assert result.exit_code == 0
    data = json.loads(result.output)
    assert data["a"] == "1"
    assert data["b"] == "two"


# ── grpc subgroup ────────────────────────────────────────────────────

def test_grpc_help():
    runner = CliRunner()
    result = runner.invoke(main, ["grpc", "--help"])
    assert result.exit_code == 0
    assert "health" in result.output
    assert "compile" in result.output


def test_grpc_health_unreachable():
    runner = CliRunner()
    result = runner.invoke(main, [
        "grpc", "health", "localhost:1", "--timeout", "0.5",
    ])
    assert result.exit_code != 0
    assert "UNREACHABLE" in result.output or "ERROR" in result.output


def _has_grpc_tools():
    try:
        import grpc_tools  # noqa: F401
        return True
    except ImportError:
        return False


@pytest.mark.skipif(
    not _has_grpc_tools(),
    reason="grpcio-tools not installed",
)
def test_grpc_compile_success(tmp_path):
    proto_file = tmp_path / "cli_test.proto"
    proto_file.write_text(
        'syntax = "proto3";\n'
        "package clipkg;\n"
        "message CliMsg { string v = 1; }\n"
    )

    runner = CliRunner()
    result = runner.invoke(main, [
        "grpc", "compile",
        str(proto_file),
        "--proto-path", str(tmp_path),
        "--python-out", str(tmp_path),
    ])
    assert result.exit_code == 0
    assert "Compiled" in result.output
    assert (tmp_path / "cli_test_pb2.py").exists()


@pytest.mark.skipif(
    not _has_grpc_tools(),
    reason="grpcio-tools not installed",
)
def test_grpc_compile_bad_proto(tmp_path):
    proto_file = tmp_path / "bad.proto"
    proto_file.write_text("invalid proto")

    runner = CliRunner()
    result = runner.invoke(main, [
        "grpc", "compile",
        str(proto_file),
        "--proto-path", str(tmp_path),
        "--python-out", str(tmp_path),
    ])
    assert result.exit_code != 0
    assert "failed" in result.output


def test_grpc_compile_help():
    runner = CliRunner()
    result = runner.invoke(main, ["grpc", "compile", "--help"])
    assert result.exit_code == 0
    assert "--proto-path" in result.output
    assert "--grpc-out" in result.output
    assert "--pyi-out" in result.output


# ── claude subgroup ──────────────────────────────────────────────────

def test_claude_help():
    runner = CliRunner()
    result = runner.invoke(main, ["claude", "--help"])
    assert result.exit_code == 0
    assert "usage" in result.output
    assert "version" in result.output
    assert "status" in result.output


def test_claude_version():
    runner = CliRunner()
    result = runner.invoke(main, ["claude", "version"])
    # Should work if claude is installed, or fail gracefully
    assert isinstance(result.output, str)


def test_claude_usage_json():
    runner = CliRunner()
    result = runner.invoke(main, ["claude", "usage", "--json"])
    assert result.exit_code == 0
    data = json.loads(result.output)
    assert "available" in data
    assert "cost_usd" in data
    assert "error" in data


def test_claude_status_json():
    runner = CliRunner()
    result = runner.invoke(main, ["claude", "status", "--json"])
    assert result.exit_code == 0
    data = json.loads(result.output)
    assert "installed" in data
    assert "version" in data
    assert "usage_available" in data


def test_claude_usage_help():
    runner = CliRunner()
    result = runner.invoke(main, ["claude", "usage", "--help"])
    assert result.exit_code == 0
    assert "--json" in result.output
    assert "--timeout" in result.output
