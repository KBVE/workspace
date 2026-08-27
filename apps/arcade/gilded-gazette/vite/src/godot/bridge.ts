import { WIRE_FIELDS } from './events';
import type { GodotToJs, JsToGodot, GodotEvent, GodotCommand } from './events';

type Handler = (cmd: string, payloadJson: string) => void;
type Listener<E extends GodotEvent> = (payload: GodotToJs[E]) => void;

export interface GodotEngine {
  startGame(override: Record<string, unknown>): Promise<void>;
  requestQuit?(): void;
}

interface EngineCtor {
  new (config: Record<string, unknown>): GodotEngine;
  getMissingFeatures?(config?: Record<string, unknown>): string[];
  isCrossOriginIsolated?(): boolean;
}

declare global {
  interface Window {
    __godotBridge?: GodotBridge;
    Engine?: EngineCtor;
  }
}

export interface GodotBridge {
  ready: boolean;
  emit(event: string, ...values: unknown[]): void;
  emitJson(event: string, payloadJson: string): void;
  setHandler(cb: Handler): void;
  send<C extends GodotCommand>(cmd: C, payload?: JsToGodot[C]): void;
  on<E extends GodotEvent>(event: E, fn: Listener<E>): () => void;
  once<E extends GodotEvent>(event: E, fn: Listener<E>): () => void;
}

export function installGodotBridge(): GodotBridge {
  if (window.__godotBridge) return window.__godotBridge;

  const listeners = new Map<string, Set<(payload: unknown) => void>>();
  const queued: Array<[string, unknown]> = [];
  let handler: Handler | null = null;

  const dispatch = (event: string, payload: unknown) => {
    if (event === 'godot:ready') bridge.ready = true;
    listeners.get(event)?.forEach((fn) => fn(payload));
  };

  const drain = () => {
    if (!handler) return;
    while (queued.length) {
      const [cmd, payload] = queued.shift()!;
      handler(cmd, JSON.stringify(payload ?? {}));
    }
  };

  const bridge: GodotBridge = {
    ready: false,

    emit(event, ...values) {
      const fields = WIRE_FIELDS[event];
      const payload: Record<string, unknown> = {};
      fields?.forEach((name, i) => {
        payload[name] = values[i];
      });
      dispatch(event, payload);
    },

    emitJson(event, payloadJson) {
      dispatch(event, payloadJson ? JSON.parse(payloadJson) : {});
    },

    setHandler(cb) {
      handler = cb;
      drain();
    },

    send(cmd, payload) {
      if (!handler) {
        queued.push([cmd, payload]);
        return;
      }
      handler(cmd, JSON.stringify(payload ?? {}));
    },

    on(event, fn) {
      let set = listeners.get(event);
      if (!set) {
        set = new Set();
        listeners.set(event, set);
      }
      const wrapped = fn as (payload: unknown) => void;
      set.add(wrapped);
      return () => {
        set.delete(wrapped);
      };
    },

    once(event, fn) {
      const off = bridge.on(event, (payload) => {
        off();
        fn(payload);
      });
      return off;
    },
  };

  window.__godotBridge = bridge;
  return bridge;
}
