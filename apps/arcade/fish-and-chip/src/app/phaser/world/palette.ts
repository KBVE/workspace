// Tile ids for the desert tileset.
//
// Every id here was read off `moon run fish-and-chip:atlas` -- a labelled render
// of the sheet -- rather than guessed or inherited from the authored map. The
// guessing cost real mistakes: the buildings came out blue, the landmarks were
// drawn with paving edge pieces, and the town was fenced with a ring of sand
// pits, which is the art for the one thing the game is about.
//
// The tileset is 45 columns wide, so a vertical neighbour is +45 and a stamp's
// rows read as consecutive runs.
//
// Ids are Tiled *gids*: 1-based, because 0 means "no tile in this layer".

export const TILESET_COLUMNS = 45;

/**
 * Open desert. A 2x2 speckle pattern, laid by parity so it tiles seamlessly
 * rather than looking like scattered grit.
 */
export const SAND = [
	[227, 228],
	[272, 273],
] as const;

/**
 * Paved brick. What the streets are made of, and the only reason they are
 * visible: the first street plan paved the whole map in this and left the
 * streets as an idea that existed only in the code.
 */
export const PAVING = [368, 413, 369, 414] as const;
export const PAVING_PRIMARY = PAVING[0];

/**
 * The town wall: sandstone, with a gold trim along its top course.
 *
 * The border used to be 47-49/92-94/137-139, which is not a wall at all. It is
 * a sand pit -- the thing the fishing minigame is named after -- so every town
 * was ringed with dozens of them.
 */
export const WALL = {
	/** Top course, trim facing out. */
	cap: 684,
	/** Everything else. */
	body: 729,
} as const;

/**
 * A building is a 3-wide, 4-tall stamp whose bottom middle tile is a doorway.
 * Column 33, row 9 of the sheet: the sandstone block. The authored map's 442
 * lands on the blue block three columns to its right.
 */
export const BUILDING = {
	width: 3,
	height: 4,
	origin: 439,
	/** Offset of the walkable doorway within the stamp. */
	door: { x: 1, y: 3 },
} as const;

/**
 * Landmarks, built out of real objects. Each stamp is rows of gids, top row
 * first; the player stands on the tile below it.
 */
export const DECOR = {
	/**
	 * The sand pit, and the whole point of the town: standing at its edge is
	 * what starts the fishing minigame.
	 */
	sandPit: [
		[47, 48, 49],
		[92, 93, 94],
		[137, 138, 139],
	],
	/** Wooden notice board. The credits sign. */
	noticeBoard: [
		[872, 873],
		[917, 918],
	],
	/** Grey headstone. The grave. */
	headstone: [[1052], [1097]],
	/** Ornamental fountain, for the middle of a junction. */
	fountain: [
		[1106, 1107],
		[1151, 1152],
	],
	/** Three tile street lamp, top to base. */
	lamp: [[877], [922], [967]],
} as const;

/** Loose scenery with no meaning: cacti and a stray crate. */
export const SCATTER = [1066, 1111, 1109, 1057] as const;

/**
 * Every gid the generator can place that the player cannot walk through.
 * grid-engine reads collision from a per-tile `ge_collide` property, so this
 * set is what the emitted tilemap declares that property on.
 */
export function collidableGids(): Set<number> {
	const solid = new Set<number>([WALL.cap, WALL.body]);

	for (const stamp of Object.values(DECOR)) {
		for (const row of stamp) for (const gid of row) solid.add(gid);
	}
	for (const gid of SCATTER) solid.add(gid);

	for (let row = 0; row < BUILDING.height; row++) {
		for (let column = 0; column < BUILDING.width; column++) {
			// The doorway is deliberately left out: it is the way in.
			if (column === BUILDING.door.x && row === BUILDING.door.y) continue;
			solid.add(BUILDING.origin + row * TILESET_COLUMNS + column);
		}
	}

	return solid;
}
