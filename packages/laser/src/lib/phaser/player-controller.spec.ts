import { describe, it, expect, beforeEach, vi } from 'vitest';
import { PlayerController } from './player-controller';
import { laserEvents } from '../core/events';
import type { Quadtree } from '../spatial/quadtree';

vi.mock('phaser', () => {
	const KeyCodes = { W: 87, A: 65, S: 83, D: 68 };
	return {
		default: {
			Input: { Keyboard: { KeyCodes } },
		},
		Scene: class Scene {},
		Input: { Keyboard: { KeyCodes } },
	};
});

function createMockScene() {
	const fKey = { isDown: false };
	return {
		input: {
			keyboard: {
				createCursorKeys: () => ({
					up: { isDown: false },
					down: { isDown: false },
					left: { isDown: false },
					right: { isDown: false },
				}),
				addKey: vi.fn().mockReturnValue(fKey),
			},
		},
		add: {
			text: vi.fn().mockReturnValue({
				setDepth: vi.fn().mockReturnThis(),
				setPadding: vi.fn().mockReturnThis(),
				setVisible: vi.fn().mockReturnThis(),
				setPosition: vi.fn().mockReturnThis(),
			}),
		},
		_fKey: fKey,
	};
}

function createMockGridEngine() {
	return {
		getPosition: vi.fn().mockReturnValue({ x: 5, y: 5 }),
		move: vi.fn(),
	};
}

function createMockQuadtree(queryResult: any[] = []) {
	return {
		query: vi.fn().mockReturnValue(queryResult),
		insert: vi.fn(),
		queryRange: vi.fn(),
	} as unknown as Quadtree;
}

describe('PlayerController', () => {
	let scene: ReturnType<typeof createMockScene>;
	let gridEngine: ReturnType<typeof createMockGridEngine>;
	let quadtree: Quadtree;
	let controller: PlayerController;

	beforeEach(() => {
		scene = createMockScene();
		gridEngine = createMockGridEngine();
		quadtree = createMockQuadtree();
		controller = new PlayerController(scene as any, gridEngine, quadtree);
		vi.clearAllMocks();
	});

	it('should return player position', () => {
		gridEngine.getPosition.mockReturnValue({ x: 3, y: 7 });
		const pos = controller.getPlayerPosition();
		expect(pos).toEqual({ x: 3, y: 7 });
		expect(gridEngine.getPosition).toHaveBeenCalledWith('player');
	});

	it('should use custom playerId', () => {
		const custom = new PlayerController(
			scene as any,
			gridEngine,
			quadtree,
			{
				playerId: 'hero',
			},
		);
		gridEngine.getPosition.mockReturnValue({ x: 1, y: 1 });
		custom.getPlayerPosition();
		expect(gridEngine.getPosition).toHaveBeenCalledWith('hero');
	});

	it('should call handleMovement without errors when no keys pressed', () => {
		expect(() => controller.handleMovement()).not.toThrow();
	});

	it('should emit player:interact and call range actions on F key press', () => {
		const action = vi.fn();
		const ranges = [
			{
				name: 'test',
				bounds: { xMin: 0, xMax: 10, yMin: 0, yMax: 10 },
				action,
			},
		];
		quadtree = createMockQuadtree(ranges);
		controller = new PlayerController(scene as any, gridEngine, quadtree);

		const emitSpy = vi.spyOn(laserEvents, 'emit');

		scene._fKey.isDown = true;
		scene.input.keyboard.addKey.mockReturnValue(scene._fKey);

		controller.handleMovement();

		expect(action).toHaveBeenCalled();
		expect(emitSpy).toHaveBeenCalledWith('player:interact', {
			position: { x: 5, y: 5 },
			ranges,
		});

		emitSpy.mockRestore();
	});

	it('should show tooltip when near interactive objects', () => {
		const ranges = [
			{
				name: 'test',
				bounds: { xMin: 0, xMax: 10, yMin: 0, yMax: 10 },
				action: vi.fn(),
			},
		];
		quadtree = createMockQuadtree(ranges);
		const tooltipMock = {
			setDepth: vi.fn().mockReturnThis(),
			setPadding: vi.fn().mockReturnThis(),
			setVisible: vi.fn().mockReturnThis(),
			setPosition: vi.fn().mockReturnThis(),
		};
		scene.add.text.mockReturnValue(tooltipMock);
		controller = new PlayerController(scene as any, gridEngine, quadtree);

		controller.handleMovement();

		expect(tooltipMock.setVisible).toHaveBeenCalledWith(true);
		expect(tooltipMock.setPosition).toHaveBeenCalled();
	});

	it('should hide tooltip when not near any objects', () => {
		quadtree = createMockQuadtree([]);
		const tooltipMock = {
			setDepth: vi.fn().mockReturnThis(),
			setPadding: vi.fn().mockReturnThis(),
			setVisible: vi.fn().mockReturnThis(),
			setPosition: vi.fn().mockReturnThis(),
		};
		scene.add.text.mockReturnValue(tooltipMock);
		controller = new PlayerController(scene as any, gridEngine, quadtree);

		controller.handleMovement();

		expect(tooltipMock.setVisible).toHaveBeenCalledWith(false);
	});
});

