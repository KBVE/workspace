/**
 * GENERATED FILE - DO NOT EDIT.
 *
 * Source: shared/state.json + shared/events.json
 * Regenerate: npm run gen (from vite/). Runs automatically on dev and build.
 */

/**
 * Where the game as a whole is; replaces sniffing scene paths on the React side.
 */
export const RunState = {
  BOOTING: 0,
  MENU: 1,
  PLAYING: 2,
  PAUSED: 3,
  ENDED: 4,
} as const;
export type RunState = (typeof RunState)[keyof typeof RunState];

/**
 * Which kind of world the player is in right now. A murder mystery moves between flat
 * interior scenes and spatial sections, and both React and the ECS need to know which
 * without guessing from the scene path.
 */
export const WorldMode = {
  NONE: 0,
  MODE_2D: 1,
  MODE_3D: 2,
} as const;
export type WorldMode = (typeof WorldMode)[keyof typeof WorldMode];

/**
 * What kind of fact a journal entry records. The journal is the run's memory: who spoke
 * to whom, what was used on what, where the player has been. Each entry carries a ULID,
 * so entries sort by when they happened without a clock field being trusted or
 * compared.
 */
export const JournalKind = {
  ENTERED: 0,
  TALKED: 1,
  SHOWED: 2,
  USED: 3,
  FOUND: 4,
  ACCUSED: 5,
} as const;
export type JournalKind = (typeof JournalKind)[keyof typeof JournalKind];

/**
 * Per frame player state! Packed because systems test these thousands of times a
 * second; a bit test is a single AND against a register but overkill for now, damn
 * safari.
 */
export const PlayerFlags = {
  ALIVE: 1 << 0,
  MOVING: 1 << 1,
  ATTACKING: 1 << 2,
  INVULNERABLE: 1 << 3,
} as const;
export type PlayerFlags = (typeof PlayerFlags)[keyof typeof PlayerFlags];

/** True when every bit in `flags` is set in `value`. */
export const hasAll = (value: number, flags: number): boolean => (value & flags) === flags;

/** True when any bit in `flags` is set in `value`. */
export const hasAny = (value: number, flags: number): boolean => (value & flags) !== 0;

/*
 * Debug decoders. A packed int is unreadable in devtools, 
 * thus the names travel with the layout and are generated
 * from the same source (as the GDScript side rather than retyped like a monkey press.)
 */

const runStateNames: Record<number, string> = { 0: 'BOOTING', 1: 'MENU', 2: 'PLAYING', 3: 'PAUSED', 4: 'ENDED' };
/**
 * Human-readable name for a `RunState` value.
 */
export const runStateName = (value: number): string =>
  runStateNames[value] ?? `UNKNOWN(${value})`;

const worldModeNames: Record<number, string> = { 0: 'NONE', 1: 'MODE_2D', 2: 'MODE_3D' };
/**
 * Human-readable name for a `WorldMode` value.
 */
export const worldModeName = (value: number): string =>
  worldModeNames[value] ?? `UNKNOWN(${value})`;

const journalKindNames: Record<number, string> = { 0: 'ENTERED', 1: 'TALKED', 2: 'SHOWED', 3: 'USED', 4: 'FOUND', 5: 'ACCUSED' };
/**
 * Human-readable name for a `JournalKind` value.
 */
export const journalKindName = (value: number): string =>
  journalKindNames[value] ?? `UNKNOWN(${value})`;

const playerFlagsNames: Record<number, string> = { 1: 'ALIVE', 2: 'MOVING', 4: 'ATTACKING', 8: 'INVULNERABLE' };
/**
 * Renders a packed `PlayerFlags` value as "ALIVE|MOVING", or "NONE".
 */
export const describePlayerFlags = (value: number): string => {
  const parts = Object.entries(playerFlagsNames)
    .filter(([bit]) => value & Number(bit))
    .map(([, label]) => label);
  const known = Object.keys(playerFlagsNames).reduce((a, b) => a | Number(b), 0);
  const rest = value & ~known;
  if (rest) parts.push(`UNKNOWN(0x${rest.toString(16)})`);
  return parts.length ? parts.join('|') : 'NONE';
};
