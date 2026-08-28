import collision from './collision.json';

// Terrain tiles, and the collision table.
//
// Everything structural -- a building, the sand pit, the fountain plaza -- is a
// prefab lifted out of the authored map instead of a gid written down here.
// Hand-picked gids are what produced buildings stamped from their own roof
// course and a town fenced in sand pits, so what is left in this file is only
// the ground the prefabs sit on.

export const TILESET_COLUMNS = 45;

/**
 * The town floor: paved brick, as in the authored map. Index 0 is the common
 * one and the rest speckle it.
 */
export const FLOOR = [368, 413, 369, 414] as const;
export const FLOOR_PRIMARY = FLOOR[0];

/**
 * The sandy rim that bounds the town, as a nine-slice. cloud_city.json is a
 * plateau: brick floor, this sand around its edge, and open sky past that. The
 * tiles are solid, so the rim is also what keeps the player on the map.
 */
export const RIM = {
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

/** Small props with no interaction, stamped top row first. */
export const DECOR = {
	/** Grey headstone. The grave. */
	headstone: [[1052], [1097]],
	/** Three tile street lamp, top to base. */
	lamp: [[877], [922], [967]],
} as const;

/** Loose scenery: cacti. */
export const SCATTER = [1066, 1111, 1109] as const;

/**
 * Every solid tile in the tileset, straight from the authored map's own tile
 * properties via `node tools/extract-collision.mjs`.
 *
 * This is the table the artist filled in, not a guess about which gids look
 * like walls: it knows a building's roof is solid and its doorway is not.
 */
const SOLID = new Set<number>(collision.solid);

export function collidableGids(): Set<number> {
	return new Set(SOLID);
}

export function isSolid(gid: number): boolean {
	return SOLID.has(gid);
}

// Kept for the tilemap emitter, which needs the sheet's width to place a gid.
export const SHEET_COLUMNS = TILESET_COLUMNS;
