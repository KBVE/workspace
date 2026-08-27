import { persistentAtom } from '@nanostores/persistent';

export type ScoreEntry = {
	score: number;
	wpm: number;
};

export const HIGH_SCORE_COUNT = 5;

const isScoreEntry = (value: unknown): value is ScoreEntry =>
	typeof value === 'object' &&
	value !== null &&
	typeof (value as ScoreEntry).score === 'number' &&
	typeof (value as ScoreEntry).wpm === 'number';

// persistentAtom hands back whatever is in localStorage, which a player can
// edit and an older build may have written in another shape. Every decode
// falls back to the default rather than throwing: a corrupt score is worth
// losing, a scene that dies on boot is not.
const decoder =
	<T>(fallback: T, isValid: (value: unknown) => value is T) =>
	(raw: string): T => {
		try {
			const parsed: unknown = JSON.parse(raw);
			return isValid(parsed) ? parsed : fallback;
		} catch {
			return fallback;
		}
	};

export const decodeTotalFish = decoder<number>(
	0,
	(value): value is number => typeof value === 'number' && Number.isFinite(value),
);

export const decodeHighScores = decoder<ScoreEntry[]>(
	[],
	(value): value is ScoreEntry[] => Array.isArray(value) && value.every(isScoreEntry),
);

const json = <T>(decode: (raw: string) => T) => ({ encode: JSON.stringify, decode });

/** Total fish caught across every run. TownScene's NPC reads this. */
export const totalFish = persistentAtom<number>('fishchip:totalFish', 0, json(decodeTotalFish));

/** Best runs, highest score first, capped at HIGH_SCORE_COUNT. */
export const highScores = persistentAtom<ScoreEntry[]>('fishchip:highScores', [], json(decodeHighScores));

/**
 * Records one finished run. This is the only writer: GameOver used to keep its
 * own `scores` and `totalScore` keys in localStorage while TownScene read a
 * store nothing wrote, so the town NPC always reported zero fish caught.
 */
export function recordRun(entry: ScoreEntry): void {
	totalFish.set(totalFish.get() + entry.score);
	highScores.set(
		[...highScores.get(), entry].sort((a, b) => b.score - a.score).slice(0, HIGH_SCORE_COUNT),
	);
}
