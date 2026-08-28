import { strict as assert } from 'node:assert'
import { test } from 'node:test'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { kindFor, scopesFor, computeLabels, reconcile } from './label-pr.mjs'
import { parseLabels } from './sync.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const lock = JSON.parse(readFileSync(join(HERE, 'labels.lock.json'), 'utf8'))

test('reads the conventional-commit type, with or without a scope', () => {
  assert.equal(kindFor('fix: x', lock.labels), 'kind/bug')
  assert.equal(kindFor('fix(laser): x', lock.labels), 'kind/bug')
  assert.equal(kindFor('feat(a/b): x', lock.labels), 'kind/feature')
})

test('a breaking-change ! is not part of the type', () => {
  assert.equal(kindFor('feat(api)!: drop the old field', lock.labels), 'kind/feature')
})

test('several types can share one kind', () => {
  for (const t of ['chore', 'ci', 'build', 'perf']) {
    assert.equal(kindFor(`${t}: x`, lock.labels), 'kind/chore', t)
  }
})

test('a title that is not conventional gets no kind rather than a wrong one', () => {
  assert.equal(kindFor('Update the readme', lock.labels), null)
  assert.equal(kindFor('', lock.labels), null)
  assert.equal(kindFor(undefined, lock.labels), null)
  assert.equal(kindFor('wip: something', lock.labels), null)
})

test('no commit type is claimed by two kinds', () => {
  const seen = new Map()
  for (const l of lock.labels) {
    for (const t of (l.commit ?? '').split(/\s+/).filter(Boolean)) {
      assert.ok(!seen.has(t), `type '${t}' is claimed by both ${seen.get(t)} and ${l.name}`)
      seen.set(t, l.name)
    }
  }
})

test('the longest matching project wins', () => {
  const routes = [
    { source: 'apps', labels: ['area/apps'] },
    { source: 'apps/arcade/x', labels: ['area/apps', 'tag/game'] },
  ]
  assert.deepEqual(scopesFor(['apps/arcade/x/src/a.ts'], routes), ['area/apps', 'tag/game'])
})

test('a path that only prefixes a project name does not match it', () => {
  const routes = [{ source: 'crates/jedi', labels: ['area/crates'] }]
  assert.deepEqual(scopesFor(['crates/jedi-extra/a.rs'], routes), [])
  assert.deepEqual(scopesFor(['crates/jedi/a.rs'], routes), ['area/crates'])
})

test('files outside every project contribute nothing', () => {
  assert.deepEqual(scopesFor(['.github/workflows/ci.yml', 'README.md'], lock.routes), [])
})

test('retitling moves the kind instead of leaving both', () => {
  const { add, remove } = reconcile(['kind/feature', 'area/tools'], { kind: 'kind/bug', scopes: ['area/tools'] })
  assert.deepEqual(add, ['kind/bug'])
  assert.deepEqual(remove, ['kind/feature'])
})

test('labels a person added by hand are left alone', () => {
  const { add, remove } = reconcile(['status/blocked', '3'], { kind: null, scopes: ['area/crates'] })
  assert.deepEqual(add, ['area/crates'])
  assert.deepEqual(remove, [])
})

test('a scope label is never removed, even once it no longer applies', () => {
  const { remove } = reconcile(['area/apps', 'kind/bug'], { kind: 'kind/bug', scopes: ['area/crates'] })
  assert.deepEqual(remove, [])
})

test('nothing to do is nothing to do', () => {
  const { add, remove } = reconcile(['kind/bug', 'area/tools'], { kind: 'kind/bug', scopes: ['area/tools'] })
  assert.deepEqual(add, [])
  assert.deepEqual(remove, [])
})

test('every label it can emit actually exists in the vocabulary', () => {
  const declared = new Set(lock.labels.map((l) => l.name))
  for (const r of lock.routes) for (const l of r.labels) {
    assert.ok(declared.has(l), `route emits ${l}, which is not declared`)
  }
  const families = parseLabels(readFileSync(join(HERE, 'labels.yml'), 'utf8'))
  for (const l of families.kind) {
    if (l.commit) assert.ok(declared.has(l.name), `${l.name} maps a commit type but is not declared`)
  }
})

test('end to end on a realistic pull request', () => {
  const out = computeLabels(
    'fix(fish-and-chip): stop the walk drifting',
    ['apps/arcade/fish-and-chip/src/game.ts', '.github/workflows/ci.yml'],
    lock,
  )
  assert.equal(out.kind, 'kind/bug')
  assert.deepEqual(out.scopes, ['area/apps', 'tag/game', 'tag/itch', 'tag/phaser'])
})
