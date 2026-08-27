import { create } from 'zustand';
import { installGodotBridge } from '../godot/bridge';
import type { GodotEvent, GodotToJs, JsToGodot } from '../godot/events';
import { RunState, PlayerFlags, hasAny } from '../godot/state';

export type BootPhase = 'idle' | 'loading' | 'running' | 'failed';

export interface TracedEvent {
  seq: number;
  at: number;
  event: string;
  payload: unknown;
}

const WARN_PATTERNS = [/^WARNING/i, /Blocking on the main thread/i, /is deprecated/i];

export interface EngineLine {
  id: number;
  level: 'warn' | 'error';
  text: string;
}

const TRACE_LIMIT = 60;
const TRACE_FLUSH_MS = 250;
const LOG_LIMIT = 40;
const JOURNAL_LIMIT = 60;

interface GameStore {
  debugOpen: boolean;
  trace: TracedEvent[];
  engineLog: EngineLine[];
  boot: BootPhase;
  progress: number | null;
  bootError: string | null;
  bridgeReady: boolean;
  run: number;
  flags: number;
  world: number;
  player: GodotToJs['player:state'] | null;
  level: GodotToJs['level:changed'] | null;
  viewer: GodotToJs['viewer:state'] | null;
  renderBudget: GodotToJs['render:budget'] | null;
  door: GodotToJs['door:state'] | null;
  loading: GodotToJs['scene:loading'] | null;
  journal: GodotToJs['journal:entry'][];
  send<C extends keyof JsToGodot>(cmd: C, payload: JsToGodot[C]): void;
}

const bridge = installGodotBridge();

export const useGameStore = create<GameStore>()(() => ({
  debugOpen: false,
  trace: [],
  engineLog: [],
  boot: 'idle',
  progress: null,
  bootError: null,
  bridgeReady: bridge.ready,
  run: RunState.BOOTING,
  flags: 0,
  world: 0,
  player: null,
  level: null,
  viewer: null,
  renderBudget: null,
  door: null,
  loading: null,
  journal: [],
  send: (cmd, payload) => bridge.send(cmd, payload),
}));

const set = useGameStore.setState;

let seq = 0;
let pending: TracedEvent[] = [];

function trace(event: string, payload: unknown): void {
  seq += 1;
  pending = [{ seq, at: Date.now(), event, payload }, ...pending].slice(0, TRACE_LIMIT);
}

function flushTrace(): void {
  if (pending.length === 0 || !useGameStore.getState().debugOpen) return;
  const drained = pending;
  pending = [];
  set({ trace: [...drained, ...useGameStore.getState().trace].slice(0, TRACE_LIMIT) });
}

setInterval(flushTrace, TRACE_FLUSH_MS);

function tracked<E extends GodotEvent>(event: E, fn?: (payload: GodotToJs[E]) => void): void {
  bridge.on(event, (payload) => {
    trace(event, payload);
    fn?.(payload);
  });
}

tracked('godot:ready', () => set({ bridgeReady: true }));
tracked('scene:changed');
tracked('game:state', ({ run, flags, world }) => set({ run, flags, world }));
tracked('player:state', (player) => set({ player }));
tracked('scene:loading', (loading) => set({ loading }));

tracked('journal:entry', (entry) =>
  set({ journal: [entry, ...useGameStore.getState().journal].slice(0, JOURNAL_LIMIT) }),
);
tracked('level:changed', (level) => set({ level }));
tracked('viewer:state', (viewer) => set({ viewer }));
tracked('render:budget', (renderBudget) => set({ renderBudget }));
tracked('door:state', (door) => set({ door }));
tracked('game:score');
tracked('game:run_over');

export const toggleDebug = () => {
  const debugOpen = !useGameStore.getState().debugOpen;
  set({ debugOpen });
  if (debugOpen) flushTrace();
};

export const clearTrace = () => {
  pending = [];
  set({ trace: [], engineLog: [], journal: [] });
};

let engineSeq = 0;

export const logEngine = (text: string) => {
  engineSeq += 1;
  const level = WARN_PATTERNS.some((re) => re.test(text)) ? 'warn' : 'error';
  const entry: EngineLine = { id: engineSeq, level, text };
  set({ engineLog: [entry, ...useGameStore.getState().engineLog].slice(0, LOG_LIMIT) });
};

export const boot = {
  start: () => set({ boot: 'loading', progress: null, bootError: null }),
  progress: (progress: number | null) => set({ progress }),
  running: () => set({ boot: 'running' }),
  fail: (bootError: string) => set({ boot: 'failed', bootError }),
};

export const useDebugOpen = () => useGameStore((s) => s.debugOpen);
export const useTrace = () => useGameStore((s) => s.trace);
export const useEngineLog = () => useGameStore((s) => s.engineLog);
export const useRun = () => useGameStore((s) => s.run);
export const useFlags = () => useGameStore((s) => s.flags);
export const useWorld = () => useGameStore((s) => s.world);
export const useBoot = () => useGameStore((s) => s.boot);
export const useProgress = () => useGameStore((s) => s.progress);
export const useBootError = () => useGameStore((s) => s.bootError);
export const useBridgeReady = () => useGameStore((s) => s.bridgeReady);
export const usePlayer = () => useGameStore((s) => s.player);
export const useLevel = () => useGameStore((s) => s.level);
export const useViewer = () => useGameStore((s) => s.viewer);
export const useRenderBudget = () => useGameStore((s) => s.renderBudget);
export const useDoor = () => useGameStore((s) => s.door);
export const useLoading = () => useGameStore((s) => s.loading);
export const useJournal = () => useGameStore((s) => s.journal);
export const useSend = () => useGameStore((s) => s.send);

export const usePaused = () => useGameStore((s) => s.run === RunState.PAUSED);

export const usePlaying = () =>
  useGameStore((s) => s.run === RunState.PLAYING || s.run === RunState.PAUSED);

export const useFlag = (flag: number) => useGameStore((s) => hasAny(s.flags, flag));

export const useInvulnerable = () => useFlag(PlayerFlags.INVULNERABLE);
