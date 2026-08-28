// A release tag has to agree with the manifest it claims to release.
//
// Tags are written by hand -- that is deliberate, because GitHub generates
// release notes by diffing against the chronologically previous tag, which in
// a monorepo interleaves every other project's commits. Hand-written notes are
// the correct output here, not a fallback.
//
// What a human cannot reliably do by hand is keep `rentearth-api@0.2.0` in
// step with `version = "0.2.0"`. A tag that disagrees ships an artifact
// labelled with a version its own manifest never claimed, and nothing
// downstream can tell. That is the whole job of this script.
//
// Tag format is `<moon project id>@<semver>`, so the tag resolves to a node in
// the project graph with no lookup table -- the manifest of ids the legacy
// repo maintained by hand is the thing this avoids.

import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync, appendFileSync } from 'node:fs';
import { join } from 'node:path';

export class TagError extends Error {}

/** Splits on the LAST @, so a scoped name like @kbve/x@1.0.0 still parses. */
export function parseTag(tag) {
  const at = tag.lastIndexOf('@');
  if (at <= 0 || at === tag.length - 1) {
    throw new TagError(
      `"${tag}" is not a release tag. Expected <project>@<version>, e.g. rentearth-api@0.2.0.`,
    );
  }
  return { project: tag.slice(0, at), version: tag.slice(at + 1) };
}

/**
 * Reads the version out of a Cargo manifest.
 *
 * Deliberately not a TOML parser: the only line that matters is `version` in
 * the [package] table, and a dependency further down the file may carry a
 * version of its own. Stopping at the next table header is what keeps those
 * apart.
 */
export function cargoVersion(text) {
  const lines = text.split('\n');
  let inPackage = false;
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith('[')) {
      inPackage = trimmed === '[package]';
      continue;
    }
    if (!inPackage) continue;
    const match = trimmed.match(/^version\s*=\s*"([^"]+)"/);
    if (match) return match[1];
    if (/^version\s*\.\s*workspace\s*=\s*true/.test(trimmed) ||
        /^version\s*=\s*\{[^}]*workspace\s*=\s*true/.test(trimmed)) {
      return { inherited: true };
    }
  }
  return null;
}

/**
 * The tag's project as the graph knows it: where its source lives and what
 * tags it carries. Callers branch on those tags -- the itch workflow publishes
 * a tag that names an 'itch' project and no-ops on any other -- so that
 * deciding which release mechanism a tag belongs to is a graph lookup rather
 * than a list of project ids in a workflow.
 */
/**
 * Reads the version out of a Godot project manifest.
 *
 * A Godot game's version is `config/version` in project.godot, and nothing
 * generates a package.json or Cargo.toml beside it. Adding one would mean two
 * places claiming a version and no mechanism keeping them equal, which is the
 * exact failure this whole script exists to catch.
 *
 * Scoped to [application], the section Godot writes config/version into, so a
 * `config/version` under some other section cannot be picked up instead.
 */
export function godotVersion(text) {
  let inApplication = false;
  for (const line of text.split('\n')) {
    const trimmed = line.trim();
    if (trimmed.startsWith('[')) {
      inApplication = trimmed === '[application]';
      continue;
    }
    if (!inApplication) continue;
    const match = trimmed.match(/^config\/version\s*=\s*"([^"]+)"/);
    if (match) return match[1];
  }
  return null;
}

export function projectNode(project, cwd = process.cwd()) {
  const out = execFileSync('moon', ['query', 'projects', '--id', project], {
    cwd,
    encoding: 'utf8',
  });
  const found = JSON.parse(out).projects;
  if (found.length === 0) {
    throw new TagError(
      `No moon project called "${project}". The tag must name a project id; ` +
        `run \`moon query projects\` to see them.`,
    );
  }
  return found[0];
}

export function manifestVersion(root, source) {
  const cargo = join(root, source, 'Cargo.toml');
  if (existsSync(cargo)) {
    const version = cargoVersion(readFileSync(cargo, 'utf8'));
    if (version === null) {
      throw new TagError(`${source}/Cargo.toml has no version in [package].`);
    }
    if (version.inherited) {
      const wsVersion = cargoVersion(
        readFileSync(join(root, 'Cargo.toml'), 'utf8').replace(
          '[workspace.package]',
          '[package]',
        ),
      );
      if (!wsVersion || wsVersion.inherited) {
        throw new TagError(
          `${source}/Cargo.toml inherits its version, but the workspace does not set one.`,
        );
      }
      return { file: `${source}/Cargo.toml`, version: wsVersion };
    }
    return { file: `${source}/Cargo.toml`, version };
  }

  const pkg = join(root, source, 'package.json');
  if (existsSync(pkg)) {
    const { version } = JSON.parse(readFileSync(pkg, 'utf8'));
    if (!version) {
      throw new TagError(
        `${source}/package.json has no version field. Private packages are ` +
          `not released; either add a version or do not tag this project.`,
      );
    }
    return { file: `${source}/package.json`, version };
  }

  // Both layouts: a bare Godot project, and one that is a subdirectory of a
  // project with other runtimes beside it -- gilded-gazette is a Godot game
  // and a Vite front end in one moon project.
  for (const candidate of ['project.godot', 'godot/project.godot']) {
    const godot = join(root, source, candidate);
    if (!existsSync(godot)) continue;
    const version = godotVersion(readFileSync(godot, 'utf8'));
    if (version === null) {
      throw new TagError(
        `${source}/${candidate} has no config/version in [application].`,
      );
    }
    return { file: `${source}/${candidate}`, version };
  }

  throw new TagError(
    `${source} has no Cargo.toml, package.json or project.godot, so there is ` +
      `no version to check the tag against.`,
  );
}

export function verify(tag, root = process.cwd()) {
  const { project, version } = parseTag(tag);
  const node = projectNode(project, root);
  const source = node.source;
  const manifest = manifestVersion(root, source);
  if (manifest.version !== version) {
    throw new TagError(
      `Tag ${tag} claims version ${version}, but ${manifest.file} says ` +
        `${manifest.version}.\n\nEither the version bump was not committed ` +
        `before tagging, or the tag has a typo. Delete the tag, fix it, and ` +
        `tag again -- do not move a tag that has already been released.`,
    );
  }
  return { project, version, source, file: manifest.file, tags: node.config?.tags ?? [] };
}

// Only run when invoked directly, so the tests can import the functions.
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop())) {
  const tag = process.argv[2] ?? process.env.GITHUB_REF_NAME;
  if (!tag) {
    console.error('Usage: node tools/release/verify-tag.mjs <project>@<version>');
    process.exit(2);
  }
  try {
    const result = verify(tag);
    console.log(
      `${tag} matches ${result.file} (project ${result.project} at ${result.source}).`,
    );
    // Handing the resolved project back to the workflow keeps every release
    // workflow free of project names: one asks the graph what the tag means,
    // then decides from the tags it carries.
    if (process.env.GITHUB_OUTPUT) {
      appendFileSync(
        process.env.GITHUB_OUTPUT,
        [
          `project=${result.project}`,
          `version=${result.version}`,
          `source=${result.source}`,
          `tags=${JSON.stringify(result.tags)}`,
          '',
        ].join('\n'),
      );
    }
  } catch (error) {
    if (error instanceof TagError) {
      console.error(`::error::${error.message}`);
      process.exit(1);
    }
    throw error;
  }
}
