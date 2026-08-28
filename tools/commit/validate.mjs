#!/usr/bin/env node
// Checks a message against the conventional-commit shape this repository uses.
//
// Runs from the commit-msg hook on every commit, and against a pull request
// title in CI, because the labeller reads the type out of that title -- an
// unconventional title silently gets no kind/* label rather than a wrong one,
// which is a quiet failure worth catching loudly.
//
// Neither the types nor the scopes are listed here. Types come from the
// `commit` fields on the kind labels in tools/labels/labels.yml, so `feat`
// meaning kind/feature is stated once. Scopes come from the project graph, via
// labels.lock.json -- a commit-msg hook runs on every commit and cannot afford
// to start moon, and the lock is the offline copy that already exists.
//
// Usage: validate.mjs <file>        the commit-msg hook form; reads a file
//        validate.mjs --title '...' validate a string
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const LOCK = join(HERE, '..', 'labels', 'labels.lock.json')

// Git's own prefixes and machinery. A merge or a revert is not something a
// person composed, and rejecting one would block a legitimate operation with
// no way to fix the message.
const EXEMPT = [
  /^Merge /, /^Revert /, /^fixup! /, /^squash! /, /^amend! /,
  /^Reapply /,
]

export function vocabulary(lockText, scopesText) {
  const lock = JSON.parse(lockText)
  const types = lock.labels
    .flatMap((l) => (l.commit ?? '').split(/\s+/).filter(Boolean))
    .sort()
  const extra = [...scopesText.matchAll(/^\s*-\s*'([^']+)'/gm)].map((m) => m[1])
  // A change can legitimately belong to a whole group rather than one project
  // -- `feat(crates): migrate the bevy crate group` -- so the area names are
  // scopes as well. They come from the area labels, so the two stay in step.
  const groups = lock.labels.filter((l) => l.family === 'area').map((l) => l.name.slice('area/'.length))
  return { types, scopes: [...new Set([...lock.scopes, ...groups, ...extra])].sort(), extra: [...groups, ...extra] }
}

// Returns an array of problems; empty means fine.
export function validate(message, { types, scopes, extra }) {
  const subject = (message ?? '').split('\n').find((l) => !l.startsWith('#'))?.trim() ?? ''
  if (!subject) return ['the message is empty']
  if (EXEMPT.some((re) => re.test(subject))) return []

  const m = /^([a-z]+)(?:\(([^)]+)\))?(!)?: (.+)$/.exec(subject)
  if (!m) {
    return [
      `"${subject}" is not a conventional commit`,
      'expected: type(scope): subject   -- for example  fix(laser): stop the pool going negative',
    ]
  }
  const [, type, scope, , text] = m
  const problems = []
  if (!types.includes(type)) {
    problems.push(`unknown type '${type}'. Use one of: ${types.join(', ')}`)
  }
  if (scope !== undefined && !scopes.includes(scope)) {
    problems.push(`unknown scope '${scope}'`)
    problems.push(`use a moon project id (moon query projects), or: ${(extra ?? []).join(', ')}`)
  }
  // Cheap style checks that catch the two things that actually happen.
  if (/^[A-Z]/.test(text)) problems.push('the subject should not start with a capital')
  if (text.endsWith('.')) problems.push('the subject should not end with a full stop')
  // Not 72. Replaying this repository's own history through the check, eight
  // subjects sit between 73 and 83 characters, and they read fine -- that is
  // the house style, not a mistake. This is only here to catch a subject that
  // is really a paragraph.
  if (subject.length > 100) problems.push(`the subject is ${subject.length} characters; keep it under 100`)
  return problems
}

function main() {
  const argv = process.argv.slice(2)
  const message = argv[0] === '--title' ? argv[1] : readFileSync(argv[0], 'utf8')
  const vocab = vocabulary(readFileSync(LOCK, 'utf8'), readFileSync(join(HERE, 'scopes.yml'), 'utf8'))
  const problems = validate(message, vocab)
  if (!problems.length) return
  console.error('commit message:')
  for (const p of problems) console.error(`  ${p}`)
  console.error('')
  console.error('Scopes come from the moon project graph; repository-wide ones are in')
  console.error('tools/commit/scopes.yml. Types are the `commit` fields in tools/labels/labels.yml.')
  process.exit(1)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main()
