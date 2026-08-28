import {
	BUILDING,
	DECOR,
	PAVING,
	PAVING_PRIMARY,
	SAND,
	SCATTER,
	TILESET_COLUMNS,
	WALL,
	collidableGids,
} from './palette';

// Generates the town TownScene walks around in.
//
// The first version scattered buildings at random on open ground, which looked
// exactly like what it was: four boxes dropped in a desert, doors facing
// nothing. A town is a street plan, so this lays streets first and hangs
// everything off them -- buildings stand in the block above a street with their
// doorway opening onto it, lamps line the kerb, landmarks sit at junctions.
//
// Everything is a pure function of the seed. That is what makes it testable
// without a canvas, and it means a town someone complains about can be
// reproduced from its `?seed=`.

export type Position = { x: number; y: number };

export type PointOfInterest = 'fishingPit' | 'sign' | 'tombstone' | 'building';

export type TownMap = {
	width: number;
	height: number;
	/** Bottom-to-top draw order, matching the authored map's layer names. */
	layers: { name: string; data: number[] }[];
	/** The tile the player stands on to use each landmark. */
	landmarks: Record<PointOfInterest, Position>;
	playerSpawn: Position;
	npcSpawns: Position[];
	/** Street tiles, for tests and for placing anything that wants a kerb. */
	streets: Position[];
};

export type TownOptions = {
	seed: number;
	width?: number;
	height?: number;
	buildings?: number;
	scatter?: number;
	npcs?: number;
};

/** Rows between one street and the next. A block is this tall, minus the street. */
const BLOCK_HEIGHT = 7;
/** Columns between cross streets. */
const BLOCK_WIDTH = 11;

/**
 * mulberry32. Small, seedable, and good enough to choose which lots get built
 * on -- the point is reproducibility, not statistical quality.
 */
