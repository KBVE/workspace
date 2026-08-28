// Renders a tileset as a labelled contact sheet: every tile with its gid on it.
//
// This exists because picking a tile was archaeology. The building origin was
// wrong twice, and the first landmarks were marked with paving edge pieces,
// because the only way to know what gid 442 looked like was to put it in the
// game and squint. Run this, open the png, read the number off the tile.
//
//   node tools/atlas.mjs [--tileset path] [--out path] [--scale n]
//                        [--rows a-b] [--cols a-b]
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import sharp from 'sharp';

const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
	args.set(process.argv[i].replace(/^--/, ''), process.argv[i + 1]);
}

const TILE = Number(args.get('tile') ?? 16);
const COLUMNS = Number(args.get('columns') ?? 45);
const SCALE = Number(args.get('scale') ?? 4);
const tileset = args.get('tileset') ?? 'public/game/desert_tileset_1.png';
const out = args.get('out') ?? 'e2e/.artifacts/atlas.png';

const range = (value, fallback) => {
	if (!value) return fallback;
	const [from, to] = value.split('-').map(Number);
	return [from, to ?? from + 1];
};

const image = sharp(tileset);
const { width, height } = await image.metadata();
const [rowFrom, rowTo] = range(args.get('rows'), [0, Math.floor(height / TILE)]);
const [colFrom, colTo] = range(args.get('cols'), [0, Math.floor(width / TILE)]);

const cols = colTo - colFrom;
const rows = rowTo - rowFrom;
const cell = TILE * SCALE;

const region = await image
	.extract({
		left: colFrom * TILE,
		top: rowFrom * TILE,
		width: cols * TILE,
		height: rows * TILE,
	})
	.resize(cols * cell, rows * cell, { kernel: 'nearest' })
	.png()
	.toBuffer();

// Grid and gid labels as one SVG overlay: sharp renders it, so no font or
// canvas dependency of our own.
const parts = [];
for (let i = 0; i <= cols; i++) {
	parts.push(`<line x1="${i * cell}" y1="0" x2="${i * cell}" y2="${rows * cell}" stroke="#ff0000" stroke-opacity="0.35"/>`);
}
for (let j = 0; j <= rows; j++) {
	parts.push(`<line x1="0" y1="${j * cell}" x2="${cols * cell}" y2="${j * cell}" stroke="#ff0000" stroke-opacity="0.35"/>`);
}
for (let j = 0; j < rows; j++) {
	for (let i = 0; i < cols; i++) {
		const gid = (rowFrom + j) * COLUMNS + (colFrom + i) + 1;
		parts.push(
			`<text x="${i * cell + 2}" y="${j * cell + 11}" font-family="monospace" font-size="10" fill="#ffff00" stroke="#000000" stroke-width="0.6">${gid}</text>`,
		);
	}
}
const overlay = Buffer.from(
	`<svg xmlns="http://www.w3.org/2000/svg" width="${cols * cell}" height="${rows * cell}">${parts.join('')}</svg>`,
);

await mkdir(dirname(out), { recursive: true });
const png = await sharp({
	create: {
		width: cols * cell,
		height: rows * cell,
		channels: 4,
		background: { r: 24, g: 24, b: 28, alpha: 1 },
	},
})
	.composite([{ input: region }, { input: overlay }])
	.png()
	.toBuffer();
await writeFile(out, png);

console.log(`atlas: rows ${rowFrom}-${rowTo}, cols ${colFrom}-${colTo} -> ${out}`);
