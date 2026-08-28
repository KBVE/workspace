"""Tests for kbve.argocd.

The module arrived with none. These cover the annotation schema, the label
propagation, and above all the exit codes -- both entry points returned None
unconditionally, so `--mode validate` printed a wall of red crosses and passed.
"""

from __future__ import annotations

import sys
import textwrap
from pathlib import Path

import pytest
import yaml

from kbve.argocd import AnnotationManager, ResourceLabeler
from kbve.argocd import annotate as annotate_mod
from kbve.argocd import label_resources as label_mod


def app_yaml(path: Path, *, annotations: dict | None = None,
             source_path: str = "apps/kube/cnpg", name: str = "app") -> Path:
    """Write an ArgoCD Application manifest."""
    doc = {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Application",
        "metadata": {"name": name},
        "spec": {"source": {"path": source_path}},
    }
    if annotations:
        doc["metadata"]["annotations"] = annotations
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(doc), encoding="utf-8")
    return path


def cli(monkeypatch, module, argv):
    monkeypatch.setattr(sys, "argv", [module.__name__, *argv])
    return module.main()


# ── AnnotationManager ────────────────────────────────────────────────

def test_finds_application_files(tmp_path):
    app_yaml(tmp_path / "cnpg" / "application.yaml")
    app_yaml(tmp_path / "cilium" / "application.yaml")
    (tmp_path / "cnpg" / "notes.txt").write_text("not yaml")
    assert len(AnnotationManager(tmp_path).find_application_files()) == 2


def test_category_and_stack_come_from_the_directory(tmp_path):
    """cnpg is a database and cilium is networking; the path is the only clue."""
    path = app_yaml(tmp_path / "cnpg" / "application.yaml")
    manager = AnnotationManager(tmp_path)
    meta = manager.extract_metadata(path, manager.parse_yaml(path))
    assert meta["kbve.com/category"] == "database"

    path = app_yaml(tmp_path / "cilium" / "application.yaml")
    meta = manager.extract_metadata(path, manager.parse_yaml(path))
    assert meta["kbve.com/category"] == "networking"
    assert meta["kbve.com/stack"] == "cilium"


def test_unknown_directory_falls_back_to_defaults(tmp_path):
    path = app_yaml(tmp_path / "something-new" / "application.yaml")
    manager = AnnotationManager(tmp_path)
    meta = manager.extract_metadata(path, manager.parse_yaml(path))
    assert meta["kbve.com/category"] == "application"
    assert meta["kbve.com/stack"] == "core"


def test_validate_requires_the_whole_schema(tmp_path):
    manager = AnnotationManager(tmp_path)
    ok, errors = manager.validate_annotations({})
    assert not ok
    assert any("source-path" in e for e in errors)


def test_validate_rejects_a_stale_schema_version(tmp_path):
    manager = AnnotationManager(tmp_path)
    ok, errors = manager.validate_annotations({
        "kbve.com/source-path": "a",
        "kbve.com/manifest-path": "a",
        "kbve.com/application-file": "a",
        "kbve.com/managed-by": "argocd",
        "kbve.com/schema-version": "v0",
    })
    assert not ok
    assert any("schema version" in e.lower() for e in errors)


def test_add_annotations_writes_them(tmp_path):
    path = app_yaml(tmp_path / "cnpg" / "application.yaml")
    AnnotationManager(tmp_path).add_annotations(path, dry_run=False)
    written = yaml.safe_load(path.read_text())["metadata"]["annotations"]
    assert written["kbve.com/managed-by"] == "argocd"
    assert written["kbve.com/schema-version"] == annotate_mod.SCHEMA_VERSION


def test_add_annotations_dry_run_changes_nothing(tmp_path):
    path = app_yaml(tmp_path / "cnpg" / "application.yaml")
    before = path.read_text()
    AnnotationManager(tmp_path).add_annotations(path, dry_run=True)
    assert path.read_text() == before


def test_malformed_yaml_does_not_stop_the_walk(tmp_path):
    app_yaml(tmp_path / "good" / "application.yaml")
    bad = tmp_path / "bad" / "application.yaml"
    bad.parent.mkdir(parents=True)
    bad.write_text("kind: [unclosed\n")
    manager = AnnotationManager(tmp_path)
    assert manager.parse_yaml(bad) is None
    assert manager.run("validate")["total"] == 2


