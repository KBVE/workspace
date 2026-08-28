import { describe, it, expect, beforeEach } from 'vitest';
import { Cat, EntityStore, type SpawnData } from './store';

type Ref = { id: number };

const spawnData = (x: number, y: number): SpawnData => ({
	tile: { x, y },
	kind: 1,
	cat: Cat.Npc,
	owner: 0,
	hostile: false,
	hp: 10,
	maxHp: 10,
});

describe('EntityStore spatial index (at)', () => {
	it('finds an entity on its tile and excludes the queried server id', () => {
		const s = new EntityStore<Ref>();
		s.spawn(100, spawnData(4, 7), { id: 100 });

		const hit = s.at(4, 7, -1);
		expect(hit?.serverEid).toBe(100);
		// Excluding the only occupant yields nothing.
		expect(s.at(4, 7, 100)).toBeNull();
		// Empty tile.
		expect(s.at(0, 0, -1)).toBeNull();
	});

	it('returns another occupant when the queried id is excluded', () => {
		const s = new EntityStore<Ref>();
		s.spawn(1, spawnData(2, 2), { id: 1 });
		s.spawn(2, spawnData(2, 2), { id: 2 });
		expect(s.at(2, 2, 1)?.serverEid).toBe(2);
		expect(s.at(2, 2, 2)?.serverEid).toBe(1);
	});

	it('moves an entity between buckets on a tile update', () => {
		const s = new EntityStore<Ref>();
		s.spawn(5, spawnData(1, 1), { id: 5 });
		s.update(5, { tile: { x: 9, y: -3 } });
		expect(s.at(1, 1, -1)).toBeNull();
		expect(s.at(9, -3, -1)?.serverEid).toBe(5);
	});

	it('drops an entity from the index on despawn', () => {
		const s = new EntityStore<Ref>();
		s.spawn(7, spawnData(3, 3), { id: 7 });
		s.despawn(7);
		expect(s.at(3, 3, -1)).toBeNull();
	});

	it('handles negative tile coordinates', () => {
		const s = new EntityStore<Ref>();
		s.spawn(8, spawnData(-12, -34), { id: 8 });
		expect(s.at(-12, -34, -1)?.serverEid).toBe(8);
	});
});

describe('EntityStore possession', () => {
	it('defaults to none, sets/reads host+kind, resets on despawn+recycle', () => {
		const s = new EntityStore<Ref>();
		s.spawn(100, spawnData(0, 0), { id: 100 });
		// Fresh entity is unpossessed.
		expect(s.possessionHost(100)).toBe(0);
		expect(s.possessionKind(100)).toBe(0);
		// Attach to a ship (host eid 555, kind 1).
		s.setPossession(100, 555, 1);
		expect(s.possessionHost(100)).toBe(555);
		expect(s.possessionKind(100)).toBe(1);
		// Despawn then respawn the same server id: the recycled bitecs slot must
		// NOT carry the stale possession (the off-grid space-handoff case).
		s.despawn(100);
		s.spawn(100, spawnData(0, 0), { id: 100 });
		expect(s.possessionHost(100)).toBe(0);
		expect(s.possessionKind(100)).toBe(0);
	});

	it('reads 0 for unknown entities and ignores set on them', () => {
		const s = new EntityStore<Ref>();
		expect(s.possessionHost(999)).toBe(0);
		expect(s.possessionKind(999)).toBe(0);
		s.setPossession(999, 1, 1); // no-op, must not throw
		expect(s.possessionHost(999)).toBe(0);
	});
});

