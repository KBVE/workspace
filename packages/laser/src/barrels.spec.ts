import { describe, it, expect, vi } from 'vitest';

/**
 * Phaser probes a canvas 2D context on evaluation and jsdom returns null, so
 * the real engine fails on itself here. Every runtime `Phaser.*` reference in
 * laser is inside a function body, so an importable module is all the barrel
 * check needs.
 */
vi.mock('phaser', () => ({ default: {} }));

/**
 * Barrels, checked by importing them. entrypoints.spec.ts reads these files
 * statically and never evaluates one, so a re-export of a renamed symbol
 * typechecks and surfaces as `undefined` in a consumer's app.
 */

describe('lib/i18n barrel', () => {
	it('re-exports the store and the react bindings', async () => {
		const barrel = await import('./lib/i18n');
		expect(barrel.I18nStore).toBeTypeOf('function');
		expect(barrel.laserI18n).toBeInstanceOf(barrel.I18nStore);
		expect(barrel.I18nProvider).toBeTypeOf('function');
		expect(barrel.useTranslation).toBeTypeOf('function');
	});
});

describe('lib/webgl/pom barrel', () => {
	it('re-exports the uniform helpers, the GLSL chunks and the WGSL stub', async () => {
		const pom = await import('./lib/webgl/pom');

		expect(pom.createPomUniforms).toBeTypeOf('function');
		expect(pom.toThreeUniforms).toBeTypeOf('function');
		expect(pom.POM_DEFAULTS).toBeTypeOf('object');
		expect(pom.registerPomMaterial).toBeTypeOf('function');

		for (const chunk of [
			pom.POM_VARYINGS,
			pom.DERIVE_TANGENT,
			pom.POM_MARCH,
			pom.SPOM_SILHOUETTE,
			pom.POM_SELF_SHADOW,
			pom.HEIGHT_HELPERS,
		]) {
			expect(chunk).toBeTypeOf('string');
			expect(chunk.length).toBeGreaterThan(0);
		}

		// The three source constants are distinct branch values in the shader,
		// so two of them collapsing into one would silently pick the wrong path.
		expect(
			new Set([
				pom.POM_SOURCE_BRICK,
				pom.POM_SOURCE_LUMA,
				pom.POM_SOURCE_MAP,
			]).size,
		).toBe(3);
	});

	// The WebGPU path is not wired into any consumer, so nothing else would
	// notice the stub drifting from the contract its own comment states.
	it('keeps the WGSL stub honouring the documented entry point', async () => {
		const { POM_WGSL_STUB } = await import('./lib/webgl/pom/pom.wgsl');
		expect(POM_WGSL_STUB).toContain('fn pomSampleDepth(uv: vec2<f32>) -> f32');
	});
});

describe('lib/physics/rapier', () => {
	it('re-exports the connector', async () => {
		const rapier = await import('./lib/physics/rapier');
		expect(rapier).toHaveProperty('RAPIER');
		expect(rapier.createRapierPhysics).toBeTypeOf('function');
	});
});

describe('lib/ecs/bitecs', () => {
	// `export *` from a peer -- a bitecs rename lands here first.
	it('re-exports the bitecs surface the ECS modules use', async () => {
		const bitecs = await import('./lib/ecs/bitecs');
		for (const name of [
			'createWorld',
			'addEntity',
			'removeEntity',
			'addComponent',
			'removeComponent',
			'hasComponent',
			'query',
		]) {
			expect(bitecs[name as keyof typeof bitecs]).toBeTypeOf('function');
		}
	});
});

/**
 * The five published entry points, evaluated rather than read. Reading them is
 * what lets entrypoints.spec.ts check the peer split without installing every
 * peer; the cost is that a barrel naming a missing export passes it.
 */
describe('published entry points', () => {
	it('@kbve/laser exposes the renderer-agnostic surface', async () => {
		const laser = await import('./index');

		expect(laser.LaserEventBus).toBeTypeOf('function');
		expect(laser.laserEvents).toBeInstanceOf(laser.LaserEventBus);
		expect(laser.Quadtree).toBeTypeOf('function');
		expect(laser.findTilePath).toBeTypeOf('function');
		expect(laser.GameClient).toBeTypeOf('function');
		expect(laser.RealmChatClient).toBeTypeOf('function');
		expect(laser.ReconnectingSocket).toBeTypeOf('function');
		expect(laser.AdCard).toBeTypeOf('function');
		expect(laser.laserAds).toBeTypeOf('object');
		expect(laser.openExternal).toBeTypeOf('function');

		// A re-export of a renamed symbol resolves to undefined, not an error.
		const holes = Object.entries(laser)
			.filter(([, v]) => v === undefined)
			.map(([k]) => k);
		expect(holes, `undefined exports: ${holes.join(', ')}`).toEqual([]);
	});

	it('@kbve/laser/ecs exposes the ECS on its own', async () => {
		const ecs = await import('./ecs');
		expect(ecs.createWorld).toBeTypeOf('function');
		expect(ecs.query).toBeTypeOf('function');
		expect(Object.values(ecs).filter((v) => v === undefined)).toEqual([]);
	});

	it('@kbve/laser/mecs exposes the shared-buffer views', async () => {
		const mecs = await import('./mecs');
		expect(Object.keys(mecs).length).toBeGreaterThan(0);
		expect(Object.values(mecs).filter((v) => v === undefined)).toEqual([]);
	});

	it('@kbve/laser/r3f exposes the three bindings', async () => {
		const r3f = await import('./r3f');
		expect(r3f.Stage).toBeTypeOf('function');
		expect(r3f.useGameLoop).toBeTypeOf('function');
		expect(r3f.createPomUniforms).toBeTypeOf('function');
		expect(Object.values(r3f).filter((v) => v === undefined)).toEqual([]);
	});

	it('@kbve/laser/phaser exposes the phaser bindings', async () => {
		const phaser = await import('./phaser');
		// forwardRef returns an exotic component object, not a function, so this
		// checks the thing that actually matters: React will accept it.
		expect(phaser.PhaserGame).toHaveProperty(
			'$$typeof',
			Symbol.for('react.forward_ref'),
		);
		expect(phaser.usePhaserEvent).toBeTypeOf('function');
		expect(phaser.PlayerController).toBeTypeOf('function');
		expect(phaser.GameObjectPool).toBeTypeOf('function');
		expect(Object.values(phaser).filter((v) => v === undefined)).toEqual([]);
	});
});
