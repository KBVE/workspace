"""ArgoCD Application annotation and Kubernetes label management.

Two passes over a directory of ArgoCD ``Application`` YAML, both pure file
manipulation: no cluster, no kubectl, no network. That is what lets them run in
CI on a pull request rather than against a live cluster.

:class:`AnnotationManager` writes and checks the ``kbve.com/*`` annotations on
each Application -- source path, manifest path, category, stack, schema
version -- deriving category and stack from the directory the Application sits
in. :class:`ResourceLabeler` reads those annotations back and propagates them
onto the Kubernetes resources the Application points at, so a resource in the
cluster carries the same provenance its Application declares.

Both take the directory to walk as an argument. It defaulted to ``apps/kube``,
which is a path in the Nx workspace and nowhere else, so the default is gone
rather than pointing every invocation at something that does not exist.

    kbve-argocd-annotate --mode validate --apps-dir <dir>
    kbve-argocd-label    --mode drift    --apps-dir <dir>

Exit status matches the rest of the package: 0 clean, 1 findings that should
block, 2 the tool could not run.
"""

from .annotate import AnnotationManager  # noqa: F401
from .label_resources import ResourceLabeler  # noqa: F401

__all__ = ["AnnotationManager", "ResourceLabeler"]