describe('EntityStore lookups', () => {
	let store: EntityStore<Ref>;

	beforeEach(() => {
		store = new EntityStore<Ref>();
		store.spawn(100, spawnData(3, 4), { id: 100 });
	});

	it('reads a spawned entity back by its server id', () => {
		expect(store.has(100)).toBe(true);
		expect(store.eid(100)).toBeTypeOf('number');
		expect(store.tile(100)).toEqual({ x: 3, y: 4 });
		expect(store.hp(100)).toBe(10);
		expect(store.refs(100)).toEqual({ id: 100 });
	});

	// Every lookup takes a server id the caller got from the wire, so an id for
	// an entity that has already despawned is ordinary, not exceptional. Each
	// returns a neutral value rather than throwing or reading off the end of a
	// typed array -- and the neutral value differs by field: -1 for a kind or
	// owner, where 0 is a real one.
	describe('an unknown server id', () => {
		it.each([
			['has', (s: EntityStore<Ref>) => s.has(999), false],
			['eid', (s: EntityStore<Ref>) => s.eid(999), undefined],
			['tile', (s: EntityStore<Ref>) => s.tile(999), null],
			['hp', (s: EntityStore<Ref>) => s.hp(999), 0],
			['maxHp', (s: EntityStore<Ref>) => s.maxHp(999), 0],
			['kind', (s: EntityStore<Ref>) => s.kind(999), -1],
			['owner', (s: EntityStore<Ref>) => s.owner(999), -1],
			['refs', (s: EntityStore<Ref>) => s.refs(999), undefined],
			['possessionHost', (s: EntityStore<Ref>) => s.possessionHost(999), 0],
			['possessionKind', (s: EntityStore<Ref>) => s.possessionKind(999), 0],
		])('%s answers neutrally', (_name, read, expected) => {
			expect(read(store)).toEqual(expected);
		});

		it('leaves update, despawn and setPossession as no-ops', () => {
			expect(() => store.update(999, { hp: 1 })).not.toThrow();
			expect(store.despawn(999)).toBeUndefined();
			expect(() => store.setPossession(999, 1, 1)).not.toThrow();
			expect(store.size()).toBe(1);
		});
	});

	describe('update', () => {
		it('moves the entity and reindexes it by tile', () => {
			store.update(100, { tile: { x: 8, y: 9 } });

			expect(store.tile(100)).toEqual({ x: 8, y: 9 });
			expect(store.at(3, 4, 0)).toBeNull();
			expect(store.at(8, 9, 0)).toMatchObject({ serverEid: 100 });
		});

		it('changes hp and maxHp independently', () => {
			store.update(100, { hp: 5 });
			expect(store.hp(100)).toBe(5);
			expect(store.maxHp(100)).toBe(10);

			store.update(100, { maxHp: 20 });
			expect(store.maxHp(100)).toBe(20);
			expect(store.hp(100)).toBe(5);
		});

		// An empty effects list means "no effects", which has to clear the entry
		// rather than store an empty array the renderer then iterates every frame.
		it('clears effects when handed an empty list', () => {
			store.update(100, { effects: [{ kind: 1, stacks: 1 } as never] });
			expect(store.effects(100)).toHaveLength(1);

			store.update(100, { effects: [] });
			expect(store.effects(100)).toEqual([]);
		});
	});

	describe('despawn', () => {
		it('hands back the side refs so a caller can dispose of them', () => {
			expect(store.despawn(100)).toEqual({ id: 100 });
			expect(store.has(100)).toBe(false);
			expect(store.size()).toBe(0);
		});

		it('removes the entity from the tile index', () => {
			store.despawn(100);
			expect(store.at(3, 4, 0)).toBeNull();
		});

		// bitECS recycles entity ids. Possession is cleared on the way out so the
		// next entity handed this slot does not inherit a stale host -- which is
		// the space-mode handoff, where a piloting player despawns and respawns.
		it('clears possession before the id can be recycled', () => {
			store.setPossession(100, 55, 1);
			expect(store.possessionHost(100)).toBe(55);

			store.despawn(100);
			store.spawn(101, spawnData(0, 0), { id: 101 });

			expect(store.possessionHost(101)).toBe(0);
			expect(store.possessionKind(101)).toBe(0);
		});
	});

	describe('at', () => {
		it('skips the entity the caller asked to exclude', () => {
			store.spawn(200, spawnData(3, 4), { id: 200 });

			expect(store.at(3, 4, 100)).toMatchObject({ serverEid: 200 });
			expect(store.at(3, 4, 200)).toMatchObject({ serverEid: 100 });
		});

		it('returns null for an empty tile', () => {
			expect(store.at(50, 50, 0)).toBeNull();
		});
	});

	describe('entries', () => {
		it('yields server id, entity id and refs together', () => {
			store.spawn(200, spawnData(1, 1), { id: 200 });
			const seen = [...store.entries()].map(([serverEid, , refs]) => [
				serverEid,
				refs,
			]);
			expect(seen).toEqual([
				[100, { id: 100 }],
				[200, { id: 200 }],
			]);
		});
	});

	describe('possession', () => {
		it('sets and clears a host', () => {
			store.setPossession(100, 42, 1);
			expect(store.possessionHost(100)).toBe(42);
			expect(store.possessionKind(100)).toBe(1);

			store.setPossession(100, 0, 0);
			expect(store.possessionHost(100)).toBe(0);
		});
	});

	describe('queries by category', () => {
		it('lists the server ids carrying a category tag', () => {
			store.spawn(200, { ...spawnData(1, 1), cat: Cat.Player }, { id: 200 });
			store.spawn(300, { ...spawnData(2, 2), cat: Cat.Item }, { id: 300 });

			expect(store.serverIdsWith(Cat.Player)).toEqual([200]);
			expect(store.serverIdsWith(Cat.Item)).toEqual([300]);
			expect(store.serverIdsWith(Cat.Env)).toEqual([]);
		});

		it('counts hostiles within a radius', () => {
			store.spawn(200, { ...spawnData(4, 4), hostile: true }, { id: 200 });
			store.spawn(300, { ...spawnData(40, 40), hostile: true }, { id: 300 });

			expect(store.hostilesInRange(3, 4, 5)).toBe(1);
			expect(store.hostilesInRange(3, 4, 100)).toBe(2);
		});

		// A non-hostile entity carries no MonsterTag, so it must not be counted
		// however close it is.
		it('does not count a friendly entity as hostile', () => {
			expect(store.hostilesInRange(3, 4, 5)).toBe(0);
		});
	});
});
