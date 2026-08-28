import { create } from 'zustand';

/**
 * The reader's own sheet.
 *
 * Clue is played with a printed card and a pencil, and the card is not evidence:
 * it is what the player believes, which is a different thing from what the run
 * has established. The journal and the case board hold the second. This holds
 * the first, and nothing in it is checked against the answer -- a reader who
 * crosses off the culprit on the first hour is allowed to be wrong, and being
 * allowed to be wrong is the whole reason the sheet is worth keeping.
 *
 * Kept in memory and nowhere else. A reload boots a fresh engine and draws a
 * fresh night, so marks that outlived the page would be marks about somebody
 * else's evening.
 */
export type Mark = 'clear' | 'out' | 'likely';

/** Blank, struck out, then circled, then blank again -- a pencil on a card. */
const NEXT: Record<Mark, Mark> = { clear: 'out', out: 'likely', likely: 'clear' };

interface NotebookStore {
  marks: Record<string, Mark>;
}

export const useNotebookStore = create<NotebookStore>()(() => ({ marks: {} }));

const set = useNotebookStore.setState;

/**
 * Keys are prefixed by column rather than bare content ids, because the three
 * vocabularies are separate and nothing says a room and a weapon will never be
 * given the same name.
 */
export const markKey = (column: string, id: string): string => `${column}:${id}`;

export const cycleMark = (key: string): void =>
  set((s) => ({ marks: { ...s.marks, [key]: NEXT[s.marks[key] ?? 'clear'] } }));

export const clearMarks = (): void => set({ marks: {} });

export const useMark = (key: string): Mark =>
  useNotebookStore((s) => s.marks[key] ?? 'clear');

export const useMarkedCount = (): number =>
  useNotebookStore((s) => Object.values(s.marks).filter((m) => m !== 'clear').length);


/**
 * The accusation being assembled, as content ids, empty until each part is chosen.
 *
 * Kept beside the marks because it is the same act: the sheet is where the reader
 * works it out and this is where they commit to it. Nothing here reaches the engine
 * until they say so -- a half-built accusation is a thought, not an answer.
 */
interface NamingStore {
  who: string;
  weapon: string;
  room: string;
}

export const useNamingStore = create<NamingStore>()(() => ({ who: '', weapon: '', room: '' }));

const setNaming = useNamingStore.setState;

export const name = (part: keyof NamingStore, id: string): void =>
  setNaming((s) => ({ [part]: s[part] === id ? '' : id }) as Partial<NamingStore>);

export const forgetNaming = (): void => setNaming({ who: '', weapon: '', room: '' });

export const useNaming = (): NamingStore => useNamingStore((s) => s);

/** All three, or it is not an accusation. */
export const useNamingIsWhole = (): boolean =>
  useNamingStore((s) => Boolean(s.who && s.weapon && s.room));
