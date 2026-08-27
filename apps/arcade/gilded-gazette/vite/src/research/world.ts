import {
  addComponent,
  addEntity,
  createRelation,
  createWorld,
  getRelationTargets,
  hasComponent,
  Pair,
  query,
  removeComponent,
} from 'bitecs';
import { JournalKind } from '../godot/state';
import {
  CARRIAGE_LOCATION_IDS,
  items,
  passengers,
  roomName,
  LOCATION_IDS,
  type Item,
  type Passenger,
  type LocationId,
} from '../content/content';

export { CARRIAGE_LOCATION_IDS, LOCATION_IDS };

const DAY = 24 * 60;

export const Source = { TIMELINE: 0, JOURNAL: 1 } as const;
export type Source = (typeof Source)[keyof typeof Source];

export const CPassenger = { suspect: [] as number[] };
export const CItem = { carried: [] as number[] };
export const CLocation = { index: [] as number[] };

export const CSighting = { at: [] as number[], source: [] as number[] };

export const CFact = { kind: [] as number[], at: [] as number[], seq: [] as number[] };

export const At = createRelation({ exclusive: true });

export const Who = createRelation({ exclusive: true });
export const Where = createRelation({ exclusive: true });
export const Actor = createRelation({ exclusive: true });
export const Target = createRelation({ exclusive: true });
export const OwnedBy = createRelation({ exclusive: true });

export const TieTo = createRelation({ store: () => ({ tie: [] as string[] }) });

export const world = createWorld();

export const labels: string[] = [];

export const ids: string[] = [];

const byId = new Map<string, number>();
const locationEid = new Map<LocationId, number>();

export const eidOf = (id: string): number => byId.get(id) ?? 0;

const minutes = (hhmm: string): number => {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
};

let departure = DAY;

export const absolute = (clock: number): number => (clock < departure ? clock + DAY : clock);

export let span: { from: number; to: number } = { from: 0, to: DAY };

function spawn(id: string, label: string): number {
  const eid = addEntity(world);
  byId.set(id, eid);
  labels[eid] = label;
  ids[eid] = id;
  return eid;
}

function sighting(subject: number, location: number, at: number, source: Source): number {
  const eid = addEntity(world);
  addComponent(world, eid, CSighting);
  CSighting.at[eid] = at;
  CSighting.source[eid] = source;
  addComponent(world, eid, Who(subject));
  addComponent(world, eid, Where(location));
  return eid;
}

function ingestLocations(): void {
  for (const id of LOCATION_IDS) {
    const eid = spawn(id, roomName(id));
    addComponent(world, eid, CLocation);
    CLocation.index[eid] = CARRIAGE_LOCATION_IDS.indexOf(id);
    locationEid.set(id, eid);
  }
}

function ingestPassengers(people: Passenger[]): void {
  for (const p of people) {
    const eid = spawn(p.id, p.listed ?? p.name);
    addComponent(world, eid, CPassenger);
    CPassenger.suspect[eid] = p.suspect ? 1 : 0;
  }

  for (const p of people) {
    const subject = eidOf(p.id);
    for (const r of p.relationships) {
      const other = eidOf(r.who);
      if (!other) continue;
      addComponent(world, subject, TieTo(other));
      Pair(TieTo, other).tie[subject] = r.tie;
    }
    for (const step of p.timeline) {
      const room = locationEid.get(step.where);
      if (room === undefined) continue;
      sighting(subject, room, absolute(minutes(step.at)), Source.TIMELINE);
    }
  }
}

function ingestItems(list: Item[]): void {
  for (const i of list) {
    const eid = spawn(i.id, i.name);
    addComponent(world, eid, CItem);
    CItem.carried[eid] = i.carried ? 1 : 0;
    const owner = i.owner ? eidOf(i.owner) : 0;
    if (owner) addComponent(world, eid, OwnedBy(owner));
  }
}

let ingested = false;

export function ingest(): void {
  if (ingested) return;
  ingested = true;

  const firsts = passengers.map((p) => (p.timeline[0] ? minutes(p.timeline[0].at) : DAY));
  departure = firsts.length ? Math.min(...firsts) : 0;

  ingestLocations();
  ingestPassengers(passengers);
  ingestItems(items);

  span = { from: departure, to: latest() };
}

let factSeq = 0;

export interface JournalFact {
  id: string;
  kind: number;
  actor: string;
  target: string;
  place: string;
  at: number;
}

export function recordFact(entry: JournalFact): void {
  const eid = addEntity(world);
  factSeq += 1;
  addComponent(world, eid, CFact);
  CFact.kind[eid] = entry.kind;
  CFact.at[eid] = absolute(entry.at);
  CFact.seq[eid] = factSeq;
  ids[eid] = entry.id;

  const actor = entry.actor ? eidOf(entry.actor) : 0;
  const target = entry.target ? eidOf(entry.target) : 0;
  const room = entry.place ? locationEid.get(entry.place as LocationId) : undefined;

  if (actor) addComponent(world, eid, Actor(actor));
  if (target) addComponent(world, eid, Target(target));
  if (room !== undefined) addComponent(world, eid, Where(room));

  if (actor && room !== undefined && entry.kind === JournalKind.ENTERED) {
    sighting(actor, room, absolute(entry.at), Source.JOURNAL);
  }

  if (span.to < CFact.at[eid]) span = { ...span, to: CFact.at[eid] };
}