/**
 * A scene whose keys a test can hold down. The factory above returns a fresh
 * cursor object per call, which cannot be driven.
 */
function createDrivableScene() {
	const cursors = {
		up: { isDown: false },
		down: { isDown: false },
		left: { isDown: false },
		right: { isDown: false },
	};
	const wasd: Record<number, { isDown: boolean }> = {
		87: { isDown: false },
		65: { isDown: false },
		83: { isDown: false },
		68: { isDown: false },
	};
	const fKey = { isDown: false };
	return {
		cursors,
		wasd,
		scene: {
			input: {
				on: vi.fn(),
				off: vi.fn(),
				keyboard: {
					createCursorKeys: () => cursors,
					addKey: vi.fn((code: number) => wasd[code] ?? fKey),
				},
			},
			scale: { height: 600 },
			add: {
				text: vi.fn().mockReturnValue({
					setDepth: vi.fn().mockReturnThis(),
					setPadding: vi.fn().mockReturnThis(),
					setVisible: vi.fn().mockReturnThis(),
					setPosition: vi.fn().mockReturnThis(),
				}),
				// Each call has to yield its own Arc carrying the coordinates it
				// was given: VirtualJoystick measures a pointer against base.x,
				// so a shared stub at the origin puts every touch out of reach.
				circle: vi.fn((x: number, y: number) => ({
					x,
					y,
					setDepth: vi.fn().mockReturnThis(),
					setScrollFactor: vi.fn().mockReturnThis(),
					setVisible: vi.fn().mockReturnThis(),
					destroy: vi.fn(),
					setPosition: vi.fn(function (
						this: { x: number; y: number },
						nx: number,
						ny: number,
					) {
						this.x = nx;
						this.y = ny;
						return this;
					}),
				})),
			},
		},
	};
}