# ── exit codes ───────────────────────────────────────────────────────
#
# The whole reason these entry points are worth having in CI.

def test_annotate_validate_fails_on_missing_annotations(monkeypatch, tmp_path):
    app_yaml(tmp_path / "cnpg" / "application.yaml")
    assert cli(monkeypatch, annotate_mod,
               ["--mode", "validate", "--apps-dir", str(tmp_path)]) == 1


def test_annotate_validate_passes_once_annotated(monkeypatch, tmp_path):
    path = app_yaml(tmp_path / "cnpg" / "application.yaml")
    AnnotationManager(tmp_path).add_annotations(path, dry_run=False)
    assert cli(monkeypatch, annotate_mod,
               ["--mode", "validate", "--apps-dir", str(tmp_path)]) == 0


def test_annotate_add_succeeds_even_though_it_changed_files(monkeypatch, tmp_path):
    """add is a fixer, not a gate; writing annotations is success."""
    app_yaml(tmp_path / "cnpg" / "application.yaml")
    assert cli(monkeypatch, annotate_mod,
               ["--mode", "add", "--apps-dir", str(tmp_path)]) == 0


def test_annotate_exits_two_on_a_missing_directory(monkeypatch, tmp_path, capsys):
    code = cli(monkeypatch, annotate_mod,
               ["--mode", "validate", "--apps-dir", str(tmp_path / "nope")])
    assert code == 2
    assert "no directory at" in capsys.readouterr().err


def test_apps_dir_is_required(monkeypatch, tmp_path):
    """It defaulted to apps/kube, a path that exists in one repository."""
    with pytest.raises(SystemExit) as excinfo:
        cli(monkeypatch, annotate_mod, ["--mode", "validate"])
    assert excinfo.value.code == 2


def test_label_rejects_the_modes_that_were_never_implemented(monkeypatch, tmp_path):
    """They were `pass` with a TODO, and exited 0 looking like a clean run."""
    for mode in ("validate", "report"):
        with pytest.raises(SystemExit):
            cli(monkeypatch, label_mod,
                ["--mode", mode, "--apps-dir", str(tmp_path)])


def test_label_exits_two_on_a_missing_directory(monkeypatch, tmp_path, capsys):
    assert cli(monkeypatch, label_mod,
               ["--mode", "label", "--apps-dir", str(tmp_path / "nope")]) == 2
    assert "no directory at" in capsys.readouterr().err


# ── ResourceLabeler ──────────────────────────────────────────────────

ANNOTATED = {
    "kbve.com/source-path": "apps/kube/cnpg",
    "kbve.com/manifest-path": "apps/kube/cnpg",
    "kbve.com/application-file": "application.yaml",
    "kbve.com/managed-by": "argocd",
    "kbve.com/schema-version": "v1",
    "kbve.com/category": "database",
    "kbve.com/stack": "cnpg",
}


