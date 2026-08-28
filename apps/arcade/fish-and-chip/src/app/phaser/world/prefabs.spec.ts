import { describe, expect, it } from 'vitest';

import { collidableGids } from './palette';
import { PREFABS, gidAt, prefabProblems, type Prefab } from './prefabs';

const entries = Object.entries(PREFABS) as [string, Prefab][];

describe('prefabs', () => {
	it.each(entries)('%s is structurally sound', (_id, prefab) => {
		expect(prefabProblems(prefab)).toEqual([]);
	});

	it.each(entries)('%s records where it was extracted from', (_id, prefab) => {
		// Without this a prefab cannot be re-cut when the art changes, and the
		// whole point is that nobody retypes tiles by hand.
		expect(prefab.source).toMatch(/cloud_city\.json/);
	});

	it('gives the building a doorway that is not solid', () => {
		const building = PREFABS.building;
		const door = building.anchors.door;
		const solid = collidableGids();

		expect(door).toBeDefined();
		expect(solid.has(gidAt(building, 'buildings', door!.x, door!.y))).toBe(false);

		// And the rest of the ground floor is, or it is a wall you can walk
		// through rather than a building.
		const walls = building.layers.buildings[door!.y].filter(
			(_gid, x) => x !== door!.x,
		);
		expect(walls.every((gid) => gid === 0 || solid.has(gid))).toBe(true);
	});

	it('makes the sand pit solid, with somewhere to stand in front of it', () => {
		const pit = PREFABS.sandPit;
		const solid = collidableGids();

		// "Enter the sand pit" is the NPC's line, but the tiles are solid, so
		// the interaction is standing at its edge -- which is what the stand
		// anchor is for.
		const tiles = pit.layers.ground.flat();
		expect(tiles.every((gid) => solid.has(gid))).toBe(true);
		expect(pit.anchors.stand).toEqual({ x: 1, y: 3 });
	});
});
