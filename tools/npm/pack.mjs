// Assembles a built package into the exact tree npm publishes, then checks it
// holds together.
//
// Lives here rather than in a project so that adding an npm package is a tag
// and nothing else. Run from the project directory, which is where moon runs a
// task; everything below is relative to that.
//
// Nx did the first half of this with nxCopyAssetsPlugin and never did the
// second, which is how @kbve/laser 0.2.0 shipped bundles importing chunk files
// its `files` glob excluded -- every entry point 404s on first import, and
// nothing in the repository could have noticed.
//
// Reads:
//   NPM_DIST   directory the build wrote to, relative to the project (default: dist)
import { execFileSync } from 'node:child_process';
import { copyFileSync, existsSync, readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';

const die = (message) => {
	console.error(`::error::${message}`);
	process.exit(1);
};

const project = process.cwd();
const dist = path.join(project, process.env.NPM_DIST || 'dist');

if (!existsSync(dist)) {
	die(`${dist} does not exist. The build task should have produced it.`);
}

// The manifest and README are not build output, but npm needs both beside the
// bundles: `files` is relative to the package root, which is the dist tree at
// publish time. README.md is optional -- a package without one still packs.
copyFileSync(path.join(project, 'package.json'), path.join(dist, 'package.json'));
for (const optional of ['README.md', 'LICENSE', 'LICENSE.md']) {
	const from = path.join(project, optional);
	if (existsSync(from)) copyFileSync(from, path.join(dist, optional));
}

const manifest = JSON.parse(readFileSync(path.join(dist, 'package.json'), 'utf8'));
if (manifest.private) {
	die(`${manifest.name} is marked private, so it cannot be published. Drop the 'private' field or remove the 'npm' tag.`);
}

const packed = new Set(
	JSON.parse(
		execFileSync('npm', ['pack', '--dry-run', '--json'], {
			cwd: dist,
			encoding: 'utf8',
		}),
	)[0].files.map((f) => f.path),
);

// Every subpath in `exports` has to be in the tarball, or a consumer importing
// it gets ERR_PACKAGE_PATH_NOT_EXPORTED from a package that installed cleanly.
const exported = [];
const walk = (node) => {
	if (typeof node === 'string') exported.push(node);
	else if (node && typeof node === 'object') Object.values(node).forEach(walk);
};
walk(manifest.exports ?? {});

// Relative specifiers the bundles actually reach for. Rollup hashes shared
// chunk names, so these can only be checked by reading the output itself.
const imported = [];
for (const file of readdirSync(dist).filter((f) => f.endsWith('.js'))) {
	const source = readFileSync(path.join(dist, file), 'utf8');
	for (const [, spec] of source.matchAll(/from\s*["'](\.[^"']*)["']/g)) {
		imported.push([file, spec]);
	}
}

const missing = [
	...exported
		.filter((spec) => !packed.has(path.normalize(spec)))
		.map((spec) => `exports -> ${spec}`),
	...imported
		.filter(([file, spec]) =>
			!packed.has(path.normalize(path.join(path.dirname(file), spec))))
		.map(([file, spec]) => `${file} -> ${spec}`),
];

if (missing.length) {
	die(
		`These paths are not in the tarball, so the published package cannot ` +
			`load. Widen "files" in package.json:\n  ${missing.join('\n  ')}`,
	);
}

console.log(
	`${manifest.name}@${manifest.version}: ${packed.size} files, ` +
		`${exported.length} export targets, ${imported.length} internal imports, all present.`,
);
