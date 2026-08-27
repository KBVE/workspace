// Tile ids for the desert tileset, read out of the hand-authored cloud_city.json
// rather than guessed. Every number here was in use in that map, so the
// generator composes pieces an artist already placed together.
//
// The tileset is 45 columns wide, which is why a vertical neighbour is +45 and
// the nine-slice below reads as three consecutive rows.
//
// Ids are Tiled *gids*: 1-based, because 0 means "no tile in this layer".

export const TILESET_COLUMNS = 45;

/**
 * The wall enclosure, as a nine-slice. cloud_city.json fences its whole map
 * with exactly this set, so a generated map that reuses it is bounded the same
 * way the authored one is.
 */
export const WALL = {
	topLeft: 47,
	top: 48,
	topRight: 49,
	left: 92,
	middle: 93,
	right: 94,
	bottomLeft: 137,
	bottom: 138,
	bottomRight: 139,
} as const;

/**
 * Walkable sand. 368 covers most of the authored map's floor; the rest are the
 * variants it speckles in, kept in frequency order so the generator can weight
 * toward the common one and still break up the flatness.
 */
export const SAND = [368, 413, 414, 371, 372, 363, 453, 409] as const;
export const SAND_PRIMARY = SAND[0];

/**
 * A building is a 3-wide, 4-tall stamp whose bottom middle tile is a doorway.
 * The door is the only part of it that is not solid -- that is what makes a
 * building enterable rather than scenery.
 */
export const BUILDING = {
	width: 3,
	height: 4,
	/** Top-left gid; each row below it is +TILESET_COLUMNS. */
	origin: 442,
	/** Offset of the walkable doorway within the stamp. */
	door: { x: 1, y: 3 },
} as const;

/** Solid scenery scattered on the object layer: rocks, crates, cacti. */
export const PROPS = [1102, 1103, 1066, 1067, 1111, 1112] as const;

/** Marks a point of interest on the ground. Walkable -- the player stands on it. */
export const MARKERS = {
	/** The sand pit that starts the fishing minigame. */
	fishingPit: 453,
	/** The credits sign. */
	sign: 409,
	/** The tombstone. */
	tombstone: 407,
} as const;

/**
 * Every gid the generator can place that the player cannot walk through.
 * grid-engine reads collision from a per-tile `ge_collide` property, so this
 * set is what the emitted tilemap declares that property on.
 */
export function collidableGids(): Set<number> {
	const solid = new Set<number>(Object.values(WALL));
	for (const prop of PROPS) solid.add(prop);

	for (let row = 0; row < BUILDING.height; row++) {
		for (let column = 0; column < BUILDING.width; column++) {
			// The doorway is deliberately left out: it is the way in.
			if (column === BUILDING.door.x && row === BUILDING.door.y) continue;
			solid.add(BUILDING.origin + row * TILESET_COLUMNS + column);
		}
	}

	return solid;
}
