import type { CharacterDataHeadless } from 'grid-engine';

import type { TownMap } from '../../world/generate';

// The town's grid-engine characters, minus their sprites. Kept apart from
// TownScene so the ids, spawns, and speeds can be exercised against a real
// GridEngineHeadless in a test -- the scene itself needs a canvas, so nothing
// in it is reachable from a unit test.
//
// walkingAnimationMapping is a row index into the shared character sheet: each
// character is a 3x4 block of 52x72 frames, so a number is enough and no
// explicit frame mapping is needed.
export type TownCharacter = CharacterDataHeadless & {
	walkingAnimationMapping: number;
};

export const PLAYER_ID = 'player';

/**
 * Tiles per second. grid-engine's own default is 4, which is what the player
 * walked at while the map was 20x20; on a bigger town it reads as wading.
 * Twice the default overshot into skating, so this sits between the two: a
 * 34-wide town crosses in about six seconds. The townsfolk stay slow on
 * purpose -- they are meant to amble.
 */
export const PLAYER_SPEED = 6;

/** The wandering townsfolk, in the order the generator's npc spawns fill them. */
export const NPC_IDS = ['npc', 'fishNpc'] as const;

const ANIMATION_ROW: Record<string, number> = {
	player: 6,
	npc: 5,
	fishNpc: 4,
};

/**
 * Builds the character list for a generated town. Positions come from the map
 * rather than from constants -- they used to be fixed coordinates into
 * cloud_city.json, which is exactly what stops a town from being generated.
 *
 * An npc with no spawn left is dropped rather than placed somewhere arbitrary:
 * a townsperson standing inside a rock is worse than one fewer townsperson.
 */
export function townCharacters(map: TownMap): TownCharacter[] {
	const characters: TownCharacter[] = [
		{
			id: PLAYER_ID,
			walkingAnimationMapping: ANIMATION_ROW.player,
			startPosition: map.playerSpawn,
			speed: PLAYER_SPEED,
		},
	];

	NPC_IDS.forEach((id, position) => {
		const spawn = map.npcSpawns[position];
		if (!spawn) return;
		characters.push({
			id,
			walkingAnimationMapping: ANIMATION_ROW[id],
			startPosition: spawn,
			speed: 3,
		});
	});

	return characters;
}
