#!/usr/bin/env node
// Reconciles GitHub's labels with labels.yml, and checks the moon graph
// against the tag vocabulary that file declares.
//
// Two jobs, because they are the same question asked from both ends:
//
//   --check   does the repository agree with labels.yml? Used by CI. Fails on
//             a moon.yml tag that labels.yml does not declare, which is the
//             drift that matters -- without it a typo mints a label and
//             tag/bevy and tag/bevvy both look official.
//   --apply   create missing labels on GitHub and correct wrong colours or
//             descriptions.
//
// Never deletes. Labels already on GitHub that labels.yml does not describe
// are reported and left alone -- this repository had eighteen of them before
// this file existed, and removing someone's label is not a tool's decision.
//
// No dependencies: a hand-rolled reader for the small YAML subset labels.yml
// uses, and gh for the API.
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))

// Only what labels.yml uses: `family:` at column 0, then `- name:` items whose
// scalars are quoted. A real parser would be a dependency, and this file is
// checked by CI against the graph, so a shape it cannot read fails loudly.
export function parseLabels(text) {
  const out = {}
  let family = null
  let item = null
  for (const raw of text.split('\n')) {
    const line = raw.replace(/\s+$/, '')
    if (!line || /^\s*#/.test(line)) continue
    const fam = line.match(/^([a-z][a-z0-9_]*):$/)
    if (fam) { family = fam[1]; out[family] = []; item = null; continue }
    if (!family) continue
    const start = line.match(/^\s*-\s*name:\s*'(.+)'$/)
    if (start) { item = { name: start[1] }; out[family].push(item); continue }
    const field = line.match(/^\s+([a-z]+):\s*(?:'(.*)'|"(.*)")$/)
    if (field && item) item[field[1]] = field[2] ?? field[3]
  }
  return out
}

const sh = (cmd, args) => execFileSync(cmd, args, { encoding: 'utf8', maxBuffer: 64 << 20 })

function main() {
  const families = parseLabels(readFileSync(join(HERE, 'labels.yml'), 'utf8'))
  // 'retire' is not a family of labels this repository has; it is the list of
  // names it is allowed to delete. Kept in the same file so the whole
  // vocabulary, including what was dropped and why, reads as one document.
  const { retire: retiring = [], ...keep } = families
  const declared = Object.values(keep).flat()
  const declaredTags = new Set((families.tag ?? []).map((l) => l.name.slice('tag/'.length)))
  const declaredAreas = new Set((families.area ?? []).map((l) => l.name.slice('area/'.length)))

  const projects = JSON.parse(sh('moon', ['query', 'projects'])).projects
  const usedTags = new Set(projects.flatMap((p) => p.config?.tags ?? []))
  const usedAreas = new Set(projects.map((p) => p.source.split('/')[0]))

  const problems = []
  const notes = []

  for (const tag of [...usedTags].sort()) {
    if (!declaredTags.has(tag)) {
      const where = projects.filter((p) => (p.config?.tags ?? []).includes(tag)).map((p) => p.id)
      problems.push(`tag '${tag}' is used by ${where.join(', ')} but not declared in labels.yml`)
    }
  }
  for (const tag of [...declaredTags].sort()) {
    if (!usedTags.has(tag)) notes.push(`tag '${tag}' is declared but no project uses it`)
  }
  for (const area of [...usedAreas].sort()) {
    if (!declaredAreas.has(area)) problems.push(`projects live under '${area}/' but area/${area} is not declared`)
  }

  // Existing colours may be written with or without a leading '#'.
  const norm = (c) => (c ?? '').replace(/^#/, '').toLowerCase()

  // The graph half of --check needs no network, and it is the half CI cares
  // about. Reaching GitHub is best-effort so a runner without gh, without a
  // token, or without network still fails on a bad tag rather than on curl.
  // Labels are per-repository, and gh picks its target from the working
  // directory. Naming it out loud is cheap, and makes an --apply run from the
  // wrong clone obvious before it changes anything -- this org has a dozen
  // other repositories and none of them share a label set with this one.
  let existing = null
  try {
    console.log(`repository: ${sh('gh', ['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner']).trim()}`)
    existing = new Map(
      JSON.parse(sh('gh', ['label', 'list', '--limit', '200', '--json', 'name,color,description']))
        .map((l) => [l.name, l]),
    )
  } catch {
    console.warn('warn:  could not reach GitHub; checking the project graph only')
  }

  // A declared label whose older synonym is still on GitHub is a rename, not a
  // creation. Renaming keeps the label and everything filed under it, and the
  // duplicate spelling stops existing -- which is how the vocabulary can become
  // authoritative without deleting anything.
  const renames = existing
    ? declared.filter((l) => l.supersedes && !existing.has(l.name) && existing.has(l.supersedes))
    : []
  const renaming = new Set(renames.map((l) => l.name))
  const missing = existing
    ? declared.filter((l) => !existing.has(l.name) && !renaming.has(l.name))
    : []
  const wrong = existing
    ? declared.filter((l) => {
        const cur = existing.get(l.name)
        return cur && (norm(cur.color) !== norm(l.color) || (cur.description ?? '') !== (l.description ?? ''))
      })
    : []
  const superseded = new Set(renames.map((l) => l.supersedes))
  const retire = existing ? retiring.filter((l) => existing.has(l.name)) : []
  const retiringNames = new Set(retire.map((l) => l.name))
  const unmanaged = existing
    ? [...existing.keys()].filter(
        (n) => !declared.some((l) => l.name === n) && !superseded.has(n) && !retiringNames.has(n),
      )
    : []

  const apply = process.argv.includes('--apply')

  for (const p of problems) console.error(`error: ${p}`)
  for (const n of notes) console.warn(`warn:  ${n}`)

  if (apply && !existing) {
    console.error('error: --apply needs GitHub, and it could not be reached')
    process.exit(1)
  }

  if (apply) {
    for (const l of renames) {
      sh('gh', ['label', 'edit', l.supersedes, '--name', l.name, '--color', norm(l.color),
                '--description', l.description ?? ''])
      console.log(`renamed ${l.supersedes} -> ${l.name}`)
    }
    for (const l of missing) {
      sh('gh', ['label', 'create', l.name, '--color', norm(l.color), '--description', l.description ?? ''])
      console.log(`created ${l.name}`)
    }
    for (const l of retire) {
      sh('gh', ['label', 'delete', l.name, '--yes'])
      console.log(`deleted ${l.name}`)
    }
    for (const l of wrong) {
      sh('gh', ['label', 'edit', l.name, '--color', norm(l.color), '--description', l.description ?? ''])
      console.log(`updated ${l.name}`)
    }
  } else {
    for (const l of renames) console.log(`would rename ${l.supersedes} -> ${l.name}`)
    for (const l of missing) console.log(`would create ${l.name}`)
    for (const l of retire) console.log(`would delete ${l.name} -- ${l.description ?? 'retired'}`)
    for (const l of wrong) console.log(`would update ${l.name}`)
  }

  if (unmanaged.length) {
    console.log(`\n${unmanaged.length} label(s) on GitHub that labels.yml does not describe, left alone:`)
    console.log(`  ${unmanaged.join(', ')}`)
  }

  console.log(
    existing
      ? `\n${declared.length} declared, ${renames.length} to rename, ${missing.length} to create, ` +
          `${wrong.length} to correct, ${retire.length} to delete, ${unmanaged.length} unmanaged.`
      : `\n${declared.length} declared. Graph checked; GitHub not compared.`,
  )

  // Colour and description drift is fixable by re-running with --apply, so it is
  // not worth failing CI over. An undeclared tag is not: it means the vocabulary
  // and the graph disagree, and only a person can say which one is right.
  if (problems.length) process.exit(1)
}

// Importable for tests: running the module must not fire a gh call.
if (process.argv[1] === fileURLToPath(import.meta.url)) main()
