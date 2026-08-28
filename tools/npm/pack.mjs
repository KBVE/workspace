// Assembles dist/ into the exact tree npm publishes, then checks it holds
// together. Nx did the first half with nxCopyAssetsPlugin and never did the
// second, which is how @kbve/laser 0.2.0 shipped bundles importing chunk files
// the `files` glob excluded -- every entry point 404s on first import, and
// nothing in the repository could have noticed.
//
// Run as `moon run laser:pack`. It does not publish; it produces and verifies
// the tarball contents.
import { execFileSync } from 'node:child_process';
import { copyFileSync, existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const dist = path.join(root, 'dist');

if (!existsSync(dist)) {
	console.error('dist/ is missing -- run the build first.');
	process.exit(1);
}

// The manifest and README are not build output, but npm needs both beside the
// bundles. `files` is relative to the package root, which is dist/ at publish.
for (const asset of ['package.json', 'README.md']) {
	copyFileSync(path.join(root, asset), path.join(dist, asset));
}

const packed = new Set(
	JSON.parse(
		execFileSync('npm', ['pack', '--dry-run', '--json'], {
			cwd: dist,
			encoding: 'utf8',
		}),
	)[0].files.map((f) => f.path),
);

// Every relative specifier any bundle reaches for. Rollup hashes shared chunk
// names, so they can only be checked by reading what the output actually says.
const missing = [];
for (const file of readdirSync(dist).filter((f) => f.endsWith('.js'))) {
	const source = readFileSync(path.join(dist, file), 'utf8');
	for (const [, spec] of source.matchAll(/from\s*["'](\.[^"']*)["']/g)) {
		const target = path.normalize(path.join(path.dirname(file), spec));
		if (!packed.has(target)) missing.push(`${file} -> ${spec}`);
	}
}

if (missing.length) {
	console.error(
		`These imports resolve to files the 'files' glob excludes, so the published package cannot load:\n  ${missing.join('\n  ')}`,
	);
	process.exit(1);
}

console.log(`packed ${packed.size} files, ${missing.length} broken imports`);
