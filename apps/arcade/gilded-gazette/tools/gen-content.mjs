#!/usr/bin/env node
/**
 * Compiles shared/data into the one JSON both runtimes read:
 * godot/data/content.gen.json and vite/src/content/content.gen.json.
 *
 * Every directory under shared/data is a collection of MDX files - articles,
 * passengers, items - validated against tools/content-schema.mjs. gazette.json
 * holds the newspaper frame, which is plain config rather than prose.
 *
 * Prose is authored as MDX so an article reads like an article and a passenger
 * reads like a person. Everything a runtime needs sits in the frontmatter, so
 * neither side parses markdown.
 *
 * Usage: node tools/gen-content.mjs [--check]
 */
import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { createRequire } from 'node:module';
import { collections } from './content-schema.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

// &resolve -> yaml and zod are installed under vite/, see content-schema.mjs
const require = createRequire(join(root, 'vite/package.json'));
const YAML = require('yaml');
const check = process.argv.includes('--check');

const DATA = join(root, 'shared/data');
const FRAME = join(DATA, 'gazette.json');
const OUTPUTS = [
  join(root, 'godot/data/content.gen.json'),
  join(root, 'vite/src/content/content.gen.json'),
];


/**
 * Splits an MDX body into a lede and its `##` sections.
 *
 * &shape -> prose before the first heading is the lede, which is what a page or
 *           a summary line prints. Everything after is addressable: a section
 *           key, its paragraphs, and its bullets, so game code can ask for the
 *           alibi without reading the whole dossier
 */
function parseBody(text) {
  const lines = text.split('\n');
  const blocks = [{ key: '', heading: '', lines: [] }];

  for (const line of lines) {
    const h = /^##\s+(.+?)\s*$/.exec(line);
    if (h) {
      blocks.push({ key: slug(h[1]), heading: h[1], lines: [] });
      continue;
    }
    blocks[blocks.length - 1].lines.push(line);
  }

  const intro = paragraphs(blocks[0].lines.join('\n'));
  const sections = {};
  for (const b of blocks.slice(1)) {
    if (sections[b.key]) throw new Error(`duplicate section "## ${b.heading}"`);
    const bullets = b.lines
      .map((l) => /^\s*[-*]\s+(.*)$/.exec(l.trim()))
      .filter(Boolean)
      .map((m) => m[1].trim());
    const prose = b.lines.filter((l) => !/^\s*[-*]\s+/.test(l.trim())).join('\n');
    sections[b.key] = { heading: b.heading, paragraphs: paragraphs(prose), bullets };
  }
  return { intro, sections };
}

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');

/** Blank-line separated, soft-wrapped lines rejoined. */
function paragraphs(text) {
  return text
    .split(/\n\s*\n/)
    .map((p) => p.trim().replace(/\s*\n\s*/g, ' '))
    .filter(Boolean);
}

function compileArticle(file) {
  const raw = readFileSync(join(ARTICLES, file), 'utf8');
  const m = /^---\n([\s\S]*?)\n---\n([\s\S]*)$/.exec(raw);
  if (!m) throw new Error(`${file}: missing --- frontmatter block`);
  const meta = parseFrontmatter(m[1], file);
  const body = parseBody(m[2]);

  for (const key of ['id', 'title', 'kicker', 'caption']) {
    if (!meta[key]) throw new Error(`${file}: frontmatter is missing "${key}"`);
  }
  if (!meta.when || typeof meta.when !== 'object') {
    throw new Error(`${file}: frontmatter needs a "when:" block saying what prints it`);
  }
  if (body.length === 0) throw new Error(`${file}: article has no prose`);

  // &lede -> first paragraph carries the drop cap; the rest is the column body
  const [lede, ...rest] = body;
  return {
    id: meta.id,
    when: meta.when,
    priority: meta.priority ?? 0,
    kicker: meta.kicker,
    title: meta.title,
    caption: meta.caption,
    lede,
    body: rest,
    source: `shared/data/articles/${file}`,
  };
}

/**
 * &lede -> the first paragraph carries the drop cap on a page and the summary
 *          line anywhere else, so it is split out for every collection, not
 *          just for articles
 */
