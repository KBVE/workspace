import { create } from 'zustand';
import { installGodotBridge } from '../godot/bridge';
import { ingest, recordFact, scrubTo, span } from '../research/world';

interface ResearchStore {
  open: boolean;

  focus: number;

  at: number;
  from: number;
  to: number;

  record: number;

  clock: number;
}

ingest();

export const useResearchStore = create<ResearchStore>()(() => ({
  open: false,
  focus: 0,
  at: span.to,
  from: span.from,
  to: span.to,
  record: 0,
  clock: 0,
}));

const set = useResearchStore.setState;

scrubTo(span.to);

const bumpRecord = () => set((s) => ({ record: s.record + 1 }));
const bumpClock = () => set((s) => ({ clock: s.clock + 1 }));

export const setAt = (at: number): void => {
  const clamped = Math.max(span.from, Math.min(span.to, Math.round(at)));
  if (useResearchStore.getState().at === clamped) return;
  scrubTo(clamped);
  set({ at: clamped });
  bumpClock();
};

export const openResearch = (focus = 0): void => set({ open: true, focus });
export const closeResearch = (): void => set({ open: false });
export const setFocus = (focus: number): void =>
  set((s) => ({ focus: s.focus === focus ? 0 : focus }));

export const toggleResearch = (): void =>
  set((s) => ({ open: !s.open, focus: s.open ? 0 : s.focus }));

const bridge = installGodotBridge();

bridge.on('journal:entry', (entry) => {
  const wasLive = useResearchStore.getState().at >= useResearchStore.getState().to;
  recordFact(entry);
  set({ from: span.from, to: span.to });
  if (wasLive) {
    scrubTo(span.to);
    set({ at: span.to });
    bumpClock();
  }
  bumpRecord();
});

export const useResearchOpen = () => useResearchStore((s) => s.open);
export const useFocus = () => useResearchStore((s) => s.focus);
export const useAt = () => useResearchStore((s) => s.at);
export const useFrom = () => useResearchStore((s) => s.from);
export const useTo = () => useResearchStore((s) => s.to);
export const useRecordVersion = () => useResearchStore((s) => s.record);
export const useClockVersion = () => useResearchStore((s) => s.clock);
