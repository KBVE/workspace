import {
	BUILDING,
	MARKERS,
	PROPS,
	SAND,
	SAND_PRIMARY,
	TILESET_COLUMNS,
	WALL,
	collidableGids,
} from './palette';

// Generates the town TownScene walks around in.
//
// It replaces cloud_city.json, a 20x20 map with every landmark at a fixed
// coordinate -- which is why the old scene asked "is the player between x=2 and
// x=5" to know it was standing at the well. Landmarks come out of the generator
// here, so the interaction code reads a position instead of a magic rectangle
// and a bigger map does not mean rewriting those checks.
//
// Everything is a pure function of the seed. That is what makes it testable
// without a canvas, and it means a seed that produces a broken town can be
// replayed exactly.

export type Position = { x: number; y: number };

export type PointOfInterest =
	| 'fishingPit'
	| 'sign'
	| 'tombstone'
	| 'building';

export type TownMap = {
	width: number;
	height: number;
	/** Bottom-to-top draw order, matching the authored map's layer names. */
	layers: { name: string; data: number[] }[];
	/** Where each landmark sits. The scene turns these into interactions. */
	landmarks: Record<PointOfInterest, Position>;
	playerSpawn: Position;
	npcSpawns: Position[];
};

export type TownOptions = {
	seed: number;
	width?: number;
	height?: number;
	buildings?: number;
	props?: number;
	npcs?: number;
};

/**
 * mulberry32. Small, seedable, and good enough to scatter rocks -- the point is
 * reproducibility, not statistical quality.
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

/** Wall gid for a position on the enclosure, picked by which edge it is on. */
function wallAt(x: number, y: number, width: number, height: number): number {
	const left = x === 0;
	const right = x === width - 1;
	const top = y === 0;
	const bottom = y === height - 1;

	if (top && left) return WALL.topLeft;
	if (top && right) return WALL.topRight;
	if (bottom && left) return WALL.bottomLeft;
	if (bottom && right) return WALL.bottomRight;
	if (top) return WALL.top;
	if (bottom) return WALL.bottom;
	if (left) return WALL.left;
	return WALL.right;
}

/**
 * Builds the town. Landmarks and spawns are placed on open floor, then the
 * whole thing is checked for reachability -- a town with a walled-off sand pit
 * is a town the player cannot finish.
 */