function compile(dir, file, schema) {
  const where = `shared/data/${dir}/${file}`;
  const raw = readFileSync(join(DATA, dir, file), 'utf8');
  const m = /^---\n([\s\S]*?)\n---\n([\s\S]*)$/.exec(raw);
  if (!m) throw new Error(`${where}: missing --- frontmatter block`);

  let front;
  try {
    front = YAML.parse(m[1]) ?? {};
  } catch (e) {
    throw new Error(`${where}: frontmatter is not valid YAML\n  ${e.message}`);
  }

  let intro, sections;
  try {
    ({ intro, sections } = parseBody(m[2]));
  } catch (e) {
    throw new Error(`${where}: ${e.message}`);
  }
  if (intro.length === 0) throw new Error(`${where}: no prose before the first heading`);
  const [lede, ...rest] = intro;

  const parsed = schema.safeParse({ ...front, lede, body: rest, sections });
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `  ${i.path.join('.') || '(root)'}: ${i.message}`)
      .join('\n');
    throw new Error(`${where} failed validation:\n${issues}`);
  }
  return { ...parsed.data, source: where };
}

const content = {};
for (const [dir, schema] of Object.entries(collections)) {
  const path = join(DATA, dir);
  if (!existsSync(path)) {
    content[dir] = [];
    continue;
  }
  const entries = readdirSync(path)
    .filter((f) => f.endsWith('.mdx'))
    .sort()
    .map((f) => compile(dir, f, schema));

  const seen = new Set();
  for (const e of entries) {
    if (seen.has(e.id)) throw new Error(`duplicate id "${e.id}" in shared/data/${dir}`);
    seen.add(e.id);
  }
  content[dir] = entries;
}

// &refs -> an item pointing at a passenger who does not exist is a content bug
//          that would surface as a blank line in game, so catch it here
const passengerIds = new Set(content.passengers.map((p) => p.id));
for (const it of content.items) {
  if (it.owner && !passengerIds.has(it.owner)) {
    throw new Error(`${it.source}: owner "${it.owner}" is not a passenger id`);
  }
}
for (const p of content.passengers) {
  for (const rel of p.relationships ?? []) {
    if (!passengerIds.has(rel.who)) {
      throw new Error(`${p.source}: relationship "${rel.who}" is not a passenger id`);
    }
  }
}

/**
 * &vocab -> the locations collection IS the location vocabulary, so every place
 *           a location is named gets checked against it. A room renamed in
 *           shared/data/locations breaks the build at the file that still names
 *           the old one, rather than silently emptying a room in game.
 */
const locationIds = new Set(content.locations.map((l) => l.id));
const requireLocation = (where, field, id) => {
  if (!locationIds.has(id)) {
    throw new Error(
      `${where}: ${field} "${id}" is not a locations id`
      + ` (have: ${[...locationIds].join(', ')})`,
    );
  }
};
for (const p of content.passengers) {
  requireLocation(p.source, 'location', p.location);
  for (const step of p.timeline ?? []) requireLocation(p.source, 'timeline.where', step.where);
}
for (const it of content.items) {
  if (it.location) requireLocation(it.source, 'location', it.location);
}

/**
 * &consist -> a carriage index is a position along the train, which SOccupancy
 *             indexes into directly. A gap or a repeat would leave a carriage
 *             resolving to nowhere, so the run of indices has to be 0..n.
 */
const aboard = content.locations
  .filter((l) => typeof l.carriage === 'number')
  .sort((a, b) => a.carriage - b.carriage);
aboard.forEach((l, i) => {
  if (l.carriage !== i) {
    throw new Error(
      `${l.source}: carriage indices must run 0..${aboard.length - 1} with no gaps or repeats;`
      + ` "${l.id}" is ${l.carriage}, expected ${i}`,
    );
  }
});

/**
 * Furnishings name a prop out of the compiled prop library, so a prop renamed in
 * its spec breaks the build at the room that still asks for the old one rather
 * than leaving a hole in the floor where a crate should be.
 *
 * The manifest is the compiler's own output, so this checks against what was
 * actually built rather than against a list of names kept alongside it.
 */
const PROP_MANIFEST = join(root, 'godot/assets/props/props_manifest.json');
const props = existsSync(PROP_MANIFEST)
  ? JSON.parse(readFileSync(PROP_MANIFEST, 'utf8'))
  : null;
