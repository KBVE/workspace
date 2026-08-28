import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { FakeSocket } from './fake-socket.testing';
import {
	EPHEMERAL_COMBAT,
	EPHEMERAL_INVENTORY,
	EPHEMERAL_SHOP,
	PROTOCOL_VERSION,
	type ClientMessage,
} from './protocol';

// The decoders are stubbed and the encoder is not. What this file is about is
// the routing between them -- which frame becomes which typed event -- and
// stubbing decodeServerEvent is the only way to hand the client a frame
// without a ServerEvent encoder, which is a server-side concern and does not
// exist here. encodeClientMessage stays real so the outbound path is exercised
// end to end; it is wrapped only so a test can read back the message that was
// encoded rather than assert on bytes.
const decodeServerEvent = vi.fn();
const decodeInventory = vi.fn();
const decodeCombat = vi.fn();
const decodeShop = vi.fn();
const encodeClientMessage = vi.fn();

vi.mock('./postcard-wire', async (importOriginal) => {
	const actual = await importOriginal<typeof import('./postcard-wire')>();
	encodeClientMessage.mockImplementation(actual.encodeClientMessage);
	return {
		...actual,
		decodeServerEvent,
		decodeInventory,
		decodeCombat,
		decodeShop,
		encodeClientMessage,
	};
});

const { GameClient } = await import('./game-client');

/** The message objects the client encoded, in order. */
const sentMessages = (): ClientMessage[] =>
	encodeClientMessage.mock.calls.map(([msg]) => msg as ClientMessage);

