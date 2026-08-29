import { Scene } from 'phaser';
import Phaser from 'phaser';
import type { Point2D } from '../core/types';
import type { Quadtree } from '../spatial/quadtree';
import { laserEvents } from '../core/events';
import { VirtualJoystick } from './virtual-joystick';
import type { GridDirection, VirtualJoystickConfig } from './virtual-joystick';

/**
 * The slice of grid-engine this controller drives.
 *
 * Structural rather than an import: grid-engine is not a peer of this package
 * and adding one for two method signatures would put it in every consumer's
 * install. Anything shaped like this satisfies it, grid-engine included.
 */
export interface GridMover {
	move(charId: string, direction: NonNullable<GridDirection>): void;
	getPosition(charId: string): Point2D;
}

export class PlayerController {
	private scene: Scene;
	private gridEngine: GridMover;
	private quadtree: Quadtree;
	private cursor: Phaser.Types.Input.Keyboard.CursorKeys | undefined;
	private wasdKeys!: Record<string, Phaser.Input.Keyboard.Key>;
	private tooltip: Phaser.GameObjects.Text;
	private tileSize: number;
	private playerId: string;
	private joystick: VirtualJoystick | null = null;

	constructor(
		scene: Scene,
		gridEngine: GridMover,
		quadtree: Quadtree,
		options?: {
			tileSize?: number;
			playerId?: string;
			joystick?: boolean | VirtualJoystickConfig;
		},
	) {
		this.scene = scene;
		this.gridEngine = gridEngine;
		this.quadtree = quadtree;
		this.tileSize = options?.tileSize ?? 48;
		this.playerId = options?.playerId ?? 'player';
		this.cursor = this.scene.input.keyboard?.createCursorKeys();
		this.initializeWASDKeys();
		this.tooltip = this.scene.add
			.text(0, 0, 'Press [F]', {
				font: '16px Arial',
				backgroundColor: '#000000',
			})
			.setDepth(4)
			.setPadding(3, 2, 2, 3)
			.setVisible(false);

		if (options?.joystick) {
			const joystickConfig =
				typeof options.joystick === 'object'
					? options.joystick
					: undefined;
			this.joystick = new VirtualJoystick(scene, joystickConfig);
		}
	}

	private initializeWASDKeys(): void {
		const keyboard = this.scene.input.keyboard;
		if (keyboard) {
			this.wasdKeys = {
				W: keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.W),
				A: keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.A),
				S: keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.S),
				D: keyboard.addKey(Phaser.Input.Keyboard.KeyCodes.D),
			};
		}
	}

	private checkForNearbyObjects(): void {
		const position = this.gridEngine.getPosition(this.playerId);
		const screenX = position.x * this.tileSize;
		const screenY = position.y * this.tileSize;

		const foundRanges = this.quadtree.query(position);

		if (foundRanges.length > 0) {
			this.tooltip.setPosition(screenX, screenY - 60).setVisible(true);
			laserEvents.emit('player:nearby', {
				position,
				ranges: foundRanges,
			});
		} else {
			this.tooltip.setVisible(false);
		}
	}

	getPlayerPosition(): Point2D {
		return this.gridEngine.getPosition(this.playerId);
	}

	handleMovement(): void {
		if (this.scene.input.keyboard?.addKey('F').isDown) {
			const position = this.gridEngine.getPosition(this.playerId);
			const foundRanges = this.quadtree.query(position);

			if (foundRanges.length > 0) {
				laserEvents.emit('player:interact', {
					position,
					ranges: foundRanges,
				});
				for (const range of foundRanges) {
					range.action();
				}
			}
		}

		// Joystick takes priority when active
		if (this.joystick?.isActive && this.joystick.direction) {
			this.gridEngine.move(this.playerId, this.joystick.direction);
			this.checkForNearbyObjects();
			return;
		}

		if (!this.cursor) {
			this.checkForNearbyObjects();
			return;
		}

		const cursors = this.cursor;
		const wasd = this.wasdKeys;

		if (
			(cursors.left.isDown || wasd['A'].isDown) &&
			(cursors.up.isDown || wasd['W'].isDown)
		) {
			this.gridEngine.move(this.playerId, 'up-left');
		} else if (
			(cursors.left.isDown || wasd['A'].isDown) &&
			(cursors.down.isDown || wasd['S'].isDown)
		) {
			this.gridEngine.move(this.playerId, 'down-left');
		} else if (
			(cursors.right.isDown || wasd['D'].isDown) &&
			(cursors.up.isDown || wasd['W'].isDown)
		) {
			this.gridEngine.move(this.playerId, 'up-right');
		} else if (
			(cursors.right.isDown || wasd['D'].isDown) &&
			(cursors.down.isDown || wasd['S'].isDown)
		) {
			this.gridEngine.move(this.playerId, 'down-right');
		} else if (cursors.left.isDown || wasd['A'].isDown) {
			this.gridEngine.move(this.playerId, 'left');
		} else if (cursors.right.isDown || wasd['D'].isDown) {
			this.gridEngine.move(this.playerId, 'right');
		} else if (cursors.up.isDown || wasd['W'].isDown) {
			this.gridEngine.move(this.playerId, 'up');
		} else if (cursors.down.isDown || wasd['S'].isDown) {
			this.gridEngine.move(this.playerId, 'down');
		}

		this.checkForNearbyObjects();
	}
}