describe('PlayerController movement', () => {
	// Diagonals are tested before cardinals, so a wrong order turns a diagonal
	// into whichever cardinal the chain reaches first.
	const cases: [string, string[], string][] = [
		['left arrow', ['left'], 'left'],
		['right arrow', ['right'], 'right'],
		['up arrow', ['up'], 'up'],
		['down arrow', ['down'], 'down'],
		['left+up', ['left', 'up'], 'up-left'],
		['left+down', ['left', 'down'], 'down-left'],
		['right+up', ['right', 'up'], 'up-right'],
		['right+down', ['right', 'down'], 'down-right'],
	];

	const wasdFor: Record<string, number> = { left: 65, right: 68, up: 87, down: 83 };

	it.each(cases)('moves on %s', (_name, keys, direction) => {
		const rig = createDrivableScene();
		const gridEngine = createMockGridEngine();
		const controller = new PlayerController(
			rig.scene as never,
			gridEngine,
			createMockQuadtree(),
		);

		for (const key of keys) {
			rig.cursors[key as 'left'].isDown = true;
		}
		controller.handleMovement();
		expect(gridEngine.move).toHaveBeenCalledWith('player', direction);
	});

	it.each(cases)('moves on %s held on WASD instead', (_name, keys, direction) => {
		const rig = createDrivableScene();
		const gridEngine = createMockGridEngine();
		const controller = new PlayerController(
			rig.scene as never,
			gridEngine,
			createMockQuadtree(),
		);

		for (const key of keys) {
			rig.wasd[wasdFor[key]].isDown = true;
		}
		controller.handleMovement();
		expect(gridEngine.move).toHaveBeenCalledWith('player', direction);
	});

	it('moves nowhere with nothing held', () => {
		const rig = createDrivableScene();
		const gridEngine = createMockGridEngine();
		new PlayerController(
			rig.scene as never,
			gridEngine,
			createMockQuadtree(),
		).handleMovement();

		expect(gridEngine.move).not.toHaveBeenCalled();
	});
});

describe('PlayerController joystick', () => {
	it('is off unless asked for', () => {
		const rig = createDrivableScene();
		new PlayerController(rig.scene as never, createMockGridEngine(), createMockQuadtree());
		expect(rig.scene.add.circle).not.toHaveBeenCalled();
	});

	it('takes a config object through', () => {
		const rig = createDrivableScene();
		new PlayerController(
			rig.scene as never,
			createMockGridEngine(),
			createMockQuadtree(),
			{ joystick: { radius: 80, x: 10, y: 20 } },
		);
		expect(rig.scene.add.circle).toHaveBeenCalledWith(
			10,
			20,
			80,
			expect.anything(),
			expect.anything(),
		);
	});

	it('takes `true` as "default config"', () => {
		const rig = createDrivableScene();
		new PlayerController(
			rig.scene as never,
			createMockGridEngine(),
			createMockQuadtree(),
			{ joystick: true },
		);
		expect(rig.scene.add.circle).toHaveBeenCalledWith(
			120,
			480,
			60,
			expect.anything(),
			expect.anything(),
		);
	});

	// On a phone the stick is the input; a keyboard key held at the same time
	// must not fight it for the same frame.
	it('wins over the keyboard while it is active', () => {
		const rig = createDrivableScene();
		const gridEngine = createMockGridEngine();
		const controller = new PlayerController(
			rig.scene as never,
			gridEngine,
			createMockQuadtree(),
			{ joystick: true },
		);

		const pointerdown = rig.scene.input.on.mock.calls.find(
			([e]) => e === 'pointerdown',
		)![1] as (p: unknown) => void;
		const pointermove = rig.scene.input.on.mock.calls.find(
			([e]) => e === 'pointermove',
		)![1] as (p: unknown) => void;

		const pointer = { x: 120, y: 480 };
		pointerdown(pointer);
		pointer.x = 200;
		pointermove(pointer);

		rig.cursors.up.isDown = true;
		controller.handleMovement();

		expect(gridEngine.move).toHaveBeenCalledExactlyOnceWith('player', 'right');
	});
});

describe('PlayerController without a keyboard', () => {
	// scene.input.keyboard is optional in Phaser -- a game booted with keyboard
	// input disabled, or a touch-only build, has none. The controller still has
	// to run its interaction check each frame rather than throwing on a cursor
	// it never got.
	it('still checks for nearby objects each frame', () => {
		const rig = createDrivableScene();
		(rig.scene.input as { keyboard?: unknown }).keyboard = undefined;
		const gridEngine = createMockGridEngine();

		const controller = new PlayerController(
			rig.scene as never,
			gridEngine,
			createMockQuadtree(),
		);

		expect(() => controller.handleMovement()).not.toThrow();
		expect(gridEngine.move).not.toHaveBeenCalled();
		expect(gridEngine.getPosition).toHaveBeenCalled();
	});
});
