import { strict as assert } from 'node:assert'
import { test } from 'node:test'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseLabels } from './sync.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))

test('reads families, names, colours, and descriptions', () => {
  const out = parseLabels(`
# comment
kind:
  - name: 'kind/bug'
    color: 'd73a4a'
    description: "Something is broken"
tag:
  - name: 'tag/game'
    color: 'd4c5f9'
    description: 'A playable game project'
`)
  assert.deepEqual(Object.keys(out), ['kind', 'tag'])
  assert.deepEqual(out.kind, [{ name: 'kind/bug', color: 'd73a4a', description: 'Something is broken' }])
  assert.equal(out.tag[0].name, 'tag/game')
})

test('ignores comments and blank lines rather than reading them as items', () => {
  const out = parseLabels("kind:\n\n  # - name: 'kind/ghost'\n  - name: 'kind/real'\n    color: 'ffffff'\n")
  assert.deepEqual(out.kind.map((l) => l.name), ['kind/real'])
})

// The parser is deliberately small, so the thing worth asserting is that it
// still understands the file it exists to read.
test('parses the real labels.yml, and every entry is complete', () => {
  const out = parseLabels(readFileSync(join(HERE, 'labels.yml'), 'utf8'))
  assert.deepEqual(Object.keys(out).sort(), ['area', 'kind', 'level', 'retire', 'status', 'tag'])

  // 'level' keeps its original bare names (0-6) rather than a prefix, and
  // 'retire' is a delete list rather than labels this repository has, so
  // neither is prefixed and retired entries carry no colour.
  const prefixed = ['area', 'kind', 'status', 'tag']

  for (const [family, labels] of Object.entries(out)) {
    assert.ok(labels.length > 0, `${family} is empty`)
    for (const l of labels) {
      assert.ok(l.description?.length, `${l.name} has no description`)
      if (prefixed.includes(family)) {
        assert.match(l.name, new RegExp(`^${family}/`), `${l.name} is not in the ${family} family`)
      }
      if (family !== 'retire') {
        assert.match(l.color, /^[0-9a-f]{6}$/, `${l.name} has a bad colour: ${l.color}`)
      }
    }
  }
})

test('levels are bare integers, not prefixed', () => {
  const out = parseLabels(readFileSync(join(HERE, 'labels.yml'), 'utf8'))
  assert.deepEqual(out.level.map((l) => l.name), ['0', '1', '2', '3', '4', '5', '6'])
})

test('no label is declared and retired at once', () => {
  const out = parseLabels(readFileSync(join(HERE, 'labels.yml'), 'utf8'))
  const { retire, ...keep } = out
  const declared = new Set(Object.values(keep).flat().map((l) => l.name))
  const superseded = new Set(Object.values(keep).flat().map((l) => l.supersedes).filter(Boolean))
  for (const l of retire) {
    assert.ok(!declared.has(l.name), `${l.name} is both declared and retired`)
    assert.ok(!superseded.has(l.name), `${l.name} is both superseded and retired`)
  }
})
