// Renders a generated town straight to a PNG, no browser involved.
//
//   node tools/render-town.mjs --seed 7 --out e2e/.artifacts/town.png
//
// The loop before this was: change the generator, build, launch a browser,
// screenshot, squint. This is the same picture in about a second.
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import { createServer } from 'vite';

const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
	args.set(process.argv[i].replace(/^--/, ''), process.argv[i + 1]);
}

// Vite loads the generator's TypeScript for us, so the tool and the game are
// guaranteed to be running the same code.
const vite = await createServer({ server: { middlewareMode: true }, appType: 'custom' });
const { generateTown, toTiledJSON } = await vite.ssrLoadModule('/src/app/phaser/world/generate.ts');
await vite.close();

const seed = Number(args.get('seed') ?? 7);
const town = generateTown({
	seed,
	width: args.get('width') ? Number(args.get('width')) : undefined,
	height: args.get('height') ? Number(args.get('height')) : undefined,
});

const out = args.get('out') ?? `e2e/.artifacts/town-${seed}.json`;
await mkdir(dirname(out), { recursive: true });
await writeFile(out, `${JSON.stringify(toTiledJSON(town))}\n`);
console.log(
	`seed ${seed}: ${town.width}x${town.height}, landmarks ${Object.entries(town.landmarks)
		.map(([name, at]) => `${name}@${at.x},${at.y}`)
		.join(' ')} -> ${out}`,
);
