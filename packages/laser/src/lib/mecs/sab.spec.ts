import { describe, it, expect } from 'vitest';
import { createSabWorld, sabBytes, type Schema } from './sab';

const SCHEMA = {
	Transform: {
		px: 'f32',
		py: 'f32',
		pz: 'f32',
		qx: 'f32',
		qy: 'f32',
		qz: 'f32',
		qw: 'f32',
	},
	Health: { hp: 'f32', max: 'f32' },
	Flags: { mask: 'u32' },
} satisfies Schema;

const CAP = 128;

function makeWorld() {
	const buf = new ArrayBuffer(sabBytes(SCHEMA, CAP));
	return createSabWorld(buf, SCHEMA, CAP);
}

describe('mecs sab world', () => {
	it('spawns dense ascending eids and tracks count', () => {
		const w = makeWorld();
		expect(w.count()).toBe(0);
		const a = w.spawn();
		const b = w.spawn();
		expect(a).toBe(0);
		expect(b).toBe(1);
		expect(w.count()).toBe(2);
		expect(w.isAlive(a)).toBe(true);
	});

	it('reuses despawned slots', () => {
		const w = makeWorld();
		const a = w.spawn();
		w.spawn();
		w.despawn(a);
		expect(w.isAlive(a)).toBe(false);
		expect(w.spawn()).toBe(a);
	});

	it('component add/remove drives has() and query()', () => {
		const w = makeWorld();
		const a = w.spawn();
		const b = w.spawn();
		w.add(a, 'Health');
		w.add(a, 'Transform');
		w.add(b, 'Transform');
		expect(w.has(a, 'Health')).toBe(true);
		expect(w.has(b, 'Health')).toBe(false);
		expect(w.query(['Transform']).sort()).toEqual([a, b]);
		expect(w.query(['Transform', 'Health'])).toEqual([a]);
	});

	it('stores read/write through typed views', () => {
		const w = makeWorld();
		const e = w.spawn();
		w.add(e, 'Transform');
		w.stores.Transform.px[e] = 3.5;
		w.stores.Transform.qw[e] = 1;
		expect(w.stores.Transform.px[e]).toBeCloseTo(3.5);
		expect(w.stores.Transform.qw[e]).toBe(1);
	});

	it('despawn clears component membership', () => {
		const w = makeWorld();
		const e = w.spawn();
		w.add(e, 'Health');
		w.despawn(e);
		const e2 = w.spawn();
		expect(e2).toBe(e);
		expect(w.has(e2, 'Health')).toBe(false);
	});

	it('two worlds over one buffer share membership + data (cross-thread model)', () => {
		const buf = new ArrayBuffer(sabBytes(SCHEMA, CAP));
		const writer = createSabWorld(buf, SCHEMA, CAP);
		const reader = createSabWorld(buf, SCHEMA, CAP);
		const e = writer.spawn();
		writer.add(e, 'Transform');
		writer.stores.Transform.px[e] = 42;
		expect(reader.isAlive(e)).toBe(true);
		expect(reader.query(['Transform'])).toEqual([e]);
		expect(reader.stores.Transform.px[e]).toBe(42);
	});

	it('rejects cap mismatch on re-attach', () => {
		const buf = new ArrayBuffer(sabBytes(SCHEMA, CAP + 32));
		createSabWorld(buf, SCHEMA, CAP);
		expect(() => createSabWorld(buf, SCHEMA, CAP + 32)).toThrow(/cap/);
	});

	it('seqlock gen advances around a write', () => {
		const w = makeWorld();
		const g0 = w.gen();
		w.beginWrite();
		expect(w.gen() & 1).toBe(1);
		w.endWrite();
		expect(w.gen()).toBe(g0 + 2);
	});

	it('clear() wipes membership and reuses eid 0', () => {
		const w = makeWorld();
		const a = w.spawn();
		w.add(a, 'Health');
		w.spawn();
		w.clear();
		expect(w.count()).toBe(0);
		expect(w.isAlive(a)).toBe(false);
		expect(w.query(['Health'])).toEqual([]);
		expect(w.spawn()).toBe(0);
	});

	it('fills to capacity then returns -1', () => {
		const w = makeWorld();
		for (let i = 0; i < CAP; i++) expect(w.spawn()).toBe(i);
		expect(w.spawn()).toBe(-1);
		expect(w.count()).toBe(CAP);
	});
});

