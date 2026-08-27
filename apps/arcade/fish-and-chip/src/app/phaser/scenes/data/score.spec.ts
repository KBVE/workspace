import { beforeEach, describe, expect, it } from 'vitest';

import {
	HIGH_SCORE_COUNT,
	decodeHighScores,
	decodeTotalFish,
	highScores,
	recordRun,
	totalFish,
} from './score';

describe('score store', () => {
	// Reset through the atoms, not localStorage: nanostores falls back to memory
	// when no storage is present, and Node 26 ships an inert `localStorage`
	// global that shadows jsdom's, so touching it directly fails under the
	// toolchain node while passing on an older one.
	beforeEach(() => {
		totalFish.set(0);
		highScores.set([]);
	});

	it('adds each run to the running fish total', () => {
		recordRun({ score: 3, wpm: 40 });
		recordRun({ score: 4, wpm: 55 });

		expect(totalFish.get()).toBe(7);
	});

	it('keeps the best runs first and drops the rest', () => {
		for (let score = 1; score <= HIGH_SCORE_COUNT + 3; score++) {
			recordRun({ score, wpm: score * 10 });
		}

		const kept = highScores.get();
		expect(kept).toHaveLength(HIGH_SCORE_COUNT);
		expect(kept.map((entry) => entry.score)).toEqual([8, 7, 6, 5, 4]);
	});

	// The decoders are tested directly rather than through the atoms: nanostores
	// only reads storage once something subscribes, so asserting on get() after
	// writing junk passes whether or not the fallback works.
	it('decodes a stored total, and falls back on anything else', () => {
		expect(decodeTotalFish('12')).toBe(12);
		expect(decodeTotalFish('not json')).toBe(0);
		expect(decodeTotalFish('"12"')).toBe(0);
		expect(decodeTotalFish('null')).toBe(0);
	});

	it('decodes a stored table, and falls back on anything else', () => {
		expect(decodeHighScores('[{"score":2,"wpm":30}]')).toEqual([{ score: 2, wpm: 30 }]);
		expect(decodeHighScores('{"score":1}')).toEqual([]);
		expect(decodeHighScores('[{"score":"2"}]')).toEqual([]);
		expect(decodeHighScores('oops')).toEqual([]);
	});
});
