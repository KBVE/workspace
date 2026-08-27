import type { CharacterDataHeadless } from 'grid-engine';

// The town's grid-engine characters, minus their sprites. Kept apart from
// TownScene so the ids, start positions, and speeds can be exercised against a
// real GridEngineHeadless in a test -- the scene itself needs a canvas, so
// nothing in it is reachable from a unit test.
//
// walkingAnimationMapping is a row index into the shared character sheet: each
// character is a 3x4 block of 52x72 frames, so a number is enough and no
// explicit frame mapping is needed.
export type TownCharacter = CharacterDataHeadless & {
	walkingAnimationMapping: number;
};

export const TOWN_CHARACTERS: readonly TownCharacter[] = [
	{
		id: 'player',
		walkingAnimationMapping: 6,
		startPosition: { x: 5, y: 12 },
	},
	{
		id: 'npc',
		walkingAnimationMapping: 5,
		startPosition: { x: 4, y: 10 },
		speed: 3,
	},
	{
		id: 'fishNpc',
		walkingAnimationMapping: 4,
		startPosition: { x: 8, y: 14 },
		speed: 3,
	},
];

export const PLAYER_ID = 'player';
