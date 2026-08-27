import { render } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import App from './app';

// Phaser opens a real canvas as soon as a Game is constructed, and jsdom's
// getContext() returns null, so an unmocked render dies inside Phaser instead
// of testing anything this app owns. Only the Game constructor is replaced --
// the scenes still extend the real Phaser classes, which import fine.
const destroy = vi.fn();
vi.mock('phaser', async (importOriginal) => {
	const actual = (await importOriginal()) as { default: Record<string, unknown> };
	const Game = class {
		destroy = destroy;
	};
	return { ...actual, Game, default: { ...actual.default, Game } };
});

describe('App', () => {
	it('mounts a container for the game and tears it down', () => {
		const { baseElement, unmount } = render(<App />);

		expect(baseElement.querySelector('div')).toBeTruthy();

		unmount();
		expect(destroy).toHaveBeenCalledWith(true);
	});
});