describe('GameClient', () => {
	let client: InstanceType<typeof GameClient>;

	beforeEach(() => {
		vi.useFakeTimers();
		FakeSocket.reset();
		vi.stubGlobal('WebSocket', FakeSocket);
		vi.clearAllMocks();
		decodeServerEvent.mockReset();
		client = new GameClient({
			url: 'ws://test',
			jwt: 'token',
			kbveUsername: 'player',
		});
	});

	afterEach(() => {
		vi.useRealTimers();
		vi.unstubAllGlobals();
	});

	/** Connects and opens, which is the precondition for anything being sent. */
	const open = () => {
		client.connect();
		FakeSocket.last.fireOpen();
	};

	/** Hands the client a binary frame that decodes to `event`. */
	const deliver = (event: unknown) => {
		decodeServerEvent.mockReturnValueOnce(event);
		FakeSocket.last.fireMessage(new ArrayBuffer(8));
	};

	describe('handshake', () => {
		it('joins with its credentials as soon as the socket opens', () => {
			const onOpen = vi.fn();
			client.on('open', onOpen);
			open();

			expect(sentMessages()[0]).toEqual({
				JoinMatch: expect.objectContaining({
					jwt: 'token',
					kbve_username: 'player',
					// Pinned so a protocol bump cannot ship without the join
					// frame being looked at.
					protocol: PROTOCOL_VERSION,
				}),
			});
			expect(onOpen).toHaveBeenCalledOnce();
		});

		it('rejoins after a reconnect, because the server forgets on drop', () => {
			open();
			FakeSocket.last.fireClose();
			vi.advanceTimersByTime(5000);
			FakeSocket.last.fireOpen();

			const joins = sentMessages().filter((m) => 'JoinMatch' in (m as object));
			expect(joins).toHaveLength(2);
		});
	});

	describe('inbound frames', () => {
		it('ignores anything that is not a binary frame', () => {
			open();
			FakeSocket.last.fireMessage('a text frame');
			expect(decodeServerEvent).not.toHaveBeenCalled();
		});

		it('reports a frame it cannot decode instead of dropping it silently', () => {
			const onError = vi.fn();
			client.on('error', onError);
			open();
			decodeServerEvent.mockImplementationOnce(() => {
				throw new Error('bad tag 99');
			});
			FakeSocket.last.fireMessage(new ArrayBuffer(8));

			expect(onError).toHaveBeenCalledWith(
				expect.stringContaining('bad tag 99'),
			);
			// One unreadable frame is not a reason to end a healthy session.
			expect(client.getState().status).toBe('connected');
		});

		it('routes each server event to its own typed listener', () => {
			const onWelcome = vi.fn();
			const onSnapshot = vi.fn();
			client.on('welcome', onWelcome);
			client.on('snapshot', onSnapshot);
			open();

			deliver({ Welcome: { tick: 1 } });
			deliver({ Snapshot: { tick: 2 } });

			expect(onWelcome).toHaveBeenCalledWith({ tick: 1 });
			expect(onSnapshot).toHaveBeenCalledWith({ tick: 2 });
		});

		it('stops reconnecting once the server rejects the session', () => {
			const onReject = vi.fn();
			client.on('reject', onReject);
			open();

			deliver({ Reject: { reason: 'bad token' } });
			expect(onReject).toHaveBeenCalledWith('bad token');

			// A rejection is terminal: retrying it just gets rejected again.
			FakeSocket.last.fireClose();
			vi.advanceTimersByTime(10_000);
			expect(FakeSocket.instances).toHaveLength(1);
			expect(client.getState().status).toBe('closed');
		});
	});

	describe('ephemeral payloads', () => {
		it('emits the raw ephemeral alongside its decoded event', () => {
			const onEphemeral = vi.fn();
			const onInventory = vi.fn();
			client.on('ephemeral', onEphemeral);
			client.on('inventory', onInventory);
			open();

			const payload = new Uint8Array([1, 2, 3]);
			decodeInventory.mockReturnValueOnce({ slots: [] });
			deliver({
				Ephemeral: { kind: EPHEMERAL_INVENTORY, payload },
			});

			expect(onEphemeral).toHaveBeenCalledWith({
				kind: EPHEMERAL_INVENTORY,
				payload,
			});
			expect(decodeInventory).toHaveBeenCalledWith(payload);
			expect(onInventory).toHaveBeenCalledWith({ slots: [] });
		});

		it('routes each kind to the decoder that owns it', () => {
			const onCombat = vi.fn();
			const onShop = vi.fn();
			client.on('combat', onCombat);
			client.on('shop', onShop);
			open();

			decodeCombat.mockReturnValueOnce({ hit: true });
			deliver({ Ephemeral: { kind: EPHEMERAL_COMBAT, payload: new Uint8Array() } });
			decodeShop.mockReturnValueOnce({ ok: true });
			deliver({ Ephemeral: { kind: EPHEMERAL_SHOP, payload: new Uint8Array() } });

			expect(onCombat).toHaveBeenCalledWith({ hit: true });
			expect(onShop).toHaveBeenCalledWith({ ok: true });
			expect(decodeShop).toHaveBeenCalledOnce();
		});

		// A decoder returns null for a payload it cannot make sense of. Emitting
		// that would hand every consumer a null where the type says otherwise.
		it('emits nothing when the decoder rejects the payload', () => {
			const onInventory = vi.fn();
			client.on('inventory', onInventory);
			open();

			decodeInventory.mockReturnValueOnce(null);
			deliver({ Ephemeral: { kind: EPHEMERAL_INVENTORY, payload: new Uint8Array() } });

			expect(onInventory).not.toHaveBeenCalled();
		});

		it('ignores a kind it has no decoder for', () => {
			open();
			expect(() =>
				deliver({ Ephemeral: { kind: 0xff, payload: new Uint8Array() } }),
			).not.toThrow();
		});
	});

	describe('outbound input', () => {
		it('drops input while the socket is not open', () => {
			client.connect();
			client.action(1, null);
			expect(sentMessages()).toEqual([]);
		});

		it('sends nothing for an empty input list', () => {
			open();
			client.sendInputs([]);
			expect(sentMessages().filter((m) => 'Frame' in (m as object))).toEqual([]);
		});

		it('advances the client tick once per frame, not once per input', () => {
			open();
			client.sendInputs([{ Action: { id: 1, target: null } }, { Action: { id: 2, target: null } }]);
			client.sendInputs([{ Action: { id: 3, target: null } }]);

			const ticks = sentMessages()
				.map((m) => (m as { Frame?: { client_tick: number } }).Frame?.client_tick)
				.filter((tick) => tick !== undefined);
			expect(ticks).toEqual([1, 2]);
		});
	});

	describe('move reconciliation', () => {
		it('hands back a rising sequence number per move', () => {
			open();
			expect(client.move(1, 0, false, 1)).toBe(1);
			expect(client.move(0, 1, false, 2)).toBe(2);
		});

		it('keeps a move unacked until the server passes its sequence', () => {
			open();
			client.move(1, 0, false, 1);
			client.move(0, 1, false, 2);
			client.move(1, 1, true, 3);

			expect(client.ackMoves(2).map((m) => m.seq)).toEqual([3]);
			expect(client.ackMoves(3)).toEqual([]);
		});

		it('treats an ack of 0 as "nothing acknowledged yet"', () => {
			open();
			client.move(1, 0, false, 1);
			expect(client.ackMoves(0)).toHaveLength(1);
		});

		// The buffer is capped so an unresponsive server cannot grow it without
		// bound. The oldest sample is what goes, which means a server that then
		// acks below the cap reconciles against an incomplete history -- the
		// trade is deliberate, and this pins the size it is made at.
		it('caps the unacked buffer at 256 samples, dropping the oldest', () => {
			open();
			for (let i = 0; i < 300; i++) client.move(1, 0, false, i);
			const unacked = client.ackMoves(0);
			expect(unacked).toHaveLength(256);
			expect(unacked[0].seq).toBe(45);
			expect(unacked.at(-1)!.seq).toBe(300);
		});
	});

	describe('shutdown', () => {
		it('tells the server it is leaving before closing the socket', () => {
			open();
			client.close();

			expect(sentMessages().at(-1)).toEqual({
				Frame: expect.objectContaining({ inputs: ['Leave'] }),
			});
			expect(client.getState().status).toBe('closed');
		});

		it('reports a deliberate close exactly once', () => {
			const onClose = vi.fn();
			client.on('close', onClose);
			open();

			client.close();
			FakeSocket.last.fireClose(1000);

			expect(onClose).toHaveBeenCalledOnce();
		});

		it('does not reconnect after markTerminal', () => {
			open();
			client.markTerminal();
			FakeSocket.last.fireClose();
			vi.advanceTimersByTime(10_000);

			expect(FakeSocket.instances).toHaveLength(1);
		});
	});
});
