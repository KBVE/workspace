import { describe, it, expect, vi } from 'vitest';

/**
 * Phaser probes a canvas 2D context when it is first evaluated, and jsdom hands
 * back null, so importing the real engine here fails on the engine rather than
 * on anything in this package. Every runtime `Phaser.*` reference in laser sits
 * inside a function body, so the module only has to be importable for the
 * phaser barrel to be evaluated and its re-exports checked -- which is what
 * this file is for. Behaviour that needs the engine is covered by the specs
 * beside each module.
 */
vi.mock('phaser', () => ({ default: {} }));

/**
 * Barrels and re-export modules, checked by importing them.
 *
 * A barrel is where a rename goes wrong quietly: entrypoints.spec.ts reads the
 * files statically and never evaluates one, tsc is happy with a re-export of
 * something that exists at build time, and the failure surfaces as `undefined`
 * in a consumer's app. Evaluating each barrel and asserting the named exports
 * are actually bound is the cheap way to catch that here instead.
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
	// A thin re-export of an optional peer, and the only thing standing between
	// `@kbve/laser/phaser` and a rapier import that resolves to undefined.
	it('re-exports the connector', async () => {
		const rapier = await import('./lib/physics/rapier');
		expect(rapier).toHaveProperty('RAPIER');
		expect(rapier.createRapierPhysics).toBeTypeOf('function');
	});
});

describe('lib/ecs/bitecs', () => {
	// `export *` from a peer: the seam every ECS module imports through, so a
	// bitecs rename lands here first.
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
 * The five published entry points, evaluated.
 *
 * entrypoints.spec.ts reads these files as text -- that is what lets it prove
 * the optional peers stay behind their subpaths without installing every one.
 * The cost is that a barrel naming an export that no longer exists passes that
 * check and fails in a consumer's build. Importing each one closes it, and is
 * also the only place the `exports` map is exercised the way an installed
 * package uses it.
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

		// Nothing in the barrel may be a hole. A re-export of a name that has
		// been renamed away resolves to undefined rather than throwing.
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
