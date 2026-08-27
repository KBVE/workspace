#!/usr/bin/env node
/**
 * Generates the GDScript and TypeScript views of shared/state.json.
 * This is based upon bf6 typescript <-> gdscript , as well as some other converters.
 * 
 * This is just a scoped and tree shaken version of the converter. 
 * 
 * DO NOT EDIT THIS UNLESS USING SOMETHING LIKE TinyTemplate Syntax
 * 
 * Bitty shift layout is our safe to share via (FFI / aka language boundary) -> exactly one
 * file defines the values amoung ts, js, gdscript.
 * 
 * Editing any generated file (by hand) could cause a build failure but prevent a silent divergence.
 *
 * Usage via node tools/gen-state.mjs [--check? --proto?]
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const spec = JSON.parse(readFileSync(join(root, 'shared/state.json'), 'utf8'));
const events = JSON.parse(readFileSync(join(root, 'shared/events.json'), 'utf8'));
const check = process.argv.includes('--check');

const BANNER = [
  'GENERATED FILE - DO NOT EDIT.',
  '',
  'Source: shared/state.json + shared/events.json',
  'Regenerate: npm run gen (from vite/). Runs automatically on dev and build.',
];

function snake(name) {
  return name.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
}

function lower(name) {
  return name.charAt(0).toLowerCase() + name.slice(1);
}

function constPrefix(name) {
  return name.replace(/Flags$/, '').toUpperCase();
}

function wrapDoc(text, prefix, width = 88) {
  const out = [];
  for (const line of text.split('\n')) {
    let current = '';
    for (const word of line.split(' ')) {
      if (current && (prefix + current + ' ' + word).length > width) {
        out.push(prefix + current);
        current = word;
      } else {
        current = current ? current + ' ' + word : word;
      }
    }
    out.push(current ? prefix + current : prefix.trimEnd());
  }
  return out;
}

function gdscript() {
  const L = ['class_name StateBits', ''];
  L.push(...BANNER.map((l) => (l ? `## ${l}` : '##')));
  L.push('');
  for (const [name, def] of Object.entries(spec.enums ?? {})) {
    L.push(...wrapDoc(def.description, '## '));
    L.push(`enum ${name} {`);
    for (const [key, value] of Object.entries(def.values)) L.push(`\t${key} = ${value},`);
    L.push('}', '');
  }
  for (const [name, def] of Object.entries(spec.flags ?? {})) {
    L.push(...wrapDoc(def.description, '## '));
    for (const [key, bit] of Object.entries(def.bits)) {
      L.push(`const ${constPrefix(name)}_${key} := 1 << ${bit}`);
    }
    L.push('');
  }

  L.push('## True when every bit in [param flags] is set in [param value].');
  L.push('static func has_all(value: int, flags: int) -> bool:');
  L.push('\treturn (value & flags) == flags', '');
  L.push('## True when any bit in [param flags] is set in [param value].');
  L.push('static func has_any(value: int, flags: int) -> bool:');
  L.push('\treturn (value & flags) != 0', '');

  L.push('# Debug decoders. A packed int is unreadable in a log or a breakpoint, which is');
  L.push('# the one real cost of packing state - so the names travel with the layout and');
  L.push('# are generated from the same source rather than retyped.');
  L.push('');
  for (const [name, def] of Object.entries(spec.enums ?? {})) {
    const fn = snake(name);
    const pairs = Object.entries(def.values).map(([k, v]) => `${v}: "${k}"`).join(', ');
    L.push(`const _${fn.toUpperCase()}_NAMES := {${pairs}}`);
    L.push(`## Human-readable name for a [enum ${name}] value.`);
    L.push(`static func ${fn}_name(value: int) -> String:`);
    L.push(`\treturn _${fn.toUpperCase()}_NAMES.get(value, "UNKNOWN(%d)" % value)`, '');
  }
  for (const [name, def] of Object.entries(spec.flags ?? {})) {
    const fn = snake(name);
    const pairs = Object.entries(def.bits).map(([k, b]) => `${1 << b}: "${k}"`).join(', ');
    L.push(`const _${fn.toUpperCase()}_NAMES := {${pairs}}`);
    L.push(`## Renders a packed [code]${name}[/code] value as "ALIVE|MOVING", or "NONE".`);
    L.push(`static func describe_${fn}(value: int) -> String:`);
    L.push('\tvar parts: PackedStringArray = []');
    L.push(`\tfor bit: int in _${fn.toUpperCase()}_NAMES:`);
    L.push('\t\tif value & bit:');
    L.push(`\t\t\tparts.append(_${fn.toUpperCase()}_NAMES[bit])`);
    L.push('\tvar known: int = 0');
    L.push(`\tfor bit: int in _${fn.toUpperCase()}_NAMES:`);
    L.push('\t\tknown |= bit');
    L.push('\tif value & ~known:');
    L.push('\t\tparts.append("UNKNOWN(0x%x)" % (value & ~known))');
    L.push('\treturn "|".join(parts) if not parts.is_empty() else "NONE"', '');
  }
  return L.join('\n').replace(/\n+$/, '\n');
}

function typescript() {
  const L = ['/**', ...BANNER.map((l) => (l ? ` * ${l}` : ' *')), ' */', ''];
  const doc = (text) => L.push('/**', ...wrapDoc(text, ' * '), ' */');

  for (const [name, def] of Object.entries(spec.enums ?? {})) {
    doc(def.description);
    L.push(`export const ${name} = {`);
    for (const [key, value] of Object.entries(def.values)) L.push(`  ${key}: ${value},`);
    L.push('} as const;');
    L.push(`export type ${name} = (typeof ${name})[keyof typeof ${name}];`, '');
  }
  for (const [name, def] of Object.entries(spec.flags ?? {})) {
    doc(def.description);
    L.push(`export const ${name} = {`);
    for (const [key, bit] of Object.entries(def.bits)) L.push(`  ${key}: 1 << ${bit},`);
    L.push('} as const;');
    L.push(`export type ${name} = (typeof ${name})[keyof typeof ${name}];`, '');
  }

  L.push('/** True when every bit in `flags` is set in `value`. */');
  L.push('export const hasAll = (value: number, flags: number): boolean => (value & flags) === flags;', '');
  L.push('/** True when any bit in `flags` is set in `value`. */');
  L.push('export const hasAny = (value: number, flags: number): boolean => (value & flags) !== 0;', '');

  L.push('/*');
  L.push(' * Debug decoders. A packed int is unreadable in devtools, ');
  L.push(' * thus the names travel with the layout and are generated');
  L.push(' * from the same source (as the GDScript side rather than retyped like a monkey press.)');
  L.push(' */');
  L.push('');
  for (const [name, def] of Object.entries(spec.enums ?? {})) {
    const pairs = Object.entries(def.values).map(([k, v]) => `${v}: '${k}'`).join(', ');
    L.push(`const ${lower(name)}Names: Record<number, string> = { ${pairs} };`);
    doc(`Human-readable name for a \`${name}\` value.`);
    L.push(`export const ${lower(name)}Name = (value: number): string =>`);
    L.push(`  ${lower(name)}Names[value] ?? \`UNKNOWN(\${value})\`;`, '');
  }
  for (const [name, def] of Object.entries(spec.flags ?? {})) {
    const pairs = Object.entries(def.bits).map(([k, b]) => `${1 << b}: '${k}'`).join(', ');
    L.push(`const ${lower(name)}Names: Record<number, string> = { ${pairs} };`);
    doc(`Renders a packed \`${name}\` value as "ALIVE|MOVING", or "NONE".`);
    L.push(`export const describe${name} = (value: number): string => {`);
    L.push(`  const parts = Object.entries(${lower(name)}Names)`);
    L.push('    .filter(([bit]) => value & Number(bit))');
    L.push('    .map(([, label]) => label);');
    L.push(`  const known = Object.keys(${lower(name)}Names).reduce((a, b) => a | Number(b), 0);`);
    L.push('  const rest = value & ~known;');
    L.push('  if (rest) parts.push(`UNKNOWN(0x${rest.toString(16)})`);');
    L.push("  return parts.length ? parts.join('|') : 'NONE';");
    L.push('};', '');
  }
  return L.join('\n').replace(/\n+$/, '\n');
}

