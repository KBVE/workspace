import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseTag, cargoVersion, TagError } from './verify-tag.mjs';

test('parses a project tag', () => {
  assert.deepEqual(parseTag('rentearth-api@0.2.0'), {
    project: 'rentearth-api',
    version: '0.2.0',
  });
});

test('splits on the last @ so scoped names survive', () => {
  assert.deepEqual(parseTag('@kbve/i18n@1.0.0'), {
    project: '@kbve/i18n',
    version: '1.0.0',
  });
});

test('rejects anything that is not a release tag', () => {
  for (const bad of ['v1.0.0', 'rentearth-api', '@1.0.0', 'rentearth-api@']) {
    assert.throws(() => parseTag(bad), TagError, `expected ${bad} to be rejected`);
  }
});

test('reads the package version, not a dependency version', () => {
  const manifest = [
    '[package]',
    'name = "rentearth-api"',
    'version = "0.1.0"',
    '',
    '[dependencies]',
    'axum = { version = "0.8.9" }',
  ].join('\n');
  assert.equal(cargoVersion(manifest), '0.1.0');
});

test('does not mistake a dependency version for the package version', () => {
  // No version in [package] at all: the dependency below must not be picked up
  // as a fallback, or a tag would validate against axum's version number.
  const manifest = ['[package]', 'name = "x"', '', '[dependencies]', 'axum = "0.8.9"'].join('\n');
  assert.equal(cargoVersion(manifest), null);
});

test('reports an inherited version rather than returning nothing', () => {
  const manifest = ['[package]', 'name = "x"', 'version.workspace = true'].join('\n');
  assert.deepEqual(cargoVersion(manifest), { inherited: true });
});

test('recognises the table form of inheritance', () => {
  const manifest = ['[package]', 'version = { workspace = true }'].join('\n');
  assert.deepEqual(cargoVersion(manifest), { inherited: true });
});
