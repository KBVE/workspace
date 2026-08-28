import { strict as assert } from 'node:assert'
import { test } from 'node:test'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { validate, vocabulary } from './validate.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const vocab = vocabulary(
  readFileSync(join(HERE, '..', 'labels', 'labels.lock.json'), 'utf8'),
  readFileSync(join(HERE, 'scopes.yml'), 'utf8'),
)
const ok = (m) => assert.deepEqual(validate(m, vocab), [], m)
const bad = (m) => assert.ok(validate(m, vocab).length, `expected a problem: ${m}`)

test('accepts the shapes this repository writes', () => {
  ok('fix(laser): stop the resource pools going negative')
  ok('feat(fish-and-chip): walk at six tiles per second')
  ok('chore: bump the toolchain')
  ok('content(gilded-gazette): write the telegram lines that still said TODO')
  ok('feat(crates): migrate the bevy crate group')
  ok('refactor(moon): move the hooks into the workspace config')
})

test('rejects a type the vocabulary does not have', () => {
  bad('wip(laser): halfway there')
  bad('update(laser): something')
})

test('rejects a scope that is neither a project, a group, nor repository-wide', () => {
  bad('fix(nope): x')
  // Ambiguous between rentearth.com, rentearth-bevy and rentearth-api, which
  // is exactly why naming one of them should be required.
  bad('feat(rentearth): build the browser bundles')
})

test('a scope is optional', () => {
  ok('docs: explain the worktree flow')
})

test('breaking changes are allowed', () => {
  ok('feat(kbve-proto)!: drop the deprecated field')
})

test('git\'s own messages are left alone', () => {
  ok("Merge branch 'main' into wt/x")
  ok('Revert "feat(laser): something"')
  ok('fixup! fix(laser): x')
})

test('catches the two style slips that actually happen', () => {
  bad('fix(laser): Stop the pool going negative')
  bad('fix(laser): stop the pool going negative.')
})

test('a subject in this house style is not too long', () => {
  // 83 characters, taken from real history. A 72-character cap would have
  // rejected eight existing commits.
  ok('test(laser): cover the movement chain, the quadtree children and the reconnect path')
})

test('a paragraph masquerading as a subject is still caught', () => {
  bad(`fix(laser): ${'x'.repeat(120)}`)
})

test('an empty message is a problem, not a pass', () => {
  bad('')
  bad('\n# a comment git added\n')
})

test('the comment lines git appends are ignored', () => {
  ok('fix(laser): x\n\n# Please enter the commit message for your changes.')
})

test('every type maps to a kind label, so the labeller can never be surprised', () => {
  const lock = JSON.parse(readFileSync(join(HERE, '..', 'labels', 'labels.lock.json'), 'utf8'))
  const mapped = new Set(lock.labels.flatMap((l) => (l.commit ?? '').split(/\s+/).filter(Boolean)))
  assert.deepEqual([...vocab.types].sort(), [...mapped].sort())
})
