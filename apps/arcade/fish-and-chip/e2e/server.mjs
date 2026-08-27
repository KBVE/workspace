import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

// Serves the build the way itch.io does: under a path prefix rather than at the
// domain root. That is not decoration -- `base: './'` in vite.config.ts is the
// single setting standing between a working upload and a blank page, and
// serving from '/' would let a regression through unnoticed.
const ROOT = process.argv[2] ?? 'dist';
const PORT = Number(process.argv[3] ?? 8110);
const PREFIX = process.argv[4] ?? '/html';

const TYPES = {
	'.html': 'text/html',
	'.js': 'text/javascript',
	'.mjs': 'text/javascript',
	'.css': 'text/css',
	'.json': 'application/json',
	'.png': 'image/png',
	'.webp': 'image/webp',
	'.ico': 'image/x-icon',
	'.ogg': 'audio/ogg',
	'.mp3': 'audio/mpeg',
};

createServer(async (req, res) => {
	const url = new URL(req.url, 'http://localhost');
	const path = decodeURIComponent(url.pathname);

	if (!path.startsWith(PREFIX)) {
		res.writeHead(404).end('outside the prefix');
		return;
	}

	const rel = normalize(path.slice(PREFIX.length)).replace(/^(\.\.[/\\])+/, '');
	let file = join(ROOT, rel === '' || rel === '/' ? 'index.html' : rel);
	try {
		if ((await stat(file)).isDirectory()) file = join(file, 'index.html');
		const body = await readFile(file);
		res.writeHead(200, {
			'Content-Type': TYPES[extname(file)] ?? 'application/octet-stream',
			'Cache-Control': 'no-store',
		});
		res.end(body);
	} catch {
		res.writeHead(404).end('not found');
	}
}).listen(PORT, () => console.log(`serving ${ROOT} on http://127.0.0.1:${PORT}${PREFIX}/`));