const latest = (): number => {
  let max = departure;
  for (const eid of query(world, [CSighting])) if (CSighting.at[eid] > max) max = CSighting.at[eid];
  return max;
};

export function scrubTo(at: number): void {
  for (const p of query(world, [CPassenger])) {
    let bestAt = -1;
    let room = 0;
    for (const s of query(world, [CSighting, Pair(Who, p)])) {
      const when = CSighting.at[s];
      if (when > at || when < bestAt) continue;

      if (when === bestAt && CSighting.source[s] !== Source.JOURNAL) continue;
      bestAt = when;
      room = getRelationTargets(world, s, Where)[0] ?? 0;
    }
    const held = getRelationTargets(world, p, At)[0];
    if (held !== undefined && held !== room) removeComponent(world, p, At(held));
    if (room) addComponent(world, p, At(room));
  }
}

export const whoIsAt = (location: LocationId): number[] => {
  const room = locationEid.get(location);
  if (room === undefined) return [];
  return Array.from(query(world, [CPassenger, Pair(At, room)]));
};

export const roomOf = (passenger: number): LocationId | null => {
  const room = getRelationTargets(world, passenger, At)[0];
  return room === undefined ? null : (ids[room] as LocationId);
};

export interface Placement {
  at: number;
  location: LocationId;
  source: Source;
}

export const trailOf = (passenger: number): Placement[] =>
  Array.from(query(world, [CSighting, Pair(Who, passenger)]))
    .map((s) => ({
      at: CSighting.at[s],
      location: ids[getRelationTargets(world, s, Where)[0] ?? 0] as LocationId,
      source: CSighting.source[s] as Source,
    }))
    .sort((a, b) => a.at - b.at);

export interface Tie {
  other: number;
  tie: string;
  mutual: boolean;
}

export const tiesOf = (passenger: number): Tie[] => {
  const out = new Map<number, Tie>();

  for (const other of getRelationTargets(world, passenger, TieTo)) {
    out.set(other, { other, tie: Pair(TieTo, other).tie[passenger] ?? '', mutual: false });
  }
  for (const other of query(world, [CPassenger, Pair(TieTo, passenger)])) {
    const held = out.get(other);
    if (held) {
      held.mutual = true;
      continue;
    }
    out.set(other, { other, tie: Pair(TieTo, passenger).tie[other] ?? '', mutual: false });
  }
  return Array.from(out.values());
};

export const effectsOf = (passenger: number): number[] =>
  Array.from(query(world, [CItem, Pair(OwnedBy, passenger)]));

export interface FactRow {
  eid: number;
  kind: number;
  at: number;
  actor: number;
  target: number;
  place: LocationId | null;
}

const factRow = (eid: number): FactRow => {
  const place = getRelationTargets(world, eid, Where)[0];
  return {
    eid,
    kind: CFact.kind[eid],
    at: CFact.at[eid],
    actor: getRelationTargets(world, eid, Actor)[0] ?? 0,
    target: getRelationTargets(world, eid, Target)[0] ?? 0,
    place: place === undefined ? null : (ids[place] as LocationId),
  };
};

export const factsAbout = (passenger: number, limit = FACT_LIMIT): FactRow[] => {
  const seen = new Set<number>();
  for (const eid of query(world, [CFact, Pair(Actor, passenger)])) seen.add(eid);
  for (const eid of query(world, [CFact, Pair(Target, passenger)])) seen.add(eid);
  return Array.from(seen)
    .sort((a, b) => CFact.seq[b] - CFact.seq[a])
    .slice(0, limit)
    .map(factRow);
};

const FACT_LIMIT = 60;

export const allFacts = (limit = FACT_LIMIT): FactRow[] =>
  Array.from(query(world, [CFact]))
    .sort((a, b) => CFact.seq[b] - CFact.seq[a])
    .slice(0, limit)
    .map(factRow);

export const isCorroborated = (passenger: number): boolean =>
  Array.from(query(world, [CSighting, Pair(Who, passenger)])).some(
    (s) => CSighting.source[s] === Source.JOURNAL,
  );

export const isSuspect = (passenger: number): boolean =>
  hasComponent(world, passenger, CPassenger) && CPassenger.suspect[passenger] === 1;

export const roster = (): number[] => passengers.map((p) => eidOf(p.id)).filter(Boolean);

export const clockOf = (at: number): string => {
  const m = ((at % DAY) + DAY) % DAY;
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
};
