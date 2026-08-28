// Lifts the collision flags out of an authored Tiled map's tileset.
//
//   node tools/extract-collision.mjs
//
// The tileset knows which of its 1260 tiles are solid; cloud_city.json carries
// that table. Reading it beats maintaining a hand-written list of "gids I think
// are walls", which is what produced a town fenced in sand and buildings with
// walkable roofs.
import { readFile, writeFile } from 'node:fs/promises';

const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
	args.set(process.argv[i].replace(/^--/, ''), process.argv[i + 1]);
}

const mapPath = args.get('map') ?? 'public/game/cloud_city.json';
const out = args.get('out') ?? 'src/app/phaser/world/collision.json';

const map = JSON.parse(await readFile(mapPath, 'utf8'));
const tileset = map.tilesets[0];

const solid = [];
for (const tile of tileset.tiles ?? []) {
	const collides = (tile.properties ?? []).some(
		(property) => property.name === 'ge_collide' && property.value === true,
	);
	// Tiled ids are 0-based; a gid is the id plus the tileset's firstgid.
	if (collides) solid.push(tile.id + tileset.firstgid);
}
solid.sort((a, b) => a - b);

await writeFile(
	out,
	`${JSON.stringify({ source: `${mapPath} tileset "${tileset.name}"`, solid }, null, '\t')}\n`,
);
console.log(`${solid.length} solid gids -> ${out}`);
