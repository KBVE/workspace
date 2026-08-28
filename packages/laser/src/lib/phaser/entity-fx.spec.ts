import { describe, it, expect, vi, beforeEach } from 'vitest';

// entity-fx reaches for Phaser.TintModes and Phaser.Math.Clamp only, so the
// module stands in for the engine rather than the engine being loaded.
vi.mock('phaser', () => ({
	default: {
		TintModes: { FILL: 1, MULTIPLY: 0 },
		Math: {
			Clamp: (v: number, lo: number, hi: number) =>
				Math.max(lo, Math.min(hi, v)),
		},
	},
}));

const {
	attachCameraZoom,
	drawHealthBar,
	drawHealthBarCached,
	flashEntity,
	floatingText,
} = await import('./entity-fx');

const makeGraphics = () => ({
	clear: vi.fn().mockReturnThis(),
	fillStyle: vi.fn().mockReturnThis(),
	fillRect: vi.fn().mockReturnThis(),
	setPosition: vi.fn().mockReturnThis(),
});

const makeSprite = (active = true) => ({
	active,
	scene: active ? {} : null,
	setTint: vi.fn().mockReturnThis(),
	setTintMode: vi.fn().mockReturnThis(),
	clearTint: vi.fn().mockReturnThis(),
});

/** A scene whose delayedCall queue a test can run by hand. */
const makeScene = () => {
	const queued: (() => void)[] = [];
	return {
		queued,
		run: () => queued.splice(0).forEach((fn) => fn()),
		time: {
			delayedCall: vi.fn((_ms: number, fn: () => void) => queued.push(fn)),
		},
		tweens: { add: vi.fn() },
		add: {
			text: vi.fn(() => ({
				setOrigin: vi.fn().mockReturnThis(),
				setDepth: vi.fn().mockReturnThis(),
				destroy: vi.fn(),
			})),
		},
		cameras: { main: { zoom: 1, setZoom: vi.fn() } },
		input: {
			on: vi.fn(),
			off: vi.fn(),
			keyboard: { on: vi.fn(), off: vi.fn() },
		},
	};
};

describe('drawHealthBar', () => {
	let g: ReturnType<typeof makeGraphics>;

	beforeEach(() => {
		g = makeGraphics();
	});

	/** The filled portion is the second fillRect; its width argument is index 2. */
	const filledWidth = () => g.fillRect.mock.calls[1][2];

	it('fills in proportion to the health remaining', () => {
		drawHealthBar(g as never, 0, 0, 50, 100, 26);
		expect(filledWidth()).toBeCloseTo(12.5);
	});

	it('clamps above max and below zero', () => {
		drawHealthBar(g as never, 0, 0, 500, 100, 26);
		expect(filledWidth()).toBe(25);

		g = makeGraphics();
		drawHealthBar(g as never, 0, 0, -10, 100, 26);
		expect(filledWidth()).toBe(0);
	});

	// hp/maxHp is NaN when maxHp is 0, and NaN survives both clamps -- Math.min
	// and Math.max return it untouched -- so the fill width reaches fillRect as
	// NaN and the bar renders as garbage. An entity with no max health is not
	// exotic: it is one that has not been given stats yet.
	it('draws an empty bar rather than NaN when there is no max', () => {
		drawHealthBar(g as never, 0, 0, 0, 0, 26);
		expect(filledWidth()).toBe(0);
		expect(Number.isNaN(filledWidth())).toBe(false);
	});

	it('picks the colour band from the fraction', () => {
		const bandFor = (hp: number) => {
			const gfx = makeGraphics();
			drawHealthBar(gfx as never, 0, 0, hp, 100);
			return gfx.fillStyle.mock.calls[1][0];
		};
		expect(bandFor(80)).toBe(0x4ade80);
		expect(bandFor(40)).toBe(0xfbbf24);
		expect(bandFor(10)).toBe(0xf87171);
	});
});

