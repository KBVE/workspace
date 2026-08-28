import { describe, it, expect } from 'vitest';
import { findTilePath } from './path';

const noBlocks = () => false;

describe('findTilePath', () => {
	it('returns empty when already at target', () => {
		expect(findTilePath({ x: 2, y: 2 }, { x: 2, y: 2 }, noBlocks)).toEqual(
			[],
		);
	});

	it('returns empty when target is blocked', () => {
		const blocked = (x: number, y: number) => x === 3 && y === 0;
		expect(findTilePath({ x: 0, y: 0 }, { x: 3, y: 0 }, blocked)).toEqual(
			[],
		);
	});

	it('walks a straight line excluding the origin', () => {
		const path = findTilePath({ x: 0, y: 0 }, { x: 3, y: 0 }, noBlocks);
		expect(path).toEqual([
			{ x: 1, y: 0 },
			{ x: 2, y: 0 },
			{ x: 3, y: 0 },
		]);
	});

	it('routes around a wall', () => {
		// Wall along x=1 for y=0..2, leaving a gap at y=3.
		const blocked = (x: number, y: number) => x === 1 && y <= 2;
		const path = findTilePath({ x: 0, y: 0 }, { x: 2, y: 0 }, blocked);
		expect(path.length).toBeGreaterThan(2);
		expect(path[path.length - 1]).toEqual({ x: 2, y: 0 });
		// Never steps onto the wall.
		expect(path.every((t) => !(t.x === 1 && t.y <= 2))).toBe(true);
	});

	it('returns empty when unreachable', () => {
		// Fully wall off the target column.
		const blocked = (x: number) => x === 1;
		expect(findTilePath({ x: 0, y: 0 }, { x: 2, y: 0 }, blocked)).toEqual(
			[],
		);
	});
});

describe('findTilePath limits', () => {
	const open = () => false;

	// The target is reachable in principle but walled off, so BFS drains its
	// queue without arriving. That is a different exit from hitting the
	// exploration cap, and it has to return an empty path rather than walk back
	// from a node it never reached.
	it('returns nothing when the start is enclosed', () => {
		const blocked = (x: number, y: number) =>
			(Math.abs(x) === 1 && Math.abs(y) <= 1) ||
			(Math.abs(y) === 1 && Math.abs(x) <= 1);

		expect(findTilePath({ x: 0, y: 0 }, { x: 5, y: 0 }, blocked, 32)).toEqual(
			[],
		);
	});

	// maxLen bounds the walk back as well as the search: a route longer than the
	// caller allowed is not a shorter answer, it is no answer. The server caps
	// the same way, so returning a too-long path here would desync prediction.
	it('returns nothing when the route is longer than maxLen allows', () => {
		expect(findTilePath({ x: 0, y: 0 }, { x: 7, y: 0 }, open, 6)).toEqual([]);
	});

	it('returns the route when it fits within maxLen', () => {
		const path = findTilePath({ x: 0, y: 0 }, { x: 3, y: 0 }, open, 6);
		expect(path).toHaveLength(3);
		expect(path.at(-1)).toEqual({ x: 3, y: 0 });
	});

	it('returns nothing when the target itself is blocked', () => {
		const blocked = (x: number) => x === 3;
		expect(findTilePath({ x: 0, y: 0 }, { x: 3, y: 0 }, blocked, 32)).toEqual(
			[],
		);
	});
});
