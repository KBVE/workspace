import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
	ReconnectingSocket,
	defaultCloseReason,
	type ConnectionState,
} from './connection';
import { FakeSocket } from './fake-socket.testing';

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
		FakeSocket.reset();
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


	// ReconnectingSocket is reachable from the React-free entry points, which
	// exist so sim and netcode can run in a worker. A worker has no `window`,
	// and the reconnect path used to schedule through it -- so the first drop
	// threw inside a close handler and the socket stayed dead with nothing left
	// to revive it.
	it('reconnects in a host that has no window', () => {
		vi.stubGlobal('window', undefined);

		const socket = make({ maxAttempts: 2 });
		expect(() => socket.connect()).not.toThrow();

		FakeSocket.instances[0].fireClose();
		expect(states.at(-1)!.status).toBe('reconnecting');

		vi.advanceTimersByTime(1000);
		expect(FakeSocket.instances).toHaveLength(2);

		expect(() => socket.close()).not.toThrow();
		expect(states.at(-1)!.status).toBe('closed');
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

describe('ReconnectingSocket.connect', () => {
	// connect() is called by the retry timer as well as by a caller, so it has
	// to be idempotent while a socket is already up -- otherwise a manual
	// connect() during a live session opens a second one and orphans the first.
	it('does nothing when a socket already exists', () => {
		vi.useFakeTimers();
		FakeSocket.reset();
		vi.stubGlobal('WebSocket', FakeSocket);

		const socket = new ReconnectingSocket({ url: 'ws://test' }, {});
		socket.connect();
		socket.connect();

		expect(FakeSocket.instances).toHaveLength(1);
		vi.useRealTimers();
		vi.unstubAllGlobals();
	});
});
