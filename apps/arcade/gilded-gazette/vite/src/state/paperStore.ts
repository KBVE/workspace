import { create } from 'zustand';
import { installGodotBridge } from '../godot/bridge';
import { outcomeKicker, selectArticle, wireLine, type Article } from '../content/content';

export type View = 'world' | 'paper';

export interface PlateRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface Dispatch {
  id: number;
  label: string;
  text: string;
}

const DISPATCH_LIMIT = 12;

export interface RunningOrder {
  level: string;
  index: number;
  total: number;
  outcome: string;
}

interface PaperStore {
  view: View;
  plate: PlateRect | null;
  edition: Article | null;
  dispatches: Dispatch[];
  order: RunningOrder | null;
  clock: number | null;
}

export const usePaperStore = create<PaperStore>()(() => ({

  view: 'paper',
  plate: null,
  edition: selectArticle({ level: null, clock: null }),
  dispatches: [],
  order: null,
  clock: null,
}));

const set = usePaperStore.setState;

let dispatchSeq = 0;

const pushDispatch = (label: string, text: string): void => {
  dispatchSeq += 1;
  set((s) => ({
    dispatches: [{ id: dispatchSeq, label, text }, ...s.dispatches].slice(0, DISPATCH_LIMIT),
  }));
};

export const wire = (key: string, vars: Record<string, string | number> = {}): void => {
  const line = wireLine(key, vars);
  if (line) pushDispatch(line.label, line.text);
};

function reprint(outcome?: string): void {
  const { order, clock } = usePaperStore.getState();
  const article = selectArticle({ level: order?.level ?? null, clock });
  if (!article) return;
  const kicker = (outcome && outcomeKicker(outcome)) || article.kicker;
  set({ edition: { ...article, kicker } });
}

export const setView = (view: View): void => set({ view });

export const toggleView = (): void =>
  set((s) => ({ view: s.view === 'world' ? 'paper' : 'world' }));

export const setPlate = (plate: PlateRect): void =>
  set((s) => {
    const p = s.plate;
    if (p && p.x === plate.x && p.y === plate.y && p.w === plate.w && p.h === plate.h) return s;
    return { plate };
  });

const bridge = installGodotBridge();

let openedForLoad = false;

bridge.on('scene:loading', ({ status, progress, scene }) => {
  if (status === 'start') {
    openedForLoad = usePaperStore.getState().view === 'world';
    if (openedForLoad) set({ view: 'paper' });
    wire('scene:loading');
    return;
  }
  if (status === 'failed') {
    wire('scene:failed', { scene });
    openedForLoad = false;
    return;
  }
  if (status === 'ready') {
    wire('scene:ready');
    if (openedForLoad) set({ view: 'world' });
    openedForLoad = false;
    return;
  }

  void progress;
});

bridge.on('level:changed', (order) => {
  set({ order });
  reprint(order.outcome);
  wire(`level:${order.outcome}`, {
    level: order.level,
    chapter: order.index + 1,
    total: order.total,
  });
});

bridge.on('world:clock', ({ hour, minute }) => {
  const clock = hour * 60 + minute;
  const before = usePaperStore.getState().edition?.id;
  set({ clock });
  reprint();
  const after = usePaperStore.getState().edition;
  if (after && after.id !== before) wire('edition:new', { title: after.title });
});

bridge.on('game:score', ({ score }) => wire('game:score', { score }));

bridge.on('game:run_over', () => wire('game:run_over'));

export const useView = () => usePaperStore((s) => s.view);
export const usePlate = () => usePaperStore((s) => s.plate);
export const useEdition = () => usePaperStore((s) => s.edition);
export const useDispatches = () => usePaperStore((s) => s.dispatches);
export const useRunningOrder = () => usePaperStore((s) => s.order);
export const useClock = () => usePaperStore((s) => s.clock);
