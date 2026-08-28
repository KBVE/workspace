#!/usr/bin/env node
// Labels a pull request from its title and the files it touches.
//
// Reads labels.lock.json and nothing else: `routes` already maps every project
// source to the area/* and tag/* labels it implies, and `commit` on each kind
// label says which conventional-commit types mean it. So this needs no moon
// run, no project graph, and no API call to work out what the labels should
// be -- only to apply them.
//
// Usage: label-pr.mjs <pr-number>
//        label-pr.mjs --explain "<title>" <changed file>...
//
// --explain prints what it would do for a title and file list, without gh.
//
// The kind is reconciled rather than added to: a pull request has exactly one,
// and retitling from feat() to fix() should move the label rather than leave
// both. Scope labels are only added -- a person who labels something by hand
// knows something this does not, and removing that would be rude. Nothing
// outside kind/, area/ and tag/ is ever touched.
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))

// `type(scope)!: subject` -- the ! marks a breaking change and is not part of
// the type.
export function kindFor(title, labels) {
  const m = /^([a-z]+)(?:\([^)]*\))?!?:/.exec(title?.trim() ?? '')
  if (!m) return null
  const type = m[1]
  const hit = labels.find((l) => (l.commit ?? '').split(/\s+/).filter(Boolean).includes(type))
  return hit?.name ?? null
}

// Longest source wins, so a file under a nested project gets that project's
// labels rather than a parent's. Files outside every project -- .github/,
// the root manifests -- contribute nothing, which is correct: they are not
// in an area.
export function scopesFor(files, routes) {
  const sorted = [...routes].sort((a, b) => b.source.length - a.source.length)
  const out = new Set()
  for (const f of files) {
    const hit = sorted.find((r) => f === r.source || f.startsWith(`${r.source}/`))
    if (hit) for (const l of hit.labels) out.add(l)
  }
  return [...out].sort()
}

export function computeLabels(title, files, lock) {
  const kind = kindFor(title, lock.labels)
  return { kind, scopes: scopesFor(files, lock.routes) }
}

// Which of the current labels this tool considers its own. Everything else on
// the pull request belongs to whoever put it there.
export function reconcile(current, { kind, scopes }) {
  const add = []
  const remove = []
  for (const l of scopes) if (!current.includes(l)) add.push(l)
  for (const l of current) {
    if (l.startsWith('kind/') && kind && l !== kind) remove.push(l)
  }
  if (kind && !current.includes(kind)) add.push(kind)
  return { add: add.sort(), remove: remove.sort() }
}

const sh = (cmd, args) => execFileSync(cmd, args, { encoding: 'utf8', maxBuffer: 64 << 20 })

function main() {
  const argv = process.argv.slice(2)
  const lock = JSON.parse(readFileSync(join(HERE, 'labels.lock.json'), 'utf8'))

  if (argv[0] === '--explain') {
    const [, title, ...files] = argv
    const computed = computeLabels(title, files, lock)
    console.log(`title:  ${title}`)
    console.log(`kind:   ${computed.kind ?? '(no conventional-commit type)'}`)
    console.log(`scopes: ${computed.scopes.join(', ') || '(none)'}`)
    return
  }

  const pr = argv[0]
  if (!pr) {
    console.error('usage: label-pr.mjs <pr-number> | --explain "<title>" <file>...')
    process.exit(1)
  }

  const view = JSON.parse(sh('gh', ['pr', 'view', pr, '--json', 'title,labels,files']))
  const files = view.files.map((f) => f.path)
  const current = view.labels.map((l) => l.name)
  const { add, remove } = reconcile(current, computeLabels(view.title, files, lock))

  if (!add.length && !remove.length) {
    console.log('labels already correct')
    return
  }
  // One call each: gh takes repeated --add-label / --remove-label flags.
  if (add.length) sh('gh', ['pr', 'edit', pr, ...add.flatMap((l) => ['--add-label', l])])
  if (remove.length) sh('gh', ['pr', 'edit', pr, ...remove.flatMap((l) => ['--remove-label', l])])
  console.log(`added: ${add.join(', ') || '(none)'}`)
  console.log(`removed: ${remove.join(', ') || '(none)'}`)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main()
