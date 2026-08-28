"""KBVE - Core library for async HTTP and gRPC servers.

Top-level names are resolved lazily (PEP 562) so importing a leaf subpackage
(e.g. ``kbve.config``, ``kbve.utils``) does not drag in the server stack
(pydantic/fastapi/uvicorn/grpc). ``from kbve import AppServer`` still works —
the backing module loads on first attribute access.
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
    value = getattr(importlib.import_module(module, __name__), name)
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