describe('field types', () => {
	// One typed array per field type. A type mapped to the wrong constructor
	// gives a store that silently truncates -- an i16 landing in a Uint8Array
	// wraps at 256 and nothing says so.
	const ALL: Schema = {
		C: { f: 'f32', i: 'i32', u: 'u32', b: 'u8', s: 'i16', w: 'u16' },
	};

	it('backs each field type with its own array kind', () => {
		const buffer = new ArrayBuffer(sabBytes(ALL, 4));
		const world = createSabWorld(buffer, ALL, 4);

		expect(world.stores.C.f).toBeInstanceOf(Float32Array);
		expect(world.stores.C.i).toBeInstanceOf(Int32Array);
		expect(world.stores.C.u).toBeInstanceOf(Uint32Array);
		expect(world.stores.C.b).toBeInstanceOf(Uint8Array);
		expect(world.stores.C.s).toBeInstanceOf(Int16Array);
		expect(world.stores.C.w).toBeInstanceOf(Uint16Array);
	});

	it('keeps a signed 16-bit value signed', () => {
		const buffer = new ArrayBuffer(sabBytes(ALL, 4));
		const world = createSabWorld(buffer, ALL, 4);

		world.stores.C.s[0] = -300;
		expect(world.stores.C.s[0]).toBe(-300);
	});
});

describe('createSabWorld guards', () => {
	// The buffer is shared across a worker boundary, so a caller sizing it by
	// hand is normal. Refusing an undersized one is the difference between a
	// clear error here and two threads disagreeing about where a field lives.
	it('refuses a buffer too small for the schema', () => {
		const schema: Schema = { C: { x: 'f32' } };
		const tooSmall = new ArrayBuffer(8);

		expect(() => createSabWorld(tooSmall, schema, 1000)).toThrow(
			/buffer 8B < required/,
		);
	});

	it('accepts a buffer sized by sabBytes', () => {
		const schema: Schema = { C: { x: 'f32' } };
		const bytes = sabBytes(schema, 16);

		expect(() => createSabWorld(new ArrayBuffer(bytes), schema, 16)).not.toThrow();
	});
});

describe('component membership and iteration', () => {
	const schema: Schema = { A: { v: 'f32' }, B: { v: 'f32' } };
	const make = () =>
		createSabWorld(new ArrayBuffer(sabBytes(schema, 64)), schema, 64);

	it('removes a component without touching the entity', () => {
		const world = make();
		const eid = world.spawn();
		world.add(eid, 'A');
		expect(world.has(eid, 'A')).toBe(true);

		world.remove(eid, 'A');
		expect(world.has(eid, 'A')).toBe(false);
		expect(world.isAlive(eid)).toBe(true);
	});

	it('despawns once, and ignores a second despawn of the same entity', () => {
		const world = make();
		const eid = world.spawn();
		world.add(eid, 'A');

		world.despawn(eid);
		expect(world.isAlive(eid)).toBe(false);
		expect(() => world.despawn(eid)).not.toThrow();
		expect(world.has(eid, 'A')).toBe(false);
	});

	describe('each', () => {
		it('visits every live entity carrying all the named components', () => {
			const world = make();
			const both = world.spawn();
			const onlyA = world.spawn();
			world.add(both, 'A');
			world.add(both, 'B');
			world.add(onlyA, 'A');

			const seen: number[] = [];
			world.each(['A', 'B'], (eid) => seen.push(eid));
			expect(seen).toEqual([both]);
		});

		// The iteration walks a bitset word at a time, clearing the lowest set
		// bit each pass, so an entity beyond the first 32 is a different code
		// path from one inside it.
		it('crosses word boundaries', () => {
			const world = make();
			const eids: number[] = [];
			for (let i = 0; i < 40; i++) {
				const eid = world.spawn();
				world.add(eid, 'A');
				eids.push(eid);
			}

			const seen: number[] = [];
			world.each(['A'], (eid) => seen.push(eid));
			expect(seen).toEqual(eids);
		});

		it('visits nothing when no entity carries the set', () => {
			const world = make();
			world.add(world.spawn(), 'A');

			const seen: number[] = [];
			world.each(['B'], (eid) => seen.push(eid));
			expect(seen).toEqual([]);
		});
	});
});

describe('header counters', () => {
	const schema: Schema = { A: { v: 'f32' } };
	const make = () =>
		createSabWorld(new ArrayBuffer(sabBytes(schema, 8)), schema, 8);

	// tick and gen live in the shared header so a reader thread can tell whether
	// the snapshot it is looking at has moved on. They are read atomically for
	// that reason and nothing was reading them.
	it('starts at zero and advances one tick per step', () => {
		const world = make();
		expect(world.tick()).toBe(0);

		expect(world.step()).toBe(1);
		expect(world.step()).toBe(2);
		expect(world.tick()).toBe(2);
	});

	it('reports a generation', () => {
		expect(make().gen()).toBeTypeOf('number');
	});
});
