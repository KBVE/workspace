/**
 * A WebSocket that never touches the network.
 *
 * Every instance registers itself on the class, so a test can drive open,
 * close and message by hand. That is the only way to exercise reconnect
 * behaviour and frame dispatch without a server and without real timers.
 *
 * Named `.testing.ts` rather than `.spec.ts` so vitest does not collect it as
 * a suite of its own, and excluded from tsconfig.lib.json so it produces no
 * declarations in the published package.
 */

export class FakeSocket {
	static instances: FakeSocket[] = [];
	/** Set to make the constructor throw, the way a malformed URL does. */
	static throwOnConstruct: string | null = null;

	static OPEN = 1;
	static CLOSED = 3;

	/** Clears state between tests. */
	static reset(): void {
		FakeSocket.instances = [];
		FakeSocket.throwOnConstruct = null;
	}

	static get last(): FakeSocket {
		const socket = FakeSocket.instances.at(-1);
		if (!socket) throw new Error('no FakeSocket has been constructed');
		return socket;
	}

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
	): void {
		if (opts?.signal?.aborted) return;
		let set = this.listeners.get(type);
		if (!set) this.listeners.set(type, (set = new Set()));
		set.add(fn);
		opts?.signal?.addEventListener('abort', () => set!.delete(fn));
	}

	removeEventListener(type: string, fn: (ev: unknown) => void): void {
		this.listeners.get(type)?.delete(fn);
	}

	send(data: unknown): void {
		this.sent.push(data);
	}

	close(): void {
		this.readyState = FakeSocket.CLOSED;
	}

	fireOpen(): void {
		this.readyState = FakeSocket.OPEN;
		for (const fn of this.listeners.get('open') ?? []) fn({});
	}

	fireClose(code = 1006, reason = ''): void {
		this.readyState = FakeSocket.CLOSED;
		for (const fn of this.listeners.get('close') ?? []) fn({ code, reason });
	}

	/** Delivers a binary frame, which is the only kind the game wire uses. */
	fireMessage(data: unknown): void {
		for (const fn of this.listeners.get('message') ?? []) fn({ data });
	}

	get listenerCount(): number {
		let total = 0;
		for (const set of this.listeners.values()) total += set.size;
		return total;
	}
}