export function generateTown(options: TownOptions): TownMap {
	const width = options.width ?? 40;
	const height = options.height ?? 30;
	const buildingCount = options.buildings ?? 4;
	const propCount = options.props ?? 24;
	const npcCount = options.npcs ?? 2;

	if (width < 12 || height < 12) {
		throw new Error(`A ${width}x${height} town is too small to place its landmarks.`);
	}

	const random = rng(options.seed);
	const pick = <T>(values: readonly T[]): T => values[Math.floor(random() * values.length)];

	const ground = new Array<number>(width * height).fill(0);
	const buildings = new Array<number>(width * height).fill(0);
	const objects = new Array<number>(width * height).fill(0);

	// Floor first, walls over the edge of it.
	for (let y = 0; y < height; y++) {
		for (let x = 0; x < width; x++) {
			const onEdge = x === 0 || y === 0 || x === width - 1 || y === height - 1;
			// Most of the floor is the primary sand; the variants only speckle,
			// the way the authored map uses them.
			ground[index(x, y, width)] = onEdge
				? wallAt(x, y, width, height)
				: random() < 0.15
					? pick(SAND)
					: SAND_PRIMARY;
		}
	}

	const solid = collidableGids();
	const blocked = (x: number, y: number) =>
		solid.has(ground[index(x, y, width)]) ||
		solid.has(buildings[index(x, y, width)]) ||
		solid.has(objects[index(x, y, width)]);

	const occupied = (x: number, y: number) =>
		buildings[index(x, y, width)] !== 0 || objects[index(x, y, width)] !== 0;

	/** Interior floor, one tile in from the wall so nothing hugs the edge. */
	const freeInteriorTile = (margin = 2): Position | null => {
		for (let attempt = 0; attempt < 500; attempt++) {
			const x = margin + Math.floor(random() * (width - margin * 2));
			const y = margin + Math.floor(random() * (height - margin * 2));
			if (!blocked(x, y) && !occupied(x, y)) return { x, y };
		}
		return null;
	};

	// Buildings. Each is a solid stamp with a walkable doorway at its foot; the
	// tile below the door is kept clear so the player can stand there.
	const doors: Position[] = [];
	// A door is useless if something later covers the tile you walk in from, and
	// a building placed there is allowed by an occupancy test alone -- that tile
	// is empty, which is the whole point of it.
	const reservedApproaches = new Set<number>();
	for (let placed = 0; placed < buildingCount; placed++) {
		let anchor: Position | null = null;

		for (let attempt = 0; attempt < 200 && !anchor; attempt++) {
			const x = 2 + Math.floor(random() * (width - BUILDING.width - 4));
			const y = 2 + Math.floor(random() * (height - BUILDING.height - 5));

			// One tile of clearance all round, plus the approach below the door,
			// so two buildings cannot seal a corridor between them.
			let clear = true;
			for (let dy = -1; dy <= BUILDING.height + 1 && clear; dy++) {
				for (let dx = -1; dx <= BUILDING.width && clear; dx++) {
					const cx = x + dx;
					const cy = y + dy;
					if (cx < 1 || cy < 1 || cx >= width - 1 || cy >= height - 1) clear = false;
					else if (occupied(cx, cy)) clear = false;
					else if (reservedApproaches.has(index(cx, cy, width))) clear = false;
				}
			}
			if (clear) anchor = { x, y };
		}

		if (!anchor) continue;

		for (let row = 0; row < BUILDING.height; row++) {
			for (let column = 0; column < BUILDING.width; column++) {
				buildings[index(anchor.x + column, anchor.y + row, width)] =
					BUILDING.origin + row * TILESET_COLUMNS + column;
			}
		}
		const door = { x: anchor.x + BUILDING.door.x, y: anchor.y + BUILDING.door.y };
		doors.push(door);
		reservedApproaches.add(index(door.x, door.y + 1, width));
	}

	if (doors.length === 0) {
		throw new Error(`Seed ${options.seed} produced a town with no buildings.`);
	}

	// Landmarks. The building landmark is the doorway of the first building --
	// the tile the player stands on to go in.
	const landmarks = {
		building: doors[0],
	} as Record<PointOfInterest, Position>;

	for (const marker of ['fishingPit', 'sign', 'tombstone'] as const) {
		const spot = freeInteriorTile(3);
		if (!spot) throw new Error(`Seed ${options.seed} left nowhere to put the ${marker}.`);
		ground[index(spot.x, spot.y, width)] = MARKERS[marker];
		landmarks[marker] = spot;
	}

	const reserved = new Set(
		Object.values(landmarks).map((position) => index(position.x, position.y, width)),
	);

	const playerSpawn = freeInteriorTile(2);
	if (!playerSpawn) throw new Error(`Seed ${options.seed} left nowhere to put the player.`);

	const npcSpawns: Position[] = [];
	for (let placed = 0; placed < npcCount; placed++) {
		const spot = freeInteriorTile(2);
		if (spot) npcSpawns.push(spot);
	}

	// Props go last and are checked one at a time. A rock dropped in a doorway
	// or across the only path to the sand pit produces a town that looks fine
	// and cannot be finished, and placing them at random means that is a matter
	// of luck rather than of seed -- so each one is placed only if the town is
	// still fully connected with it there.
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
	};

	for (let placed = 0; placed < propCount; placed++) {
		const spot = freeInteriorTile(2);
		if (!spot) break;
		const at = index(spot.x, spot.y, width);
		if (reserved.has(at)) continue;
		if (reservedApproaches.has(at)) continue;
		if (spot.x === playerSpawn.x && spot.y === playerSpawn.y) continue;
		if (npcSpawns.some((npc) => npc.x === spot.x && npc.y === spot.y)) continue;

		objects[at] = pick(PROPS);
		if (unreachableLandmarks(draft).length > 0) objects[at] = 0;
	}

	const map = draft;

	const unreachable = unreachableLandmarks(map);
	if (unreachable.length > 0) {
		throw new Error(
			`Seed ${options.seed} walled off ${unreachable.join(', ')} from the player spawn.`,
		);
	}

	return map;
}

/**
 * Flood fill from the player spawn, returning the landmarks it never reaches.
 * Props are placed at random, so this is the check that a town is playable at
 * all rather than merely well formed.
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
				// Only the solid tiles need declaring: grid-engine reads a missing
				// property as "not blocking".
				tiles: [...used].sort((a, b) => a - b).map((gid) => ({
					id: gid - 1,
					properties: [{ name: 'ge_collide', type: 'bool' as const, value: true }],
				})),
			},
		],
	};
}
