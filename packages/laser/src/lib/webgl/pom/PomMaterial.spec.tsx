import { describe, it, expect, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';

const extend = vi.fn();
vi.mock('@react-three/fiber', async (importOriginal) => ({
	...(await importOriginal<typeof import('@react-three/fiber')>()),
	extend,
}));

const { registerPomMaterial } = await import('./PomMaterial');

describe('pomMaterial registration', () => {
	it('registers the element as soon as the module is evaluated', () => {
		// Nothing here has called it, so the entry came from module evaluation.
		expect(extend).toHaveBeenCalledWith(
			expect.objectContaining({ PomMaterial: expect.anything() }),
		);
	});

	it('registers once, however many times it is asked', () => {
		const before = extend.mock.calls.length;
		registerPomMaterial();
		registerPomMaterial();
		expect(extend.mock.calls).toHaveLength(before);
	});
});

/**
 * That registration is invisible to a bundler, so `"sideEffects": false` would
 * let a build drop the module and leave `<pomMaterial>` unknown at render time
 * -- with no error until something renders it. See PomMaterial.tsx.
 */
describe('package side-effect declaration', () => {
	it('does not claim the package is free of side effects', () => {
		const manifest = JSON.parse(
			readFileSync(
				path.join(__dirname, '..', '..', '..', '..', 'package.json'),
				'utf8',
			),
		) as { sideEffects?: unknown };

		expect(
			manifest.sideEffects,
			'PomMaterial registers <pomMaterial> at import time and nothing ' +
				'references it, so a tree-shaking build would drop it. If this is ' +
				'to change, make every consumer call registerPomMaterial() first.',
		).toBeUndefined();
	});
});
