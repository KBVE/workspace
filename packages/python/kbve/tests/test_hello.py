"""KBVE package basic tests."""

import tomllib
from pathlib import Path

import kbve


def test_version_matches_manifest():
    """__version__ comes from the installed distribution, not a literal.

    Upstream hardcoded "0.1.0" here while pyproject.toml said 1.0.14 and a
    version.toml said 1.0.14 again -- three claims, two of them wrong, and
    nothing checking. This asserts the one remaining claim against the manifest
    so a bump cannot be half-applied.
    """
    manifest = Path(__file__).resolve().parents[1] / "pyproject.toml"
    expected = tomllib.loads(manifest.read_text())["project"]["version"]
    assert kbve.__version__ == expected


def test_exports():
    """Test that primary exports are available."""
    assert kbve.ServerConfig is not None
    assert kbve.AppServer is not None
    assert kbve.GrpcServer is not None
    assert kbve.HttpServer is not None
    assert kbve.HealthServicer is not None
    assert kbve.EchoServicer is not None