describe('drawHealthBarCached', () => {
	it('follows the entity every frame but redraws only on change', () => {
		const g = makeGraphics();
		const first = drawHealthBarCached(g as never, 10, 20, 50, 100, undefined);
		expect(first.drawn).toBe(true);

		const second = drawHealthBarCached(g as never, 30, 40, 50, 100, first.cache);
		expect(second.drawn).toBe(false);
		// Position still tracked, so a moving entity's bar moves with it.
		expect(g.setPosition).toHaveBeenLastCalledWith(30, 40);
	});

	it('redraws when max health changes even though current health did not', () => {
		const g = makeGraphics();
		const first = drawHealthBarCached(g as never, 0, 0, 50, 100, undefined);
		const second = drawHealthBarCached(g as never, 0, 0, 50, 200, first.cache);
		expect(second.drawn).toBe(true);
	});
});

describe('flashEntity', () => {
	it('flashes white, settles to the hit colour, then clears', () => {
		const scene = makeScene();
		const sprite = makeSprite();
		flashEntity(scene as never, sprite as never, 0xff0000);

		expect(sprite.setTint).toHaveBeenCalledWith(0xffffff);
		scene.run();
		expect(sprite.setTint).toHaveBeenCalledWith(0xff0000);
		expect(sprite.clearTint).toHaveBeenCalled();
	});

	// The flash runs for 180ms after a hit, and a hit is the most likely thing
	// to destroy the sprite before it finishes. A destroyed Phaser GameObject
	// has had its internals torn down, so tinting it throws inside a timer
	// callback, where there is no call stack pointing back at the cause.
	it('does nothing to a sprite destroyed mid-flash', () => {
		const scene = makeScene();
		const sprite = makeSprite();
		flashEntity(scene as never, sprite as never);

		sprite.active = false;
		sprite.scene = null;
		sprite.setTint.mockClear();
		sprite.clearTint.mockClear();

		expect(() => scene.run()).not.toThrow();
		expect(sprite.setTint).not.toHaveBeenCalled();
		expect(sprite.clearTint).not.toHaveBeenCalled();
	});
});

describe('floatingText', () => {
	it('rises, fades, and destroys itself', () => {
		const scene = makeScene();
		floatingText(scene as never, 10, 20, 'crit', '#fff', 5);

		const tween = scene.tweens.add.mock.calls[0][0] as {
			y: number;
			alpha: number;
			onComplete: () => void;
		};
		expect(tween.y).toBe(20 - 28);
		expect(tween.alpha).toBe(0);
		expect(() => tween.onComplete()).not.toThrow();
	});
});

describe('attachCameraZoom', () => {
	it('clamps zoom to the configured range', () => {
		const scene = makeScene();
		attachCameraZoom(scene as never, { min: 1, max: 2, step: 5 });

		const zoomIn = scene.input.keyboard.on.mock.calls.find(
			([evt]) => evt === 'keydown-PLUS',
		)![1] as () => void;
		zoomIn();
		expect(scene.cameras.main.setZoom).toHaveBeenCalledWith(2);
	});

	it('zooms out on the minus key and both ways on the wheel', () => {
		const scene = makeScene();
		scene.cameras.main.zoom = 1.5;
		attachCameraZoom(scene as never, { min: 0.5, max: 3, step: 0.5 });

		const key = (name: string) =>
			scene.input.keyboard.on.mock.calls.find(([e]) => e === name)![1] as () => void;
		key('keydown-MINUS')();
		expect(scene.cameras.main.setZoom).toHaveBeenLastCalledWith(1);

		const wheel = scene.input.on.mock.calls.find(
			([e]) => e === 'wheel',
		)![1] as (p: unknown, o: unknown, dx: number, dy: number) => void;

		// Scrolling down zooms out, scrolling up zooms in, and the wheel moves
		// in smaller increments than the keys.
		wheel(null, null, 0, 1);
		expect(scene.cameras.main.setZoom).toHaveBeenLastCalledWith(1.125);
		wheel(null, null, 0, -1);
		expect(scene.cameras.main.setZoom).toHaveBeenLastCalledWith(1.875);
	});

	// A scene that restarts calls this again. Without a way to undo it, every
	// restart adds another set of handlers to the same input plugin and the
	// zoom step multiplies by the number of restarts.
	it('returns a disposer that removes what it added', () => {
		const scene = makeScene();
		const dispose = attachCameraZoom(scene as never);

		expect(dispose).toBeTypeOf('function');
		dispose();
		expect(scene.input.keyboard.off).toHaveBeenCalledTimes(2);
		expect(scene.input.off).toHaveBeenCalledTimes(1);
	});
});
