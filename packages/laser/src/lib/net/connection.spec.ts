import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
	ReconnectingSocket,
	defaultCloseReason,
	type ConnectionState,
} from './connection';

/**
 * A WebSocket that never touches the network. Every instance registers itself
 * so a test can drive the open/close callbacks by hand, which is the only way
 * to exercise reconnect behaviour without waiting on real timers.
 */
class FakeSocket {
	static instances: FakeSocket[] = [];
	/** Set to make the constructor throw, the way a malformed URL does. */
	static throwOnConstruct: string | null = null;

	static OPEN = 1;
	static CLOSED = 3;

	readyState = 0;
	binaryType = '';
	sent: unknown[] = [];
	private listeners = new Map<string, Set<(ev: unknown) => void>>();

	constructor(public url: string) {
		if (FakeSocket.throwOnConstruct) {
			throw new SyntaxError(FakeSocket.throwOnConstruct);
		}
		FakeSocket.instances.push(this);
	}

	addEventListener(
		type: string,
		fn: (ev: unknown) => void,
		opts?: { signal?: AbortSignal },
	) {
		if (opts?.signal?.aborted) return;
		let set = this.listeners.get(type);
		if (!set) this.listeners.set(type, (set = new Set()));
		set.add(fn);
		opts?.signal?.addEventListener('abort', () => set!.delete(fn));
	}

	removeEventListener(type: string, fn: (ev: unknown) => void) {
		this.listeners.get(type)?.delete(fn);
	}

	send(data: unknown) {
		this.sent.push(data);
	}

	close() {
		this.readyState = FakeSocket.CLOSED;
	}

	/** Drives the events a real socket would fire. */
	fireOpen() {
		this.readyState = FakeSocket.OPEN;
		for (const fn of this.listeners.get('open') ?? []) fn({});
	}

	fireClose(code = 1006, reason = '') {
		this.readyState = FakeSocket.CLOSED;
		for (const fn of this.listeners.get('close') ?? []) fn({ code, reason });
	}

	get listenerCount() {
		let total = 0;
		for (const set of this.listeners.values()) total += set.size;
		return total;
	}
}

describe('defaultCloseReason', () => {
	it('separates a server drop from a handshake that never opened', () => {
		expect(defaultCloseReason(1000, '', true)).toBe('disconnected');
		expect(defaultCloseReason(1006, '', true)).toBe(
			'server dropped connection (code 1006)',
		);
		expect(defaultCloseReason(1006, '', false)).toBe(
			'cannot reach server — down or rejected',
		);
	});

	it('prefers the server-supplied reason when there is one', () => {
		expect(defaultCloseReason(1011, ' boom ', true)).toBe('boom');
		expect(defaultCloseReason(4001, 'bad token', false)).toBe('bad token');
	});
});

describe('ReconnectingSocket', () => {
	let states: ConnectionState[];

	beforeEach(() => {
		vi.useFakeTimers();
		FakeSocket.instances = [];
		FakeSocket.throwOnConstruct = null;
		vi.stubGlobal('WebSocket', FakeSocket);
		states = [];
	});

	afterEach(() => {
		vi.useRealTimers();
		vi.unstubAllGlobals();
	});

	const make = (opts = {}) =>
		new ReconnectingSocket(
			{ url: 'ws://test', baseDelayMs: 100, ...opts },
			{ onState: (s) => states.push(s) },
		);

	it('reports connected once the socket opens', () => {
		make().connect();
		FakeSocket.instances[0].fireOpen();
		expect(states.map((s) => s.status)).toEqual(['connecting', 'connected']);
	});

	it('backs off exponentially, capped at maxDelayMs', () => {
		make({ maxDelayMs: 250 }).connect();
		const delays: number[] = [];
		for (let i = 0; i < 4; i++) {
			FakeSocket.instances[i].fireClose();
			delays.push(states.at(-1)!.nextRetryMs!);
			vi.advanceTimersByTime(1000);
		}
		expect(delays).toEqual([100, 200, 250, 250]);
	});

	it('goes terminal after maxAttempts', () => {
		make({ maxAttempts: 2 }).connect();
		for (let i = 0; i < 3; i++) {
			FakeSocket.instances[i].fireClose();
			vi.advanceTimersByTime(1000);
		}
		expect(states.at(-1)!.status).toBe('closed');
		expect(FakeSocket.instances).toHaveLength(3);
	});

	// A URL factory exists to refresh a token per attempt, so it can produce a
	// string the WebSocket constructor rejects. Before this was handled the
	// throw escaped connect(): no socket, no close event, no retry timer, and a
	// state stuck on 'connecting' with nothing left alive to move it.
	it('treats a constructor throw as a failed attempt and retries', () => {
		FakeSocket.throwOnConstruct = 'not a valid ws url';
		const socket = make({ maxAttempts: 1 });
		expect(() => socket.connect()).not.toThrow();

		expect(states.at(-1)!.status).toBe('reconnecting');
		expect(states.at(-1)!.reason).toContain('not a valid ws url');

		// And the retry actually happens rather than the timer never being set.
		FakeSocket.throwOnConstruct = null;
		vi.advanceTimersByTime(1000);
		expect(FakeSocket.instances).toHaveLength(1);
	});

	// close() reports 'closed' immediately, and the browser then delivers the
	// socket's own close event. Both used to reach onState, so every consumer
	// saw the shutdown twice -- GameClient re-emits it as a 'close' event, so a
	// handler that tears down a scene ran twice.
	it('reports a deliberate close exactly once', () => {
		const socket = make();
		socket.connect();
		FakeSocket.instances[0].fireOpen();
		states.length = 0;

		socket.close();
		FakeSocket.instances[0].fireClose(1000);

		expect(states.map((s) => s.status)).toEqual(['closed']);
	});

	it('detaches its listeners on close', () => {
		const socket = make();
		socket.connect();
		expect(FakeSocket.instances[0].listenerCount).toBeGreaterThan(0);
		socket.close();
		expect(FakeSocket.instances[0].listenerCount).toBe(0);
	});

	it('does not reconnect after a deliberate close', () => {
		const socket = make();
		socket.connect();
		socket.close();
		vi.advanceTimersByTime(5000);
		expect(FakeSocket.instances).toHaveLength(1);
	});

	it('stops when shouldReconnect says so', () => {
		let allowed = true;
		make({ shouldReconnect: () => allowed }).connect();
		allowed = false;
		FakeSocket.instances[0].fireClose();
		vi.advanceTimersByTime(5000);
		expect(states.at(-1)!.status).toBe('closed');
		expect(FakeSocket.instances).toHaveLength(1);
	});

	it('only sends while open', () => {
		const socket = make();
		socket.connect();
		socket.send('dropped');
		FakeSocket.instances[0].fireOpen();
		socket.send('delivered');
		expect(FakeSocket.instances[0].sent).toEqual(['delivered']);
	});
});