/* targets are just two for this scope */

const MAX_WIRE_ARGS = 6;

const TS_TYPES = { string: 'string', number: 'number', boolean: 'boolean' };

function tsPayload(payload) {
  if (payload === 'unknown') return 'Record<string, unknown>';
  const entries = Object.entries(payload ?? {});
  if (!entries.length) return 'Record<string, never>';
  return `{ ${entries.map(([k, t]) => `${k}: ${TS_TYPES[t] ?? 'unknown'}`).join('; ')} }`;
}

function gdPayload(payload) {
  if (payload === 'unknown') return 'game-defined';
  const entries = Object.entries(payload ?? {});
  if (!entries.length) return 'none';
  return `{${entries.map(([k, t]) => `"${k}": ${t}`).join(', ')}}`;
}

function gameEvents() {
  const out = Object.entries(events.outbound ?? {});
  const inb = Object.entries(events.inbound ?? {});
  const L = ['class_name GameEvents', ''];
  L.push(...BANNER.map((l) => (l ? `## ${l}` : '##')));
  L.push('##');
  L.push('## The event vocabulary shared by the ECS world, the Maaack menus, and the');
  L.push('## React shell. Gameplay emits these names and nothing else - the mapping onto');
  L.push('## JS wire names lives in [constant OUTBOUND_WIRE], so producers stay unaware');
  L.push('## that a browser exists.');
  L.push('');

  const section = (title, list) => {
    L.push('# ' + '='.repeat(78));
    L.push(`# ${title}`);
    L.push('# ' + '='.repeat(78));
    L.push('');
    for (const [name, def] of list) {
      L.push(...wrapDoc(`${def.description}\n\nPayload: ${gdPayload(def.payload)}. Reaches JS as "${def.wire}".`, '## '));
      L.push(`const ${name} := &"${def.bus}"`, '');
    }
  };
  section('Outbound - Godot to React', out);
  section('Inbound - React to Godot', inb);

  L.push('# ' + '='.repeat(78));
  L.push('# Wire mapping');
  L.push('# ' + '='.repeat(78));
  L.push('');
  L.push('## Bus name to JS wire name. [JsBridgeObserver] forwards every entry, so adding');
  L.push('## an outbound event is a shared/events.json edit and nothing more.');
  L.push('const OUTBOUND_WIRE: Dictionary[StringName, String] = {');
  for (const [name, def] of out) L.push(`\t${name}: "${def.wire}",`);
  L.push('}', '');
  const emitted = [...Object.entries(events.engine ?? {}), ...out];
  const primitive = emitted.filter(([, d]) => d.payload !== 'unknown');
  const over = primitive.filter(([, d]) => Object.keys(d.payload ?? {}).length > MAX_WIRE_ARGS);
  if (over.length) {
    throw new Error(
      `events.json: ${over.map(([n]) => n).join(', ')} declare more than ${MAX_WIRE_ARGS} `
      + `payload fields. Raise MAX_WIRE_ARGS in gen-contract.mjs and add the matching `
      + `match arm in JsBridge.emit_event(), or give the event an "unknown" payload.`,
    );
  }
  L.push('## Ordered payload fields, passed to JS as positional primitives.');
  L.push('## An absent event has no flat primitive record and goes as JSON.');
  L.push('const WIRE_FIELDS: Dictionary[String, Array] = {');
  for (const [, def] of primitive) {
    const keys = Object.keys(def.payload ?? {});
    L.push(`\t"${def.wire}": [${keys.map((k) => `"${k}"`).join(', ')}],`);
  }
  L.push('}', '');
  L.push('## JS wire name to bus name. [GameBridge] republishes every entry, so a command');
  L.push('## from React is indistinguishable from in-game intent downstream.');
  L.push('const INBOUND_BUS: Dictionary[String, StringName] = {');
  for (const [name, def] of inb) L.push(`\t"${def.wire}": ${name},`);
  L.push('}');
  return L.join('\n').replace(/\n+$/, '\n');
}