def manifest(path: Path, kind: str = "Deployment", name: str = "db") -> Path:
    """Write a Kubernetes manifest.

    ResourceLabeler only looks in manifests/, manifest/ and k8s/ beside the
    Application, so where this lands is part of what is being tested.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(f"""
        apiVersion: apps/v1
        kind: {kind}
        metadata:
          name: {name}
    """).lstrip(), encoding="utf-8")
    return path


def test_labeler_reads_annotations_back_off_the_application(tmp_path):
    app = app_yaml(tmp_path / "cnpg" / "application.yaml", annotations=ANNOTATED)
    labeler = ResourceLabeler(tmp_path)
    assert labeler.read_argocd_annotations(app)["kbve.com/stack"] == "cnpg"


def test_labeler_turns_annotations_into_labels(tmp_path):
    labels = ResourceLabeler(tmp_path).extract_labels_from_annotations(ANNOTATED)
    assert labels, "annotations carrying a category and stack should yield labels"


def test_labeler_only_labels_resources_it_should(tmp_path):
    labeler = ResourceLabeler(tmp_path)
    labelable = {"kind": next(iter(label_mod.LABELABLE_KINDS)),
                 "metadata": {"name": "x"}}
    assert labeler.should_label_resource(labelable)
    assert not labeler.should_label_resource({})


def test_labeler_writes_labels_onto_a_manifest(tmp_path):
    app_yaml(tmp_path / "cnpg" / "application.yaml", annotations=ANNOTATED)
    target = manifest(tmp_path / "cnpg" / "manifests" / "deployment.yaml")
    ResourceLabeler(tmp_path).run("label", dry_run=False)
    labels = yaml.safe_load(target.read_text())["metadata"].get("labels", {})
    assert labels, "a labelable resource beside an annotated Application"


def test_a_manifest_beside_the_application_is_skipped(tmp_path):
    """Only manifests/, manifest/ and k8s/ are searched.

    A resource dropped next to application.yaml is silently not labelled, which
    is worth knowing before wondering why a label never appeared.
    """
    app_yaml(tmp_path / "cnpg" / "application.yaml", annotations=ANNOTATED)
    stray = manifest(tmp_path / "cnpg" / "deployment.yaml")
    before = stray.read_text()
    ResourceLabeler(tmp_path).run("label", dry_run=False)
    assert stray.read_text() == before


def test_labeler_dry_run_changes_nothing(tmp_path):
    app_yaml(tmp_path / "cnpg" / "application.yaml", annotations=ANNOTATED)
    target = manifest(tmp_path / "cnpg" / "manifests" / "deployment.yaml")
    before = target.read_text()
    ResourceLabeler(tmp_path).run("drift", dry_run=False)
    assert target.read_text() == before, "drift must not write"


def test_label_drift_fails_when_labels_are_missing(monkeypatch, tmp_path):
    app_yaml(tmp_path / "cnpg" / "application.yaml", annotations=ANNOTATED)
    manifest(tmp_path / "cnpg" / "manifests" / "deployment.yaml")
    assert cli(monkeypatch, label_mod,
               ["--mode", "drift", "--apps-dir", str(tmp_path)]) == 1


def test_label_drift_passes_once_labelled(monkeypatch, tmp_path):
    app_yaml(tmp_path / "cnpg" / "application.yaml", annotations=ANNOTATED)
    manifest(tmp_path / "cnpg" / "manifests" / "deployment.yaml")
    cli(monkeypatch, label_mod, ["--mode", "label", "--apps-dir", str(tmp_path)])
    assert cli(monkeypatch, label_mod,
               ["--mode", "drift", "--apps-dir", str(tmp_path)]) == 0


# ── the remaining modes ──────────────────────────────────────────────

def test_annotate_drift_reports_without_writing(monkeypatch, tmp_path):
    path = app_yaml(tmp_path / "cnpg" / "application.yaml")
    before = path.read_text()
    code = cli(monkeypatch, annotate_mod,
               ["--mode", "drift", "--apps-dir", str(tmp_path)])
    assert code == 1, "an unannotated Application is drift"
    assert path.read_text() == before, "drift must not write"


def test_annotate_report_is_json_and_always_passes(monkeypatch, tmp_path, capsys):
    """A report describes; it does not judge, so it cannot fail a pipeline."""
    import json
    app_yaml(tmp_path / "cnpg" / "application.yaml")
    code = cli(monkeypatch, annotate_mod,
               ["--mode", "report", "--apps-dir", str(tmp_path)])
    assert code == 0
    out = capsys.readouterr().out
    # run() returns its stats dict for every mode except report, which returns
    # a differently shaped coverage report -- hence total_applications here and
    # total elsewhere.
    payload = json.loads(out[out.index("{"):])
    assert payload["total_applications"] == 1


def test_annotate_report_writes_to_a_file(monkeypatch, tmp_path):
    import json
    app_yaml(tmp_path / "cnpg" / "application.yaml")
    out = tmp_path / "report.json"
    cli(monkeypatch, annotate_mod,
        ["--mode", "report", "--apps-dir", str(tmp_path), "--output", str(out)])
    assert json.loads(out.read_text())["total_applications"] == 1


def test_add_is_idempotent(tmp_path):
    """Running the fixer twice must not keep reporting work to do."""
    path = app_yaml(tmp_path / "cnpg" / "application.yaml")
    manager = AnnotationManager(tmp_path)
    manager.add_annotations(path, dry_run=False)
    first = path.read_text()
    AnnotationManager(tmp_path).add_annotations(path, dry_run=False)
    assert path.read_text() == first
