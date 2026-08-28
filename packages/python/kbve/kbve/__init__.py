"""KBVE - a toolbox, installed in pieces.

The base install is pydantic and PyYAML: enough for ``kbve.seo``,
``kbve.models``, and the stdlib-only modules (``kbve.mdx``, ``kbve.svg``,
``kbve.ai``, ``kbve.utils``, ``kbve.config``, ``kbve.tasks``).

Two extras carry the heavy parts:

    pip install 'kbve[server]'    # kbve.api, .grpc, .health, .proto, .server
    pip install 'kbve[blender]'   # the image passes in kbve.blender

Every name exported here belongs to the server stack and is resolved lazily
(PEP 562), so ``import kbve`` costs nothing extra and importing a leaf
subpackage does not drag the stack in. ``from kbve import AppServer`` works
once ``[server]`` is installed, and says so when it is not.
"""

from __future__ import annotations

import importlib
from importlib.metadata import PackageNotFoundError
from importlib.metadata import version as _dist_version
from typing import TYPE_CHECKING

try:
    __version__ = _dist_version("kbve")
except PackageNotFoundError:  # source tree, not installed
    __version__ = "0.0.0+unknown"

_LAZY = {
    "ServerConfig": ".models.server_models",
    "AppServer": ".server.app_server",
    "GrpcServer": ".server.grpc_server",
    "HttpServer": ".server.http_server",
    "HealthServicer": ".server.services.health_service",
    "EchoServicer": ".server.services.echo_service",
    "EnvConfig": ".config",
    "HealthCheck": ".health",
    "HealthStatus": ".health",
    "CheckResult": ".health",
    "TaskRunner": ".tasks",
    "TaskState": ".tasks",
    "TaskResult": ".tasks",
}

__all__ = list(_LAZY)


def __getattr__(name: str):
    module = _LAZY.get(name)
    if module is None:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
    try:
        value = getattr(importlib.import_module(module, __name__), name)
    except ImportError as exc:
        # Every name in _LAZY is part of the server stack, which is an extra.
        # Without this the failure is "No module named 'fastapi'" from three
        # frames down, which says nothing about how to fix it.
        raise ImportError(
            f"kbve.{name} needs the server stack, which is an optional "
            f"install: pip install 'kbve[server]' (missing: {exc.name})"
        ) from exc
    globals()[name] = value
    return value


def __dir__():
    return sorted(set(globals()) | set(__all__))


if TYPE_CHECKING:
    from .config import EnvConfig  # noqa: F401
    from .health import (  # noqa: F401
        CheckResult, HealthCheck, HealthStatus)
    from .models.server_models import ServerConfig  # noqa: F401
    from .server.app_server import AppServer  # noqa: F401
    from .server.grpc_server import GrpcServer  # noqa: F401
    from .server.http_server import HttpServer  # noqa: F401
    from .server.services.echo_service import EchoServicer  # noqa: F401
    from .server.services.health_service import (  # noqa: F401
        HealthServicer)
    from .tasks import (  # noqa: F401
        TaskResult, TaskRunner, TaskState)