function rng(seed: number): () => number {
	let state = seed >>> 0;
	return () => {
		state = (state + 0x6d2b79f5) >>> 0;
		let t = state;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

const index = (x: number, y: number, width: number) => y * width + x;

/**
 * Wall gid for a position on the enclosure. The top course carries the trim, so
 * the wall reads as facing out of the town rather than into it.
 */
function wallAt(y: number): number {
	return y === 0 ? WALL.cap : WALL.body;
}

export function generateTown(options: TownOptions): TownMap {
	const width = options.width ?? 40;
	const height = options.height ?? 30;
	const scatterCount = options.scatter ?? 18;
	const npcCount = options.npcs ?? 2;

	if (width < 16 || height < 16) {
		throw new Error(`A ${width}x${height} town is too small to lay streets in.`);
	}

	const random = rng(options.seed);
	const pick = <T>(values: readonly T[]): T => values[Math.floor(random() * values.length)];

	const ground = new Array<number>(width * height).fill(0);
	const buildings = new Array<number>(width * height).fill(0);
	const objects = new Array<number>(width * height).fill(0);

	// The street plan. Horizontal streets are what buildings face; the vertical
	// ones connect them, so no block is a dead end.
	const streetRows: number[] = [];
	for (let y = BLOCK_HEIGHT; y < height - 2; y += BLOCK_HEIGHT) streetRows.push(y);
	const streetColumns: number[] = [];
	for (let x = BLOCK_WIDTH; x < width - 2; x += BLOCK_WIDTH) streetColumns.push(x);

	if (streetRows.length === 0 || streetColumns.length === 0) {
		throw new Error(`A ${width}x${height} town has no room for a street grid.`);
	}

	const onStreet = (x: number, y: number) =>
		streetRows.includes(y) || streetColumns.includes(x);

	// Ground goes down after the streets are known, because what a tile is made
	// of depends on whether a street runs over it: open desert is sand, and the
	// streets are paved, which is what makes them visible as streets.
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			const onEdge = x === 0 || y === 0 || x === width - 1 || y === height - 1;
			if (onEdge) {
				ground[index(x, y, width)] = wallAt(y);
			} else if (onStreet(x, y)) {
				ground[index(x, y, width)] = random() < 0.12 ? pick(PAVING) : PAVING_PRIMARY;
			} else {
				ground[index(x, y, width)] = SAND[y % 2][x % 2];
			}
		}
	}

	const streets: Position[] = [];
	for (let y = 1; y < height - 1; y++) {
		for (let x = 1; x < width - 1; x++) {
			if (onStreet(x, y)) streets.push({ x, y });
		}
	}

	const solid = collidableGids();
	const occupied = (x: number, y: number) =>
		buildings[index(x, y, width)] !== 0 || objects[index(x, y, width)] !== 0;
	const free = (x: number, y: number) =>
		x > 0 && y > 0 && x < width - 1 && y < height - 1 && !occupied(x, y);

	/**
	 * Every lot a building could stand in: footprint sitting on a block, with
	 * its doorway one tile above a street, so the door opens onto the street
	 * rather than into whatever the random number generator left there.
	 */
	const lots: Position[] = [];
	for (const street of streetRows) {
		const top = street - BUILDING.height;
		if (top < 2) continue;
		for (let x = 2; x + BUILDING.width < width - 2; x += BUILDING.width + 1) {
			// Skip a lot that would sit across a cross street, or the junction
			// stops being a junction.
			let clearOfCrossStreets = true;
			for (let dx = 0; dx < BUILDING.width; dx++) {
				if (streetColumns.includes(x + dx)) clearOfCrossStreets = false;
			}
			if (clearOfCrossStreets) lots.push({ x, y: top });
		}
	}

	if (lots.length === 0) {
		throw new Error(`Seed ${options.seed} produced a town with nowhere to build.`);
	}

	// Build on a deterministic subset, so a town has gaps between its buildings
	// rather than a solid terrace along every street.
	const wanted = Math.min(options.buildings ?? Math.ceil(lots.length * 0.55), lots.length);
	const shuffled = [...lots];
	for (let i = shuffled.length - 1; i > 0; i--) {
		const j = Math.floor(random() * (i + 1));
		[shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
	}

	const doors: Position[] = [];
	for (const lot of shuffled.slice(0, wanted)) {
		for (let row = 0; row < BUILDING.height; row++) {
			for (let column = 0; column < BUILDING.width; column++) {
				buildings[index(lot.x + column, lot.y + row, width)] =
					BUILDING.origin + row * TILESET_COLUMNS + column;
			}
		}
		doors.push({ x: lot.x + BUILDING.door.x, y: lot.y + BUILDING.door.y });
	}

	/** Stamps a decor block on the object layer, top row first. */
	const stamp = (art: readonly (readonly number[])[], x: number, y: number) => {
		art.forEach((row, dy) => {
			row.forEach((gid, dx) => {
				objects[index(x + dx, y + dy, width)] = gid;
			});
		});
	};

	const fits = (art: readonly (readonly number[])[], x: number, y: number) => {
		for (let dy = 0; dy < art.length; dy++) {
			for (let dx = 0; dx < art[dy].length; dx++) {
				if (!free(x + dx, y + dy)) return false;
				if (onStreet(x + dx, y + dy)) return false;
			}
		}
		// The tile the player stands on to use it has to stay walkable, and be
		// somewhere they can actually get to: the street below.
		const standY = y + art.length;
		for (let dx = 0; dx < art[0].length; dx++) {
			if (!free(x + dx, standY)) return false;
		}
		return true;
	};

	/** Places a landmark against a street, returning the tile to stand on. */
	const placeLandmark = (art: readonly (readonly number[])[]): Position | null => {
		for (let attempt = 0; attempt < 800; attempt++) {
			const street = streetRows[Math.floor(random() * streetRows.length)];
			const y = street - art.length;
			const x = 2 + Math.floor(random() * (width - 4));
			if (y < 2) continue;
			if (!fits(art, x, y)) continue;
			stamp(art, x, y);
			return { x, y: street };
		}
		return null;
	};

	const landmarks = {} as Record<PointOfInterest, Position>;

	const pit = placeLandmark(DECOR.sandPit);
	const board = placeLandmark(DECOR.noticeBoard);
	const grave = placeLandmark(DECOR.headstone);
	if (!pit || !board || !grave) {
		throw new Error(`Seed ${options.seed} left nowhere to put its landmarks.`);
	}
	landmarks.fishingPit = pit;
	landmarks.sign = board;
	landmarks.tombstone = grave;
	landmarks.building = doors[0];

	// A fountain where two streets cross, purely so the middle of town looks
	// like the middle of town.
	const junctionX = streetColumns[Math.floor(streetColumns.length / 2)];
	const junctionY = streetRows[Math.floor(streetRows.length / 2)];
	if (free(junctionX + 1, junctionY + 1) && free(junctionX + 2, junctionY + 2)) {
		stamp(DECOR.fountain, junctionX + 1, junctionY + 1);
	}

	// Lamps on the kerb: the tile above a street, in the gaps between buildings.
	for (const street of streetRows) {
		for (let x = 3; x < width - 3; x += 6) {
			const y = street - DECOR.lamp.length;
			if (y > 1 && fits(DECOR.lamp, x, y)) stamp(DECOR.lamp, x, y);
		}
	}

	const reserved = new Set(
		Object.values(landmarks).map((position) => index(position.x, position.y, width)),
	);

	/** An open tile off the street, for spawns and scenery. */
	const freeOffStreet = (): Position | null => {
		for (let attempt = 0; attempt < 500; attempt++) {
			const x = 2 + Math.floor(random() * (width - 4));
			const y = 2 + Math.floor(random() * (height - 4));
			if (free(x, y) && !onStreet(x, y) && !reserved.has(index(x, y, width))) return { x, y };
		}
		return null;
	};

	// The player and the townsfolk start on a street, which is the one place
	// they are certain to be able to walk out of.
	const streetSpawn = (): Position => {
		for (let attempt = 0; attempt < 500; attempt++) {
			const spot = streets[Math.floor(random() * streets.length)];
			if (free(spot.x, spot.y) && !reserved.has(index(spot.x, spot.y, width))) return spot;
		}
		return streets[0];
	};

	const playerSpawn = streetSpawn();
	const npcSpawns: Position[] = [];
	for (let placed = 0; placed < npcCount; placed++) npcSpawns.push(streetSpawn());

	const draft: TownMap = {
		width,
		height,
		layers: [
			{ name: 'ground', data: ground },
			{ name: 'buildings', data: buildings },
			{ name: 'objects', data: objects },
		],
		landmarks,
		playerSpawn,
		npcSpawns,
		streets,
	};

	// Scenery last, and one at a time. A cactus in the wrong tile can seal a
	// landmark off, and placing them at random makes that a matter of luck
	// rather than of seed -- so each is kept only if the town is still
	// connected with it there.
	for (let placed = 0; placed < scatterCount; placed++) {
		const spot = freeOffStreet();
		if (!spot) break;
		const at = index(spot.x, spot.y, width);
		if (spot.x === playerSpawn.x && spot.y === playerSpawn.y) continue;
		if (npcSpawns.some((npc) => npc.x === spot.x && npc.y === spot.y)) continue;

		objects[at] = pick(SCATTER);
		if (unreachableLandmarks(draft).length > 0) objects[at] = 0;
	}

	const unreachable = unreachableLandmarks(draft);
	if (unreachable.length > 0) {
		throw new Error(
			`Seed ${options.seed} walled off ${unreachable.join(', ')} from the player spawn.`,
		);
	}

	void solid;
	return draft;
}

/**
 * Flood fill from the player spawn, returning the landmarks it never reaches.
 * This is the check that a town is playable at all rather than merely well
 * formed.
 */
export function unreachableLandmarks(map: TownMap): PointOfInterest[] {
	const solid = collidableGids();
	const blocked = (x: number, y: number) => {
		if (x < 0 || y < 0 || x >= map.width || y >= map.height) return true;
		const at = index(x, y, map.width);
		return map.layers.some((layer) => solid.has(layer.data[at]));
	};

	const seen = new Set<number>();
	const queue: Position[] = [map.playerSpawn];
	seen.add(index(map.playerSpawn.x, map.playerSpawn.y, map.width));

	while (queue.length > 0) {
		const { x, y } = queue.shift()!;
		for (const [dx, dy] of [
			[1, 0],
			[-1, 0],
			[0, 1],
			[0, -1],
		]) {
			const nx = x + dx;
			const ny = y + dy;
			const at = index(nx, ny, map.width);
			if (seen.has(at) || blocked(nx, ny)) continue;
			seen.add(at);
			queue.push({ x: nx, y: ny });
		}
	}

	return (Object.keys(map.landmarks) as PointOfInterest[]).filter((name) => {
		const spot = map.landmarks[name];
		// A doorway is solid on every side but its approach, so reaching the
		// tile below it counts as reaching the building.
		const target =
			name === 'building' ? index(spot.x, spot.y + 1, map.width) : index(spot.x, spot.y, map.width);
		return !seen.has(target);
	});
}

/**
 * Wraps a generated town in the Tiled JSON shape Phaser's tilemap loader
 * expects, with `ge_collide` declared on exactly the tiles grid-engine should
 * treat as walls.
 */
export function toTiledJSON(map: TownMap, tilesetName = 'Cloud City') {
	const solid = collidableGids();
	const used = new Set<number>();
	for (const layer of map.layers) {
		for (const gid of layer.data) if (gid !== 0 && solid.has(gid)) used.add(gid);
	}

	return {
		compressionlevel: -1,
		infinite: false,
		orientation: 'orthogonal' as const,
		renderorder: 'right-down' as const,
		type: 'map' as const,
		version: '1.10',
		tiledversion: '1.10.2',
		width: map.width,
		height: map.height,
		tilewidth: 16,
		tileheight: 16,
		nextlayerid: map.layers.length + 1,
		nextobjectid: 1,
		layers: map.layers.map((layer, id) => ({
			id: id + 1,
			name: layer.name,
			type: 'tilelayer' as const,
			data: layer.data,
			width: map.width,
			height: map.height,
			opacity: 1,
			visible: true,
			x: 0,
			y: 0,
		})),
		tilesets: [
			{
				firstgid: 1,
				name: tilesetName,
				image: 'desert_tileset_1.png',
				imagewidth: 720,
				imageheight: 448,
				tilewidth: 16,
				tileheight: 16,
				columns: TILESET_COLUMNS,
				tilecount: 1260,
				margin: 0,
				spacing: 0,
				tiles: [...used]
					.sort((a, b) => a - b)
					.map((gid) => ({
						id: gid - 1,
						properties: [{ name: 'ge_collide', type: 'bool' as const, value: true }],
					})),
			},
		],
	};
}
