import { CARRIAGE_LOCATION_IDS, LOCATION_IDS, type LocationId } from './locations.gen';
import data from './content.gen.json';

export interface Section {
  heading: string;
  paragraphs: string[];
  bullets: string[];
}

interface Prose {
  lede: string;
  body: string[];
  sections: Record<string, Section>;
  source: string;
}

export interface Article extends Prose {
  id: string;
  when: { boot?: boolean; level?: string; after?: string; before?: string };
  priority: number;
  kicker: string;
  title: string;
  caption: string;
}

export type { LocationId };
export { LOCATION_IDS, CARRIAGE_LOCATION_IDS };

export interface Location extends Prose {
  id: string;
  name: string;

  carriage?: number;
}

export interface Passenger extends Prose {
  id: string;
  name: string;
  listed?: string;
  role: string;
  berth: string;
  boarded: { at: string; where: string };
  location: LocationId;
  suspect: boolean;
  traits: string[];
  relationships: { who: string; tie: string }[];

  timeline: { at: string; where: LocationId; note: string }[];
}

export interface Item extends Prose {
  id: string;
  name: string;
  kind: 'document' | 'key' | 'personal' | 'weapon' | 'curio';
  carried: boolean;
  owner?: string;
  location?: LocationId;
  reveals: string[];
}

export interface Notice extends Prose {
  id: string;
  title: string;
  /** Basename of the sheet under public/notices, which is also the notice id. */
  image: string;
  carriage: number;
  along: number;
  side: 1 | -1;
  above: number;
  width: number;
}

interface Content {
  locations: Location[];
  gazette: {
    masthead: { title: string; issue: string; dateline: string; price: string };
    standing: { weather: string; runningOrder: string[]; notices: [string, string][] };
    kickers: Record<string, string>;
    wire: Record<string, { label: string; text: string }>;
    plate: { board: string; quiet: string };
  };
  articles: Article[];
  passengers: Passenger[];
  items: Item[];
  notices: Notice[];
}

const content = data as unknown as Content;

export const gazette = content.gazette;
export const masthead = gazette.masthead;
export const standing = gazette.standing;
export const plateCopy = gazette.plate;
export const locations = content.locations;
export const articles = content.articles;
export const passengers = content.passengers;
export const items = content.items;
export const notices = content.notices;

export const roomName = (id: LocationId): string =>
  locations.find((l) => l.id === id)?.name ?? id.replace('_', ' ');

export const locationOf = (id: LocationId): Location | null =>
  locations.find((l) => l.id === id) ?? null;

export const listedAs = (p: Passenger): string => p.listed ?? p.name;

export const carriedItems = (): Item[] => items.filter((i) => i.carried);

/** The sheet Godot named on notice:read, or null when nothing is posted under that id. */
export const noticeById = (id: string): Notice | null =>
  notices.find((n) => n.id === id) ?? null;

export const sectionOf = (entry: Prose, key: string): Section | null =>
  entry.sections[key] ?? null;

export const passengersAt = (location: LocationId): Passenger[] =>
  passengers.filter((p) => p.location === location);

export const whereWas = (p: Passenger, clock: number): LocationId | null => {
  if (p.timeline.length === 0) return null;

  const first = minutes(p.timeline[0].at);
  const now = clock < first ? clock + 24 * 60 : clock;

  let at: LocationId | null = null;
  let prev = -1;
  let day = 0;
  for (const step of p.timeline) {
    const m = minutes(step.at);
    if (prev >= 0 && m < prev) day += 24 * 60;
    if (m + day <= now) at = step.where;
    prev = m;
  }
  return at;
};

const minutes = (hhmm: string): number => {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
};

function inWindow(when: Article['when'], clock: number | null): boolean {
  if (when.after === undefined && when.before === undefined) return true;
  if (clock === null) return false;
  const from = when.after === undefined ? 0 : minutes(when.after);
  const to = when.before === undefined ? 24 * 60 : minutes(when.before);
  return from <= to ? clock >= from && clock < to : clock >= from || clock < to;
}

export interface Moment {

  level: string | null;

  clock: number | null;
}

export function selectArticle({ level, clock }: Moment): Article | null {
  const fits = articles.filter((a) => {
    if (a.when.level !== undefined && a.when.level !== level) return false;
    if (a.when.boot === true && level !== null) return false;
    return inWindow(a.when, clock);
  });
  if (fits.length === 0) return null;
  return fits.reduce((best, a) => (a.priority > best.priority ? a : best));
}

export const wireLine = (
  key: string,
  vars: Record<string, string | number> = {},
): { label: string; text: string } | null => {
  const entry = gazette.wire[key];
  if (!entry) return null;
  return {
    label: entry.label,
    text: entry.text.replace(/\{(\w+)\}/g, (_, k: string) => String(vars[k] ?? `{${k}}`)),
  };
};

export const outcomeKicker = (outcome: string): string | null =>
  gazette.kickers[outcome] ?? null;
