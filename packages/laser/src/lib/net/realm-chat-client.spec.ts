import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { FakeSocket } from './fake-socket.testing';
import { RealmChatClient } from './realm-chat-client';
import { GAMECHAT_KIND_CHAT } from './gamechat-wire';

const options = {
	url: 'wss://chat.kbve.com/gamechat',
	jwt: 'token-123',
	game: 'cryptothrone',
	channel: '#cryptothrone',
	nick: 'al',
};

describe('RealmChatClient', () => {
	let client: RealmChatClient;

	beforeEach(() => {
		vi.useFakeTimers();
		FakeSocket.reset();
		vi.stubGlobal('WebSocket', FakeSocket);
		client = new RealmChatClient({ ...options });
	});

	afterEach(() => {
		vi.useRealTimers();
		vi.unstubAllGlobals();
	});

	const open = () => {
		client.connect();
		FakeSocket.last.fireOpen();
	};

	const chatFrame = (over: Record<string, unknown> = {}) =>
		JSON.stringify({
			kind: GAMECHAT_KIND_CHAT,
			sender: 'someone',
			platform: 'irc',
			channel: options.channel,
			content: 'hi',
			...over,
		});

	describe('connect', () => {
		it('carries the game and token in the query string', () => {
			open();
			const url = new URL(FakeSocket.last.url);

			expect(url.searchParams.get('game')).toBe('cryptothrone');
			expect(url.searchParams.get('token')).toBe('token-123');
		});

		// The base url may already carry a query, and joining with a second '?'
		// would put the token somewhere the gateway never reads it.
		it('appends to an existing query rather than starting a new one', () => {
			const withQuery = new RealmChatClient({
				...options,
				url: 'wss://chat.kbve.com/gamechat?room=1',
			});
			withQuery.connect();

			const url = new URL(FakeSocket.last.url);
			expect(url.searchParams.get('room')).toBe('1');
			expect(url.searchParams.get('game')).toBe('cryptothrone');
		});

		it('escapes a channel or game containing url syntax', () => {
			const odd = new RealmChatClient({ ...options, game: 'a&b=c' });
			odd.connect();
			expect(new URL(FakeSocket.last.url).searchParams.get('game')).toBe(
				'a&b=c',
			);
		});

		// Without a token the gateway rejects the handshake, so there is nothing
		// to gain from opening a socket and reconnecting against it.
		it('refuses to connect with no token, and says why', () => {
			const anon = new RealmChatClient({ ...options, jwt: '' });
			const onStatus = vi.fn();
			anon.on('status', onStatus);
			anon.connect();

			expect(FakeSocket.instances).toHaveLength(0);
			expect(onStatus).toHaveBeenCalledWith(
				expect.objectContaining({
					status: 'closed',
					reason: 'missing auth token',
				}),
			);
		});

		it('emits open once the socket is up', () => {
			const onOpen = vi.fn();
			client.on('open', onOpen);
			open();
			expect(onOpen).toHaveBeenCalledOnce();
		});
	});

	describe('inbound frames', () => {
		it('emits a chat frame as a message', () => {
			const onMessage = vi.fn();
			client.on('message', onMessage);
			open();

			FakeSocket.last.fireMessage(chatFrame({ sender: 'bob', content: 'yo' }));

			expect(onMessage).toHaveBeenCalledWith({ from: 'bob', text: 'yo' });
		});

		it('ignores a frame of another kind', () => {
			const onMessage = vi.fn();
			client.on('message', onMessage);
			open();

			FakeSocket.last.fireMessage(chatFrame({ kind: 'presence' }));
			expect(onMessage).not.toHaveBeenCalled();
		});

		// One socket can carry more than one channel; a client shows its own.
		it('ignores a frame addressed to another channel', () => {
			const onMessage = vi.fn();
			client.on('message', onMessage);
			open();

			FakeSocket.last.fireMessage(chatFrame({ channel: '#somewhere-else' }));
			expect(onMessage).not.toHaveBeenCalled();
		});

		it('accepts a frame with no channel at all', () => {
			const onMessage = vi.fn();
			client.on('message', onMessage);
			open();

			FakeSocket.last.fireMessage(chatFrame({ channel: undefined }));
			expect(onMessage).toHaveBeenCalled();
		});

		it('reports a frame it cannot parse instead of dropping it', () => {
			const onError = vi.fn();
			client.on('error', onError);
			open();

			FakeSocket.last.fireMessage('not json at all');
			expect(onError).toHaveBeenCalledWith(
				expect.stringContaining('undecodable chat frame'),
			);
		});
	});

	describe('send', () => {
		it('sends a chat frame on this client’s channel', () => {
			open();
			client.send('hello');

			const frame = JSON.parse(FakeSocket.last.sent[0] as string);
			expect(frame).toMatchObject({
				kind: GAMECHAT_KIND_CHAT,
				channel: options.channel,
				content: 'hello',
			});
		});

		// The gateway broadcasts to other clients but never echoes back to the
		// originator, so without this the player never sees their own message.
		it('echoes the message locally under the sender’s nick', () => {
			const onMessage = vi.fn();
			client.on('message', onMessage);
			open();

			client.send('hello');
			expect(onMessage).toHaveBeenCalledWith({ from: 'al', text: 'hello' });
		});

		it('echoes under a placeholder when no nick was configured', () => {
			const anon = new RealmChatClient({ ...options, nick: undefined });
			const onMessage = vi.fn();
			anon.on('message', onMessage);
			anon.connect();
			FakeSocket.last.fireOpen();

			anon.send('hello');
			expect(onMessage).toHaveBeenCalledWith({ from: 'you', text: 'hello' });
		});

		it('trims, and caps the length the gateway will accept', () => {
			open();
			client.send(`  ${'x'.repeat(300)}  `);

			const frame = JSON.parse(FakeSocket.last.sent[0] as string);
			expect(frame.content).toHaveLength(200);
		});

		it.each([['   '], ['']])('sends nothing for %o', (text) => {
			open();
			client.send(text);
			expect(FakeSocket.last.sent).toEqual([]);
		});

		it('sends nothing while the socket is closed', () => {
			client.connect();
			client.send('hello');
			expect(FakeSocket.last.sent).toEqual([]);
		});
	});

	it('closes the socket and reports it once', () => {
		const onClose = vi.fn();
		client.on('close', onClose);
		open();

		client.close();
		FakeSocket.last.fireClose(1000);

		expect(onClose).toHaveBeenCalledOnce();
	});
});

describe('RealmChatClient reconnection', () => {
	beforeEach(() => {
		vi.useFakeTimers();
		FakeSocket.reset();
		vi.stubGlobal('WebSocket', FakeSocket);
	});

	afterEach(() => {
		vi.useRealTimers();
		vi.unstubAllGlobals();
	});

	// shouldReconnect is re-read on every drop, so it is what decides whether a
	// session that has lost its token keeps hammering the gateway.
	it('reconnects after a drop while it still holds a token', () => {
		const client = new RealmChatClient({ ...options });
		client.connect();
		FakeSocket.last.fireOpen();
		FakeSocket.last.fireClose();

		vi.advanceTimersByTime(5000);
		expect(FakeSocket.instances.length).toBeGreaterThan(1);
	});
});
