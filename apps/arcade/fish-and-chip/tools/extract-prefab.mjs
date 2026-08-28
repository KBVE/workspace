// Lifts a rectangle of an authored Tiled map into a prefab the generator can
// stamp.
//
//   node tools/extract-prefab.mjs --map public/game/cloud_city.json \
//     --rect 9,0,9,7 --name building --anchor door=4,6
//
// The point is to stop retyping art. Every tile mistake so far came from
// picking gids by hand: the buildings were stamped from 442, which is the roof
// course of a nine-wide structure, so they rendered as a blue slab.
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
	args.set(process.argv[i].replace(/^--/, ''), process.argv[i + 1]);
}

const mapPath = args.get('map') ?? 'public/game/cloud_city.json';
const name = args.get('name');
const rect = args.get('rect');
if (!name || !rect) {
	console.error('Usage: --name <id> --rect x,y,w,h [--anchor door=x,y] [--tags a,b] [--out dir]');
	process.exit(2);
}

const [x0, y0, w, h] = rect.split(',').map(Number);
const outDir = args.get('out') ?? 'src/app/phaser/world/prefabs';
const map = JSON.parse(await readFile(mapPath, 'utf8'));

const anchors = {};
for (const pair of (args.get('anchor') ?? '').split(';').filter(Boolean)) {
	const [key, value] = pair.split('=');
	const [ax, ay] = value.split(',').map(Number);
	anchors[key] = { x: ax, y: ay };
}

// Which layers to carry. A notice board extracted with its ground drags the
// sand it happened to stand on into every town that places it.
const wanted = args.get('layers')?.split(',');

const layers = {};
for (const layer of map.layers) {
	if (layer.type !== 'tilelayer') continue;
	if (wanted && !wanted.includes(layer.name)) continue;
	const rows = [];
	let used = false;
	for (let y = y0; y < y0 + h; y++) {
		const row = [];
		for (let x = x0; x < x0 + w; x++) {
			const gid = layer.data[y * map.width + x] ?? 0;
			if (gid !== 0) used = true;
			row.push(gid);
		}
		rows.push(row);
	}
	// Only carry layers this rectangle actually uses, so a prefab does not
	// haul three empty grids around.
	if (used) layers[layer.name] = rows;
}

const prefab = {
	name,
	tags: (args.get('tags') ?? '').split(',').filter(Boolean),
	width: w,
	height: h,
	source: `${mapPath} at ${x0},${y0}`,
	anchors,
	layers,
};

const out = join(outDir, `${name}.json`);
await mkdir(dirname(out), { recursive: true });
await writeFile(out, `${JSON.stringify(prefab, null, '\t')}\n`);
console.log(`${name}: ${w}x${h}, layers ${Object.keys(layers).join('+')} -> ${out}`);
