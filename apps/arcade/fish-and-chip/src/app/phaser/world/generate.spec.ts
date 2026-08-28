import { describe, expect, it } from 'vitest';

import { collidableGids } from './palette';
import { PREFABS } from './prefabs';
import { generateTown, toTiledJSON, unreachableLandmarks, type TownMap } from './generate';

const SEEDS = [1, 2, 7, 42, 99, 1234, 8675309];

const tileAt = (map: TownMap, layer: string, x: number, y: number) =>
	map.layers.find((candidate) => candidate.name === layer)!.data[y * map.width + x];

describe('generateTown', () => {
	it('is a pure function of the seed', () => {
		expect(generateTown({ seed: 42 })).toEqual(generateTown({ seed: 42 }));
		expect(generateTown({ seed: 42 })).not.toEqual(generateTown({ seed: 43 }));
	});

	it('fences the town on every edge', () => {
		const map = generateTown({ seed: 3 });
		const solid = collidableGids();

		for (let x = 0; x < map.width; x++) {
			expect(solid.has(tileAt(map, 'ground', x, 0))).toBe(true);
			expect(solid.has(tileAt(map, 'ground', x, map.height - 1))).toBe(true);
		}
		for (let y = 0; y < map.height; y++) {
			expect(solid.has(tileAt(map, 'ground', 0, y))).toBe(true);
			expect(solid.has(tileAt(map, 'ground', map.width - 1, y))).toBe(true);
		}
	});

	// The generator throws rather than returning an unplayable town, so this
	// doubles as the check that a run of seeds all produce one.
	it.each(SEEDS)('leaves every landmark reachable on seed %i', (seed) => {
		const map = generateTown({ seed });

		expect(unreachableLandmarks(map)).toEqual([]);
	});

	it.each(SEEDS)('never spawns anyone inside scenery on seed %i', (seed) => {
		const map = generateTown({ seed });
		const solid = collidableGids();
		const standable = ({ x, y }: { x: number; y: number }) =>
			map.layers.every((layer) => !solid.has(layer.data[y * map.width + x]));

		expect(standable(map.playerSpawn)).toBe(true);
		for (const npc of map.npcSpawns) expect(standable(npc)).toBe(true);
		for (const name of ['fishingPit', 'sign', 'tombstone'] as const) {
			expect(standable(map.landmarks[name])).toBe(true);
		}
	});

	it('puts the building landmark on a doorway with a clear approach', () => {
		const map = generateTown({ seed: 11 });
		const solid = collidableGids();
		const door = map.landmarks.building;

		// The doorway is the one part of the building that is not solid.
		expect(solid.has(tileAt(map, 'buildings', door.x, door.y))).toBe(false);
		// And the tile the player walks in from stays clear.
		expect(solid.has(tileAt(map, 'buildings', door.x, door.y + 1))).toBe(false);
		expect(solid.has(tileAt(map, 'objects', door.x, door.y + 1))).toBe(false);
	});

	// The complaint that produced the street grid: buildings dropped at random
	// on open ground, doors facing nothing. A door has to open onto a street.
	it.each(SEEDS)('opens every door onto a street on seed %i', (seed) => {
		const map = generateTown({ seed });
		const streets = new Set(map.streets.map((spot) => `${spot.x},${spot.y}`));
		const buildingLayer = map.layers.find((layer) => layer.name === 'buildings')!.data;
		const door = PREFABS.building.anchors.door!;
		const doorGid = PREFABS.building.layers.buildings[door.y][door.x];

		let doors = 0;
		for (let y = 0; y < map.height; y++) {
			for (let x = 0; x < map.width; x++) {
				if (buildingLayer[y * map.width + x] !== doorGid) continue;
				doors++;
				expect(streets.has(`${x},${y + 1}`)).toBe(true);
			}
		}
		expect(doors).toBeGreaterThan(0);
	});

	it.each(SEEDS)('keeps the streets walkable on seed %i', (seed) => {
		const map = generateTown({ seed });
		const solid = collidableGids();

		for (const spot of map.streets) {
			const at = spot.y * map.width + spot.x;
			for (const layer of map.layers) expect(solid.has(layer.data[at])).toBe(false);
		}
	});

	it('is bigger than the hand-authored map it replaces', () => {
		const map = generateTown({ seed: 5 });

		// cloud_city.json was 20x20. The point of generating one is more room.
		expect(map.width * map.height).toBeGreaterThan(20 * 20);
	});

	it('refuses a town too small to lay streets in', () => {
		expect(() => generateTown({ seed: 1, width: 8, height: 8 })).toThrow(/too small/);
	});
});

describe('toTiledJSON', () => {
	it('declares ge_collide on the solid tiles and nothing else', () => {
		const map = generateTown({ seed: 21 });
		const json = toTiledJSON(map);
		const solid = collidableGids();

		expect(json.width).toBe(map.width);
		expect(json.layers.map((layer) => layer.name)).toEqual(['ground', 'buildings', 'objects']);

		const declared = json.tilesets[0].tiles;
		expect(declared.length).toBeGreaterThan(0);
		for (const tile of declared) {
			// Tiled ids are 0-based, gids are 1-based.
			expect(solid.has(tile.id + 1)).toBe(true);
			expect(tile.properties).toEqual([{ name: 'ge_collide', type: 'bool', value: true }]);
		}

		// Anything walkable must stay undeclared, or grid-engine walls the floor.
		const declaredGids = new Set(declared.map((tile) => tile.id + 1));
		for (const layer of json.layers) {
			for (const gid of layer.data) {
				if (gid !== 0 && !solid.has(gid)) expect(declaredGids.has(gid)).toBe(false);
			}
		}
	});
});