function eventsTs() {
  const L = ['/**', ...BANNER.map((l) => (l ? ` * ${l}` : ' *')), ' *'];
  L.push(' * The bridge contract. Both sides are generated from the same file, so a wire');
  L.push(' * name cannot drift between Godot and React.');
  L.push(' *');
  L.push(' * Keep payloads coarse: gameplay runs at 60/120fps inside WASM, but these cross');
  L.push(' * the JS boundary only on real changes, or a few times a second for snapshots.');
  L.push(' */', '');

  const iface = (name, comment, list) => {
    L.push(`/** ${comment} */`);
    L.push(`export interface ${name} {`);
    for (const [, def] of list) {
      L.push(...wrapDoc(def.description.split('\n')[0], '  // '));
      L.push(`  '${def.wire}': ${tsPayload(def.payload)};`);
    }
    L.push('}', '');
  };

  iface('GodotToJs', 'Godot -> React.', [
    ...Object.entries(events.engine ?? {}),
    ...Object.entries(events.outbound ?? {}),
  ]);
  iface('JsToGodot', 'React -> Godot.', Object.entries(events.inbound ?? {}));

  const emitted = [...Object.entries(events.engine ?? {}), ...Object.entries(events.outbound ?? {})];
  L.push('/** Wire name -> ordered payload fields, matching the positional args Godot sends. */');
  L.push('export const WIRE_FIELDS: Record<string, readonly string[]> = {');
  for (const [, def] of emitted) {
    if (def.payload === 'unknown') continue;
    const keys = Object.keys(def.payload ?? {});
    L.push(`  '${def.wire}': [${keys.map((k) => `'${k}'`).join(', ')}],`);
  }
  L.push('};', '');
  L.push('export type GodotEvent = keyof GodotToJs;');
  L.push('export type GodotCommand = keyof JsToGodot;');
  return L.join('\n').replace(/\n+$/, '\n');
}

const targets = [
  ['godot/scripts/ecs/state_bits.gd', gdscript()],
  ['vite/src/godot/state.ts', typescript()],
  ['godot/scripts/ecs/game_events.gd', gameEvents()],
  ['vite/src/godot/events.ts', eventsTs()],
];

let stale = false;
for (const [rel, content] of targets) {
  const path = join(root, rel);
  if (check) {
    let existing = '';
    try {
      existing = readFileSync(path, 'utf8');
    } catch {
      /* missing counts as stale, should eventually trigger an issue ticket */
    }
    if (existing !== content) {
      console.error(`stale: ${rel}`);
      stale = true;
    }
  } else {
    writeFileSync(path, content);
    console.log(`wrote ${rel}`);
  }
}

if (check && stale) {
  console.error('\nshared/*.json changed without regenerating; resolve via npm run gen:state');
  process.exit(1);
}
if (check) console.log('hell ya brother, generated state files are up to date');
