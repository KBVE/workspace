import buildingJson from './prefabs/building.json';
import noticeBoardJson from './prefabs/notice-board.json';
import plazaJson from './prefabs/plaza.json';
import sandPitJson from './prefabs/sand-pit.json';

// Prefabs: rectangles of the authored map, lifted whole.
//
// Written by `node tools/extract-prefab.mjs`, never by hand. A building is nine
// tiles wide with a tiled roof, arched windows, and a door -- reproducing that
// from gid arithmetic is how the first version ended up stamping the roof
// course on its own and calling it a house.
//
// Adding a piece is an extract command and a line in PREFABS. No generator
// change, no new tile constants.

export type PrefabAnchors = {
	/** Walkable doorway, in prefab coordinates. */
	door?: { x: number; y: number };
	/** Where the player stands to use it, relative to the prefab's top left. */
	stand?: { x: number; y: number };
};

export type Prefab = {
	name: string;
	tags: string[];
	width: number;
	height: number;
	/** Where it came from, so the next person can re-extract it. */
	source?: string;
	anchors: PrefabAnchors;
	/** Layer name to rows of gids, top row first. 0 means "nothing here". */
	layers: Record<string, number[][]>;
};

export const PREFABS = {
	building: buildingJson as Prefab,
	sandPit: sandPitJson as Prefab,
	plaza: plazaJson as Prefab,
	noticeBoard: noticeBoardJson as Prefab,
} satisfies Record<string, Prefab>;

export type PrefabId = keyof typeof PREFABS;

/**
 * Structural complaints about a prefab. Returns them rather than throwing, so a
 * test can report every broken piece in one run instead of the first.
 */
export function prefabProblems(prefab: Prefab): string[] {
	const problems: string[] = [];

	if (prefab.width <= 0 || prefab.height <= 0) {
		problems.push(`${prefab.name}: ${prefab.width}x${prefab.height} is not a rectangle`);
	}

	const layers = Object.entries(prefab.layers);
	if (layers.length === 0) problems.push(`${prefab.name}: has no layers`);

	for (const [name, rows] of layers) {
		if (rows.length !== prefab.height) {
			problems.push(`${prefab.name}.${name}: ${rows.length} rows, expected ${prefab.height}`);
		}
		rows.forEach((row, y) => {
			if (row.length !== prefab.width) {
				problems.push(`${prefab.name}.${name}: row ${y} is ${row.length} wide, expected ${prefab.width}`);
			}
			row.forEach((gid, x) => {
				if (!Number.isInteger(gid) || gid < 0) {
					problems.push(`${prefab.name}.${name}: ${gid} at ${x},${y} is not a gid`);
				}
			});
		});
	}

	for (const [name, anchor] of Object.entries(prefab.anchors)) {
		if (!anchor) continue;
		const inside =
			anchor.x >= 0 && anchor.y >= 0 && anchor.x < prefab.width && anchor.y <= prefab.height;
		// `stand` is allowed one row past the bottom: that is the tile in front
		// of the piece, which is where you stand to use something you cannot
		// walk into.
		if (!inside) problems.push(`${prefab.name}: anchor ${name} at ${anchor.x},${anchor.y} is outside it`);
	}

	return problems;
}

/** The gid at a position in a prefab layer, or 0 where the layer is empty. */
export function gidAt(prefab: Prefab, layer: string, x: number, y: number): number {
	return prefab.layers[layer]?.[y]?.[x] ?? 0;
}
