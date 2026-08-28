import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('phaser', () => ({ default: {} }));

const { VirtualJoystick } = await import('./virtual-joystick');

const makeArc = () => ({
	x: 0,
	y: 0,
	setDepth: vi.fn().mockReturnThis(),
	setScrollFactor: vi.fn().mockReturnThis(),
	setVisible: vi.fn().mockReturnThis(),
	destroy: vi.fn(),
	setPosition: vi.fn(function (this: { x: number; y: number }, x: number, y: number) {
		this.x = x;
		this.y = y;
		return this;
	}),
});

/** A scene whose pointer events a test can fire by hand. */
const makeScene = () => {
	const handlers = new Map<string, ((p: unknown) => void)[]>();
	const arcs: ReturnType<typeof makeArc>[] = [];
	return {
		arcs,
		handlers,
		fire: (event: string, pointer: unknown) =>
			handlers.get(event)?.forEach((fn) => fn(pointer)),
		scale: { height: 600 },
		add: {
			circle: vi.fn((x: number, y: number) => {
				const arc = makeArc();
				arc.x = x;
				arc.y = y;
				arcs.push(arc);
				return arc;
			}),
		},
		input: {
			on: vi.fn((event: string, fn: (p: unknown) => void) => {
				handlers.set(event, [...(handlers.get(event) ?? []), fn]);
			}),
			off: vi.fn((event: string, fn: (p: unknown) => void) => {
				handlers.set(
					event,
					(handlers.get(event) ?? []).filter((h) => h !== fn),
				);
			}),
		},
	};
};

const pointer = (x: number, y: number) => ({ x, y });

describe('VirtualJoystick', () => {
	let scene: ReturnType<typeof makeScene>;

	beforeEach(() => {
		scene = makeScene();
	});

	const make = (config = {}) =>
		new VirtualJoystick(scene as never, { x: 100, y: 100, radius: 50, ...config });

	/** Drags from the base centre to (x, y) with the pointer held down. */
	const drag = (joystick: unknown, x: number, y: number) => {
		void joystick;
		const p = pointer(100, 100);
		scene.fire('pointerdown', p);
		const moved = pointer(x, y);
		scene.fire('pointermove', p);
		Object.assign(p, moved);
		scene.fire('pointermove', p);
		return p;
	};

	describe('construction', () => {
		it('places the base and a smaller thumb, pinned to the camera', () => {
			make();
			const [base, thumb] = scene.arcs;

			expect(scene.add.circle).toHaveBeenCalledTimes(2);
			expect(base.setScrollFactor).toHaveBeenCalledWith(0);
			expect(thumb.setScrollFactor).toHaveBeenCalledWith(0);
			// The thumb sits above the base, or it is invisible under it.
			expect(base.setDepth).toHaveBeenCalledWith(100);
			expect(thumb.setDepth).toHaveBeenCalledWith(101);
		});

		it('defaults its position to the bottom-left of the viewport', () => {
			new VirtualJoystick(scene as never);
			expect(scene.add.circle).toHaveBeenCalledWith(
				120,
				480,
				60,
				0x888888,
				0.35,
			);
		});
	});

	describe('direction', () => {
		it('starts with no direction and inactive', () => {
			const joystick = make();
			expect(joystick.direction).toBeNull();
			expect(joystick.isActive).toBe(false);
		});

		it('becomes active on a pointer down inside its reach', () => {
			const joystick = make();
			scene.fire('pointerdown', pointer(100, 100));
			expect(joystick.isActive).toBe(true);
		});

		// A fixed joystick belongs to its corner; a tap on the far side of the
		// screen is someone touching the game, not reaching for the stick.
		it('ignores a pointer down beyond twice its radius when fixed', () => {
			const joystick = make({ fixed: true });
			scene.fire('pointerdown', pointer(500, 500));
			expect(joystick.isActive).toBe(false);
		});

		it('relocates to the pointer when not fixed', () => {
			const joystick = make({ fixed: false });
			scene.fire('pointerdown', pointer(400, 300));

			const [base, thumb] = scene.arcs;
			expect(base.setPosition).toHaveBeenCalledWith(400, 300);
			expect(thumb.setPosition).toHaveBeenCalledWith(400, 300);
			expect(joystick.isActive).toBe(true);
		});

		it.each([
			[150, 100, 'right'],
			[140, 140, 'down-right'],
			[100, 150, 'down'],
			[60, 140, 'down-left'],
			[50, 100, 'left'],
			[60, 60, 'up-left'],
			[100, 50, 'up'],
			[140, 60, 'up-right'],
		])('maps a drag to (%i, %i) as %s', (x, y, expected) => {
			const joystick = make();
			drag(joystick, x, y);
			expect(joystick.direction).toBe(expected);
		});

		// Below the dead zone the stick is at rest, however precisely the
		// pointer happens to sit off-centre.
		it('reports no direction inside the dead zone', () => {
			const joystick = make({ deadZone: 0.5 });
			drag(joystick, 110, 100);
			expect(joystick.direction).toBeNull();
		});

		it('clamps the thumb to the base radius', () => {
			const joystick = make();
			drag(joystick, 1000, 100);

			const thumb = scene.arcs[1];
			expect(thumb.x).toBeCloseTo(150);
			expect(joystick.direction).toBe('right');
		});
	});

	describe('release', () => {
		it('recentres and goes inactive on pointer up', () => {
			const joystick = make();
			const p = drag(joystick, 150, 100);
			expect(joystick.direction).toBe('right');

			scene.fire('pointerup', p);

			expect(joystick.direction).toBeNull();
			expect(joystick.isActive).toBe(false);
			expect(scene.arcs[1].setPosition).toHaveBeenLastCalledWith(100, 100);
		});

		// Multi-touch: a second finger elsewhere on screen must not steal or
		// release the stick the first one is holding.
		it('ignores events from a pointer it is not tracking', () => {
			const joystick = make();
			drag(joystick, 150, 100);

			scene.fire('pointerup', pointer(0, 0));
			expect(joystick.isActive).toBe(true);

			scene.fire('pointermove', pointer(100, 150));
			expect(joystick.direction).toBe('right');
		});

		it('does not take a second pointer while one is held', () => {
			const joystick = make({ fixed: false });
			scene.fire('pointerdown', pointer(100, 100));
			scene.fire('pointerdown', pointer(400, 400));

			expect(scene.arcs[0].setPosition).not.toHaveBeenCalledWith(400, 400);
			expect(joystick.isActive).toBe(true);
		});
	});

	it('hides and shows both parts together', () => {
		const joystick = make();
		expect(joystick.setVisible(false)).toBe(joystick);
		for (const arc of scene.arcs) {
			expect(arc.setVisible).toHaveBeenCalledWith(false);
		}
	});

	describe('destroy', () => {
		it('destroys both parts', () => {
			make().destroy();
			for (const arc of scene.arcs) expect(arc.destroy).toHaveBeenCalled();
		});

		// The input plugin outlives the scene's create(), so handlers left
		// attached keep running against destroyed Arcs -- the next pointerdown
		// reads this.base.x off an object Phaser has torn down.
		it('detaches its input handlers', () => {
			const joystick = make();
			joystick.destroy();

			expect(scene.input.off).toHaveBeenCalledTimes(3);
			expect(() => scene.fire('pointerdown', pointer(100, 100))).not.toThrow();
			expect(joystick.isActive).toBe(false);
		});
	});
});
