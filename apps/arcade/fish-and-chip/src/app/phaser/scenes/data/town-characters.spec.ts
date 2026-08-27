import { ArrayTilemap, Direction, GridEngineHeadless } from 'grid-engine';
import { beforeEach, describe, expect, it } from 'vitest';

import { PLAYER_ID, TOWN_CHARACTERS } from './town-characters';

// grid-engine's headless engine takes the same character config the Phaser
// plugin does, so this checks the config against the real 2.x runtime without a
// canvas: ids resolve, start positions land, and a Direction actually moves.
const open = (size: number) => ({
	data: Array.from({ length: size }, () => Array.from({ length: size }, () => 0)),
});

describe('town characters', () => {
	let engine: GridEngineHeadless;

	beforeEach(() => {
		engine = new GridEngineHeadless(false);
		engine.create(new ArrayTilemap({ ground: open(20) }), {
			characters: TOWN_CHARACTERS.map(({ walkingAnimationMapping: _row, ...character }) => character),
		});
	});

	it('places every character at its configured start position', () => {
		for (const character of TOWN_CHARACTERS) {
			expect(engine.getPosition(character.id)).toEqual(character.startPosition);
		}
	});

	it('walks the player one tile per direction', () => {
		const start = engine.getPosition(PLAYER_ID);

		engine.move(PLAYER_ID, Direction.LEFT);
		// One tile at the default speed takes 250ms; a single update of that
		// length is enough to land on the next tile rather than between two.
		engine.update(0, 250);

		expect(engine.getPosition(PLAYER_ID)).toEqual({ x: start.x - 1, y: start.y });
	});
});
