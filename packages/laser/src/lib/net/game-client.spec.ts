import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { FakeSocket } from './fake-socket.testing';
import {
	EPHEMERAL_BLACKJACK,
	EPHEMERAL_COMBAT,
	EPHEMERAL_CORPSE,
	EPHEMERAL_DUEL_PROMPT,
	EPHEMERAL_EQUIPPED,
	EPHEMERAL_FLOOR,
	EPHEMERAL_INVENTORY,
	EPHEMERAL_ITEM_PLACED,
	EPHEMERAL_ITEM_USED,
	EPHEMERAL_PET_BATTLE_LOG,
	EPHEMERAL_PET_BATTLE_STATE,
	EPHEMERAL_PET_LEARN,
	EPHEMERAL_PET_NOTICE,
	EPHEMERAL_PET_ROSTER,
	EPHEMERAL_PICKUP,
	EPHEMERAL_PROJECTILE,
	EPHEMERAL_SHOP,
	EPHEMERAL_STATS,
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
const encodeClientMessage = vi.fn();
/** Every payload decoder, by export name, stubbed so a test can steer it. */
const decoders: Record<string, ReturnType<typeof vi.fn>> = {};

vi.mock('./postcard-wire', async (importOriginal) => {
	const actual = await importOriginal<typeof import('./postcard-wire')>();
	encodeClientMessage.mockImplementation(actual.encodeClientMessage);

	const stubbed: Record<string, unknown> = { ...actual };
	for (const name of Object.keys(actual)) {
		if (name === 'decodeServerEvent' || !name.startsWith('decode')) continue;
		stubbed[name] = decoders[name] = vi.fn();
	}
	return { ...stubbed, decodeServerEvent, encodeClientMessage };
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
			decoders.decodeInventory.mockReturnValueOnce({ slots: [] });
			deliver({
				Ephemeral: { kind: EPHEMERAL_INVENTORY, payload },
			});

			expect(onEphemeral).toHaveBeenCalledWith({
				kind: EPHEMERAL_INVENTORY,
				payload,
			});
			expect(decoders.decodeInventory).toHaveBeenCalledWith(payload);
			expect(onInventory).toHaveBeenCalledWith({ slots: [] });
		});

		it('routes each kind to the decoder that owns it', () => {
			const onCombat = vi.fn();
			const onShop = vi.fn();
			client.on('combat', onCombat);
			client.on('shop', onShop);
			open();

			decoders.decodeCombat.mockReturnValueOnce({ hit: true });
			deliver({ Ephemeral: { kind: EPHEMERAL_COMBAT, payload: new Uint8Array() } });
			decoders.decodeShop.mockReturnValueOnce({ ok: true });
			deliver({ Ephemeral: { kind: EPHEMERAL_SHOP, payload: new Uint8Array() } });

			expect(onCombat).toHaveBeenCalledWith({ hit: true });
			expect(onShop).toHaveBeenCalledWith({ ok: true });
			expect(decoders.decodeShop).toHaveBeenCalledOnce();
		});

		// A decoder returns null for a payload it cannot make sense of. Emitting
		// that would hand every consumer a null where the type says otherwise.
		it('emits nothing when the decoder rejects the payload', () => {
			const onInventory = vi.fn();
			client.on('inventory', onInventory);
			open();

			decoders.decodeInventory.mockReturnValueOnce(null);
			deliver({ Ephemeral: { kind: EPHEMERAL_INVENTORY, payload: new Uint8Array() } });

			expect(onInventory).not.toHaveBeenCalled();
		});


		// Every ephemeral kind, its decoder and the event it becomes. The routing
		// is one long else-if chain, so a kind wired to the wrong decoder -- or
		// to a neighbour's event -- is a one-token mistake that typechecks. Two
		// of the eighteen were covered before this; the chain is only as good as
		// its least-used branch.
		const routes: [string, number, string, string][] = [
			['inventory', EPHEMERAL_INVENTORY, 'decodeInventory', 'inventory'],
			['combat', EPHEMERAL_COMBAT, 'decodeCombat', 'combat'],
			['projectile', EPHEMERAL_PROJECTILE, 'decodeProjectile', 'projectile'],
			['floor change', EPHEMERAL_FLOOR, 'decodeFloorChange', 'floor'],
			['pickup', EPHEMERAL_PICKUP, 'decodePickup', 'pickup'],
			['corpse', EPHEMERAL_CORPSE, 'decodeCorpse', 'corpse'],
			['item used', EPHEMERAL_ITEM_USED, 'decodeItemUsed', 'itemUsed'],
			['item placed', EPHEMERAL_ITEM_PLACED, 'decodeItemPlaced', 'itemPlaced'],
			['equipped', EPHEMERAL_EQUIPPED, 'decodeEquipped', 'equipped'],
			['stats', EPHEMERAL_STATS, 'decodeStats', 'stats'],
			['shop', EPHEMERAL_SHOP, 'decodeShop', 'shop'],
			['blackjack', EPHEMERAL_BLACKJACK, 'decodeBlackjack', 'blackjackState'],
			['pet battle replay', EPHEMERAL_PET_BATTLE_LOG, 'decodePetBattleReplay', 'petBattleReplay'],
			['pet battle state', EPHEMERAL_PET_BATTLE_STATE, 'decodePetBattleState', 'petBattleState'],
			['pet roster', EPHEMERAL_PET_ROSTER, 'decodePetRosterSync', 'petRoster'],
			['pet notice', EPHEMERAL_PET_NOTICE, 'decodePetNotice', 'petNotice'],
			['pet learn offer', EPHEMERAL_PET_LEARN, 'decodePetLearnOffer', 'petLearnOffer'],
			['duel prompt', EPHEMERAL_DUEL_PROMPT, 'decodeDuelPrompt', 'duelPrompt'],
		];

		it.each(routes)(
			'routes %s through its own decoder',
			(_name, kind, decoder, event) => {
				const onEvent = vi.fn();
				client.on(event as 'inventory', onEvent);
				open();

				const payload = new Uint8Array([kind]);
				const decoded = { marker: _name };
				decoders[decoder].mockReturnValueOnce(decoded);
				deliver({ Ephemeral: { kind, payload } });

				expect(decoders[decoder]).toHaveBeenCalledWith(payload);
				expect(onEvent).toHaveBeenCalledWith(decoded);
			},
		);

		it.each(routes)(
			'emits no %s event when its decoder rejects the payload',
			(_name, kind, decoder, event) => {
				const onEvent = vi.fn();
				client.on(event as 'inventory', onEvent);
				open();

				decoders[decoder].mockReturnValueOnce(null);
				deliver({ Ephemeral: { kind, payload: new Uint8Array() } });

				expect(onEvent).not.toHaveBeenCalled();
			},
		);

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


	// The command surface: forty-odd one-line wrappers, each turning a call into
	// one input inside one frame. Individually trivial and collectively the bulk
	// of the class, and the failure mode is a wrong key or a wrong field name --
	// which typechecks, ships, and is rejected silently by the server. Driving
	// them from a table keeps the check honest without forty near-identical
	// tests.
	describe('commands', () => {
		const cases: [string, (c: typeof client) => void, unknown][] = [
			['action', (c) => c.action(7, 42), { Action: { id: 7, target: 42 } }],
			['action with no target', (c) => c.action(7, null), { Action: { id: 7, target: null } }],
			['heartbeat', (c) => c.heartbeat(), { Heartbeat: { client_tick: 0 } }],
			['useItem', (c) => c.useItem('potion'), { UseItem: { item_ref: 'potion' } }],
			['simPetBattle', (c) => c.simPetBattle(), 'SimPetBattle'],
			['petTurn', (c) => c.petTurn(1, 2), { PetTurn: { action: 1, arg: 2 } }],
			['setActivePet', (c) => c.setActivePet(3), { SetActivePet: { idx: 3 } }],
			['releasePet', (c) => c.releasePet(3), { ReleasePet: { idx: 3 } }],
			['renamePet', (c) => c.renamePet(1, 'Rex'), { RenamePet: { idx: 1, name: 'Rex' } }],
			['usePetElixir', (c) => c.usePetElixir(2), { UsePetElixir: { idx: 2 } }],
			['healPets', (c) => c.healPets(88), { HealPets: { npc: 88 } }],
			['evolvePet', (c) => c.evolvePet(1, 'stone'), { EvolvePet: { idx: 1, item_ref: 'stone' } }],
			['respondLearnMove', (c) => c.respondLearnMove('p1', 2), { RespondLearnMove: { pet_id: 'p1', slot: 2 } }],
			['respondLearnMove declining', (c) => c.respondLearnMove('p1', null), { RespondLearnMove: { pet_id: 'p1', slot: null } }],
			['castSpell', (c) => c.castSpell('fire', 9), { CastSpell: { spell_ref: 'fire', target: 9 } }],
			['dropItem', (c) => c.dropItem('rock', 2), { DropItem: { item_ref: 'rock', qty: 2 } }],
			['moveItem', (c) => c.moveItem(1, 4), { MoveItem: { from: 1, to: 4 } }],
			['equipItem', (c) => c.equipItem('sword'), { EquipItem: { item_ref: 'sword' } }],
			['enterShip', (c) => c.enterShip(12), { EnterShip: { ship: 12 } }],
			['exitShip', (c) => c.exitShip(), 'ExitShip'],
			['launchSpace', (c) => c.launchSpace(), 'LaunchSpace'],
			['returnSpace', (c) => c.returnSpace(), 'ReturnSpace'],
			['placeItem', (c) => c.placeItem('crate', { x: 1, y: 2 }, 3), { PlaceItem: { item_ref: 'crate', tile: { x: 1, y: 2 }, rot: 3 } }],
			['placeItem with default rotation', (c) => c.placeItem('crate', { x: 1, y: 2 }), { PlaceItem: { item_ref: 'crate', tile: { x: 1, y: 2 }, rot: 0 } }],
			['openCorpse', (c) => c.openCorpse(5), { OpenCorpse: { corpse: 5 } }],
			['challengeNpc', (c) => c.challengeNpc(6), { ChallengeNpc: { npc: 6 } }],
			['duelChallenge', (c) => c.duelChallenge(7), { DuelChallenge: { target: 7 } }],
			['duelRespond', (c) => c.duelRespond(true), { DuelRespond: { accept: true } }],
			['takeFromCorpse', (c) => c.takeFromCorpse(5, 1), { TakeFromCorpse: { corpse: 5, slot: 1 } }],
			['pickupObject', (c) => c.pickupObject({ x: 3, y: 4 }), { PickupObject: { tile: { x: 3, y: 4 } } }],
			['fell', (c) => c.fell({ x: 3, y: 4 }), { Fell: { tile: { x: 3, y: 4 } } }],
			['buyItem', (c) => c.buyItem(2, 'axe', 1), { BuyItem: { npc: 2, item_ref: 'axe', qty: 1 } }],
			['sellItem', (c) => c.sellItem(2, 'axe', 1), { SellItem: { npc: 2, item_ref: 'axe', qty: 1 } }],
			['joinTable', (c) => c.joinTable('bj-1'), { JoinTable: { table_ref: 'bj-1' } }],
			['leaveTable', (c) => c.leaveTable(), 'LeaveTable'],
			['placeBet', (c) => c.placeBet(50), { PlaceBet: { amount: 50 } }],
			['bjAction', (c) => c.bjAction('Hit'), { BjAction: { kind: 'Hit' } }],
			['insure', (c) => c.insure(25), { Insure: { amount: 25 } }],
			['face', (c) => c.face('Up'), { Face: { facing: 'Up' } }],
		];

		it.each(cases)('%s sends its input', (_name, call, expected) => {
			open();
			call(client);

			const frames = sentMessages()
				.map((m) => (m as { Frame?: { inputs: unknown[] } }).Frame)
				.filter(Boolean);
			expect(frames).toHaveLength(1);
			expect(frames[0]!.inputs).toEqual([expected]);
		});

		it.each(cases)('%s is dropped while the socket is closed', (_name, call) => {
			client.connect();
			call(client);
			expect(sentMessages()).toEqual([]);
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