const propNames = props === null ? null : new Set(Object.keys(props));
for (const l of content.locations) {
  if (!l.furnishings?.length) continue;
  if (typeof l.carriage !== 'number') {
    throw new Error(
      `${l.source}: "${l.id}" has furnishings but no carriage index, so there is`
      + ' no room in the consist for them to stand in',
    );
  }
  if (propNames === null) {
    throw new Error(
      `${l.source}: furnishings need godot/assets/props/props_manifest.json;`
      + ' build the prop library before authoring against it',
    );
  }
  for (const f of l.furnishings) {
    if (!propNames.has(f.prop)) {
      throw new Error(
        `${l.source}: prop "${f.prop}" is not in the prop library`
        + ` (have: ${[...propNames].join(', ')})`,
      );
    }
    // whether a prop is somewhere to sit is a fact about the prop, authored once
    // in its spec, so it is stamped on here rather than repeated on every chair
    // in every room and rather than read back out of the manifest at runtime
    const built = props[f.prop];
    if (built.seats) {
      f.seats = true;
      f.cushionHeight = built.cushion_height;
    }
  }
}

/**
 * &wall -> a notice hangs in a carriage, so the carriage it names has to be a room in
 *          the consist. Without this a sheet authored one carriage past the end of the
 *          train simply never appears, which looks like a missing texture rather than a
 *          missing room.
 */
const carriageCount = aboard.length;
for (const n of content.notices) {
  if (n.carriage >= carriageCount) {
    throw new Error(
      `${n.source}: notice "${n.id}" hangs in carriage ${n.carriage},`
      + ` but the consist authors ${carriageCount} (0..${carriageCount - 1})`,
    );
  }
}

const frame = JSON.parse(readFileSync(FRAME, 'utf8'));
for (const key of Object.keys(frame)) if (key.startsWith('$')) delete frame[key];

// &banner -> JSON has no comments, so the warning has to be a key. First in the
//            file, so it is the first thing an editor shows
const banner = {
  $generated:
    'GENERATED FILE - DO NOT EDIT. Source: shared/data/gazette.json + shared/data/*/*.mdx. ' +
    'Regenerate: npm run gen (from vite/). Runs automatically on dev and build.',
};

const payload = JSON.stringify({ ...banner, gazette: frame, ...content }, null, 2) + '\n';

/**
 * &type -> JSON gives both runtimes the data but gives TypeScript nothing to
 *          narrow on, so the one thing worth a literal type is emitted here:
 *          a room misspelt in React is then a type error, the same way a room
 *          misspelt in MDX is a build error above.
 */
// &order -> files are read alphabetically, which is no order at all to print
//           in. The train's own order is the consist, so that leads, and
//           anywhere off the train follows it.
const ashore = content.locations.filter((l) => typeof l.carriage !== 'number');
const ordered = [...aboard, ...ashore];
const list = (ls) => ls.map((l) => `'${l.id}'`).join(', ');

const vocabTs = [
  '/**',
  ' * GENERATED FILE - DO NOT EDIT.',
  ' *',
  ' * Source: shared/data/locations/*.mdx',
  ' * Regenerate: npm run gen (from vite/). Runs automatically on dev and build.',
  ' */',
  '',
  '/** Somewhere a passenger, an item or the player can be. */',
  'export type LocationId =',
  ...ordered.map((l, i) => `  | '${l.id}'${i === ordered.length - 1 ? ';' : ''}`),
  '',
  '/** Every location, the consist in order and then anywhere off the train. */',
  `export const LOCATION_IDS: readonly LocationId[] = [${list(ordered)}] as const;`,
  '',
  '/** Every location that is a place in the consist, by index along the train. */',
  `export const CARRIAGE_LOCATION_IDS: readonly LocationId[] = [${list(aboard)}] as const;`,
  '',
].join('\n');

const TS_OUT = join(root, 'vite/src/content/locations.gen.ts');

let drift = false;
for (const [out, body] of [...OUTPUTS.map((o) => [o, payload]), [TS_OUT, vocabTs]]) {
  mkdirSync(dirname(out), { recursive: true });
  let current = null;
  try {
    current = readFileSync(out, 'utf8');
  } catch {
    /* not written yet */
  }
  if (current === body) continue;
  if (check) {
    console.error(`content output is stale: ${out.replace(root + '/', '')}`);
    drift = true;
    continue;
  }
  writeFileSync(out, body);
  console.log('wrote', out.replace(root + '/', ''));
}

if (check && drift) process.exit(1);
if (check) {
  const counts = Object.entries(content).map(([k, v]) => `${v.length} ${k}`).join(', ');
  console.log(`content is up to date (${counts})`);
}
