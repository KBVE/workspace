// Renders a Tiled map to a PNG, so a map can be looked at without a browser.
//
//   node tools/render-map.mjs --map tools/source/cloud_city.json --out map.png
//
// Blits tiles into one raw RGBA buffer rather than compositing a few thousand
// sharp operations, which is the difference between instant and a coffee.
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import sharp from 'sharp';

const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
	args.set(process.argv[i].replace(/^--/, ''), process.argv[i + 1]);
}

const mapPath = args.get('map') ?? 'tools/source/cloud_city.json';
const tilesetPath = args.get('tileset') ?? 'public/game/desert_tileset_1.png';
const out = args.get('out') ?? 'e2e/.artifacts/map.png';
const scale = Number(args.get('scale') ?? 3);
const only = args.get('layers')?.split(',');

const raw = JSON.parse(await readFile(args.get('prefab') ?? mapPath, 'utf8'));

// A prefab is a map with the boilerplate stripped out, so give it back the two
// fields the renderer needs and treat it as one.
const map = args.get('prefab')
	? {
			width: raw.width,
			height: raw.height,
			tilewidth: 16,
			layers: Object.entries(raw.layers).map(([name, rows]) => ({
				name,
				type: 'tilelayer',
				width: raw.width,
				height: raw.height,
				data: rows.flat(),
			})),
		}
	: raw;
const tile = map.tilewidth;
const sheet = sharp(tilesetPath).ensureAlpha();
const { width: sheetWidth } = await sheet.metadata();
const sheetColumns = Math.floor(sheetWidth / tile);
const { data: sheetPixels, info } = await sheet.raw().toBuffer({ resolveWithObject: true });

const width = map.width * tile;
const height = map.height * tile;
const canvas = Buffer.alloc(width * height * 4, 0);

/** Alpha-over blit of one tile, source pixels straight out of the sheet. */
const blit = (gid, tx, ty) => {
	const id = gid - 1;
	const sx = (id % sheetColumns) * tile;
	const sy = Math.floor(id / sheetColumns) * tile;
	for (let y = 0; y < tile; y++) {
		for (let x = 0; x < tile; x++) {
			const s = ((sy + y) * info.width + (sx + x)) * 4;
			const alpha = sheetPixels[s + 3];
			if (alpha === 0) continue;
			const d = ((ty * tile + y) * width + (tx * tile + x)) * 4;
			if (alpha === 255) {
				sheetPixels.copy(canvas, d, s, s + 4);
			} else {
				const a = alpha / 255;
				for (let c = 0; c < 3; c++) {
					canvas[d + c] = Math.round(sheetPixels[s + c] * a + canvas[d + c] * (1 - a));
				}
				canvas[d + 3] = Math.max(canvas[d + 3], alpha);
			}
		}
	}
};

for (const layer of map.layers) {
	if (layer.type !== 'tilelayer') continue;
	if (only && !only.includes(layer.name)) continue;
	for (let y = 0; y < layer.height; y++) {
		for (let x = 0; x < layer.width; x++) {
			const gid = layer.data[y * layer.width + x];
			if (gid !== 0) blit(gid, x, y);
		}
	}
}

await mkdir(dirname(out), { recursive: true });
await sharp(canvas, { raw: { width, height, channels: 4 } })
	.resize(width * scale, height * scale, { kernel: 'nearest' })
	.png()
	.toFile(out);

console.log(`${mapPath} -> ${out} (${map.width}x${map.height} tiles)`);
