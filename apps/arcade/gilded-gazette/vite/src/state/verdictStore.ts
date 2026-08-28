import { create } from 'zustand';
import { installGodotBridge } from '../godot/bridge';
import { clearMarks, forgetNaming } from './notebookStore';

/**
 * The end of a run: what happened, and what the reader said happened.
 *
 * Empty until an accusation is given, because until then the engine has not sent it
 * and deliberately never will. `game:verdict` is the only event carrying the culprit,
 * and it crosses at the one moment the answer cannot spoil anything -- everything the
 * browser is handed before it is knowable without being told.
 *
 * Whether they were right is derived rather than received, for the same reason the
 * engine does not send it: the answer and the comparison of the answer are one fact
 * written twice, and two copies can disagree.
 */
export interface Verdict {
  who: string;
  weapon: string;
  room: string;
  namedWho: string;
  namedWeapon: string;
  namedRoom: string;
}

interface VerdictStore {
  verdict: Verdict | null;
  /**
   * Whether the reveal is on screen. Separate from having a verdict, so that closing
   * it leaves the case board able to say the enquiry is closed rather than forgetting
   * the run ended.
   */
  shown: boolean;
}

export const useVerdictStore = create<VerdictStore>()(() => ({
  verdict: null,
  shown: false,
}));

const set = useVerdictStore.setState;

const bridge = installGodotBridge();

bridge.on('game:verdict', (given) =>
  set({
    verdict: {
      who: given.who,
      weapon: given.weapon,
      room: given.room,
      namedWho: given.named_who,
      namedWeapon: given.named_weapon,
      namedRoom: given.named_room,
    },
    shown: true,
  }),
);

/**
 * A fresh night wipes the sheet.
 *
 * Driven off the engine saying a run started rather than off the button that asked for
 * one, because a restart can come from anywhere -- the HUD, the reveal, a devtools
 * send -- and marks about somebody else's evening surviving into this one is the same
 * bug however it was triggered. This store owns it since it is the one that knows a
 * run ended; the notebook only knows what the reader wrote.
 */
bridge.on('level:changed', ({ outcome }) => {
  if (outcome !== 'start') return;
  set({ verdict: null, shown: false });
  clearMarks();
  forgetNaming();
});

export const hideVerdict = (): void => set({ shown: false });
export const showVerdict = (): void =>
  set((s) => (s.verdict ? { shown: true } : s));

export const useVerdict = (): Verdict | null => useVerdictStore((s) => s.verdict);
export const useVerdictShown = (): boolean => useVerdictStore((s) => s.shown);

/** Right on all three, which is the only way to be right. */
export const wasRight = (v: Verdict): boolean =>
  v.who === v.namedWho && v.weapon === v.namedWeapon && v.room === v.namedRoom;
