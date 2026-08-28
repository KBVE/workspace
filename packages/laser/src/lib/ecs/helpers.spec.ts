import { describe, it, expect } from 'vitest';
import { addComponent, addEntity, createWorld } from './bitecs';
import { Transform3 } from './props';
import {
	SideMap,
	nearestInRange,
	packTile,
	queryInRange,
} from './helpers';

describe('packTile', () => {
	it('is deterministic', () => {
		expect(packTile(3, -7)).toBe(packTile(3, -7));
	});

	it('produces a unique key per tile across a grid incl. negatives', () => {
		const seen = new Map<number, string>();
		for (let x = -40; x <= 40; x++) {
			for (let y = -40; y <= 40; y++) {
				const key = packTile(x, y);
				const tag = `${x},${y}`;
				const prev = seen.get(key);
				expect(prev, `collision ${tag} vs ${prev}`).toBeUndefined();
				seen.set(key, tag);
			}
		}
	});

	it('keeps x and y independent (swapping differs off the diagonal)', () => {
		expect(packTile(2, 5)).not.toBe(packTile(5, 2));
		expect(packTile(-2, 5)).not.toBe(packTile(5, -2));
	});

	it('returns a non-negative integer for negative coords', () => {
		const k = packTile(-1, -1);
		expect(Number.isInteger(k)).toBe(true);
		expect(k).toBeGreaterThanOrEqual(0);
	});
});

describe('range queries', () => {
	// Positions as plain arrays: the signature takes ArrayLike, which is what
	// lets a caller pass either a bitECS typed-array store or a literal.
	const world = createWorld();
	const eids = [addEntity(world), addEntity(world), addEntity(world)];
	for (const eid of eids) addComponent(world, eid, Transform3);

	const pos = { x: [] as number[], y: [] as number[] };
	const place = (eid: number, x: number, y: number) => {
		pos.x[eid] = x;
		pos.y[eid] = y;
	};
	place(eids[0], 0, 0);
	place(eids[1], 3, 4); // exactly 5 away
	place(eids[2], 30, 0);

	describe('queryInRange', () => {
		it('yields only entities inside the radius', () => {
			const found = [
				...queryInRange(world, [Transform3], pos, 0, 0, 10),
			];
			expect(found).toEqual([eids[0], eids[1]]);
		});

		// The comparison is `<=`, so the boundary is inside. A caller asking for
		// "within 5 tiles" means the tile 5 away counts.
		it('includes an entity exactly on the boundary', () => {
			expect([...queryInRange(world, [Transform3], pos, 0, 0, 5)]).toContain(
				eids[1],
			);
			expect([
				...queryInRange(world, [Transform3], pos, 0, 0, 4.9),
			]).not.toContain(eids[1]);
		});

		it('yields nothing when the radius reaches no one', () => {
			expect([
				...queryInRange(world, [Transform3], pos, 100, 100, 1),
			]).toEqual([]);
		});

		// It is a generator, so a caller that only wants the first match does
		// not pay for the rest of the world.
		it('is lazy', () => {
			const gen = queryInRange(world, [Transform3], pos, 0, 0, 100);
			expect(gen.next().value).toBe(eids[0]);
			gen.return(undefined);
		});
	});

	describe('nearestInRange', () => {
		it('returns the closest entity within the radius', () => {
			expect(nearestInRange(world, [Transform3], pos, 4, 4, 10)).toBe(eids[1]);
		});

		it('returns null when nothing is in range', () => {
			expect(nearestInRange(world, [Transform3], pos, 100, 100, 1)).toBeNull();
		});

		// eid 0 is a legitimate entity id, so "found nothing" cannot be signalled
		// by returning a falsy number -- that is what the null is for.
		it('distinguishes a hit on entity zero from a miss', () => {
			const nearest = nearestInRange(world, [Transform3], pos, 0, 0, 1);
			expect(nearest).toBe(eids[0]);
			expect(nearest).not.toBeNull();
		});
	});
});

describe('SideMap', () => {
	it('stores, reads back and reports its size', () => {
		const map = new SideMap<string>();
		map.set(1, 'a');
		map.set(2, 'b');

		expect(map.get(1)).toBe('a');
		expect(map.has(2)).toBe(true);
		expect(map.size).toBe(2);
	});

	it('returns undefined for an entity it does not hold', () => {
		const map = new SideMap<string>();
		expect(map.get(99)).toBeUndefined();
		expect(map.has(99)).toBe(false);
	});

	// delete hands back what it removed, so a caller can dispose of the value
	// without a get-then-delete pair.
	it('returns the removed value on delete', () => {
		const map = new SideMap<string>();
		map.set(1, 'a');

		expect(map.delete(1)).toBe('a');
		expect(map.delete(1)).toBeUndefined();
		expect(map.size).toBe(0);
	});

	it('iterates values and entries, and clears', () => {
		const map = new SideMap<string>();
		map.set(1, 'a');
		map.set(2, 'b');

		expect([...map.values()]).toEqual(['a', 'b']);
		expect([...map.entries()]).toEqual([
			[1, 'a'],
			[2, 'b'],
		]);

		map.clear();
		expect(map.size).toBe(0);
	});
});
