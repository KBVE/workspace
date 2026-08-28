import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Quadtree } from './quadtree';
import type { Bounds2D, Point2D, Range } from '../core/types';

describe('Quadtree', () => {
	let quadtree: Quadtree;
	const bounds: Bounds2D = { xMin: 0, xMax: 20, yMin: 0, yMax: 20 };
	const capacity = 4;

	beforeEach(() => {
		quadtree = new Quadtree(bounds, capacity);
	});

	it('should insert a range within bounds', () => {
		const range: Range = {
			name: 'test',
			bounds: { xMin: 2, xMax: 5, yMin: 2, yMax: 5 },
			action: vi.fn(),
		};
		expect(quadtree.insert(range)).toBe(true);
	});

	it('should not insert a range outside bounds', () => {
		const range: Range = {
			name: 'test',
			bounds: { xMin: 21, xMax: 25, yMin: 21, yMax: 25 },
			action: vi.fn(),
		};
		expect(quadtree.insert(range)).toBe(false);
	});

	it('should query ranges containing a point', () => {
		const ranges: Range[] = [
			{
				name: 'range1',
				bounds: { xMin: 2, xMax: 5, yMin: 2, yMax: 5 },
				action: vi.fn(),
			},
			{
				name: 'range2',
				bounds: { xMin: 10, xMax: 15, yMin: 10, yMax: 15 },
				action: vi.fn(),
			},
		];
		for (const range of ranges) {
			quadtree.insert(range);
		}
		const point: Point2D = { x: 3, y: 3 };
		const found = quadtree.query(point);
		expect(found.length).toBe(1);
		expect(found[0].name).toBe('range1');
	});

	it('should return empty array for points not within any range', () => {
		const ranges: Range[] = [
			{
				name: 'range1',
				bounds: { xMin: 2, xMax: 5, yMin: 2, yMax: 5 },
				action: vi.fn(),
			},
			{
				name: 'range2',
				bounds: { xMin: 10, xMax: 15, yMin: 10, yMax: 15 },
				action: vi.fn(),
			},
		];
		for (const range of ranges) {
			quadtree.insert(range);
		}
		const point: Point2D = { x: 6, y: 6 };
		const found = quadtree.query(point);
		expect(found.length).toBe(0);
	});

	it('should cache query results', () => {
		const range: Range = {
			name: 'range1',
			bounds: { xMin: 2, xMax: 5, yMin: 2, yMax: 5 },
			action: vi.fn(),
		};
		quadtree.insert(range);
		const point: Point2D = { x: 3, y: 3 };
		const found1 = quadtree.query(point);
		const found2 = quadtree.query(point);
		expect(found1).toBe(found2);
	});

	it('should query ranges within a bounding box', () => {
		const ranges: Range[] = [
			{
				name: 'range1',
				bounds: { xMin: 2, xMax: 5, yMin: 2, yMax: 5 },
				action: vi.fn(),
			},
			{
				name: 'range2',
				bounds: { xMin: 10, xMax: 15, yMin: 10, yMax: 15 },
				action: vi.fn(),
			},
			{
				name: 'range3',
				bounds: { xMin: 14, xMax: 16, yMin: 14, yMax: 16 },
				action: vi.fn(),
			},
		];
		for (const range of ranges) {
			quadtree.insert(range);
		}
		const boundingBox: Bounds2D = { xMin: 8, xMax: 18, yMin: 8, yMax: 18 };
		const found = quadtree.queryRange(boundingBox);
		expect(found.length).toBe(2);
		expect(found.some((r) => r.name === 'range2')).toBe(true);
		expect(found.some((r) => r.name === 'range3')).toBe(true);
	});

	it('should return empty array for bounding boxes not within any range', () => {
		const ranges: Range[] = [
			{
				name: 'range1',
				bounds: { xMin: 2, xMax: 5, yMin: 2, yMax: 5 },
				action: vi.fn(),
			},
			{
				name: 'range2',
				bounds: { xMin: 10, xMax: 15, yMin: 10, yMax: 15 },
				action: vi.fn(),
			},
		];
		for (const range of ranges) {
			quadtree.insert(range);
		}
		const boundingBox: Bounds2D = {
			xMin: 16,
			xMax: 18,
			yMin: 16,
			yMax: 18,
		};
		const found = quadtree.queryRange(boundingBox);
		expect(found.length).toBe(0);
	});

	it('should subdivide when capacity is exceeded', () => {
		const ranges: Range[] = Array.from({ length: 5 }, (_, i) => ({
			name: `range${i}`,
			bounds: { xMin: i, xMax: i + 1, yMin: i, yMax: i + 1 },
			action: vi.fn(),
		}));
		for (const range of ranges) {
			quadtree.insert(range);
		}
		const point: Point2D = { x: 0.5, y: 0.5 };
		const found = quadtree.query(point);
		expect(found.length).toBe(1);
		expect(found[0].name).toBe('range0');
	});
});

describe('subdivision', () => {
	const box = (x: number, y: number, size = 1) => ({
		bounds: { xMin: x, yMin: y, xMax: x + size, yMax: y + size },
	});

	// Past capacity the node splits and hands each range to whichever child
	// fully contains it. Nothing exercised the child branches before this, so a
	// quadrant wired to the wrong sibling would have gone unnoticed.
	it('pushes overflow into the quadrant that contains it', () => {
		const tree = new Quadtree(
			{ xMin: 0, yMin: 0, xMax: 100, yMax: 100 },
			1,
		);

		const corners = [box(1, 1), box(90, 1), box(1, 90), box(90, 90)];
		for (const c of corners) expect(tree.insert(c as never)).toBe(true);

		// Each corner comes back from a query of its own quadrant alone.
		for (const c of corners) {
			const found = tree.queryRange(c.bounds);
			expect(found).toHaveLength(1);
		}
		expect(tree.queryRange({ xMin: 0, yMin: 0, xMax: 100, yMax: 100 })).toHaveLength(
			4,
		);
	});

	// A range straddling the centre fits in no child, and the root is already at
	// capacity, so there is nowhere for it to go. Reporting that is the point:
	// silently dropping it would lose an entity from the index.
	it('refuses a range that fits in no quadrant once full', () => {
		const tree = new Quadtree({ xMin: 0, yMin: 0, xMax: 100, yMax: 100 }, 1);
		expect(tree.insert(box(1, 1) as never)).toBe(true);

		const straddling = { bounds: { xMin: 10, yMin: 10, xMax: 90, yMax: 90 } };
		expect(tree.insert(straddling as never)).toBe(false);
	});

	it('returns nothing for a query outside its bounds', () => {
		const tree = new Quadtree({ xMin: 0, yMin: 0, xMax: 10, yMax: 10 }, 4);
		tree.insert(box(1, 1) as never);

		expect(
			tree.queryRange({ xMin: 500, yMin: 500, xMax: 600, yMax: 600 }),
		).toEqual([]);
	});
});
