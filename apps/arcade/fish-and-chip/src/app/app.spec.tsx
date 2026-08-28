import { render } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import App from './app';

// Phaser opens a real canvas as soon as a Game is constructed, and jsdom's
// getContext() returns null, so an unmocked render dies inside Phaser instead
// of testing anything this app owns. Only the Game constructor is replaced --
// the scenes still extend the real Phaser classes, which import fine.
//
// The stub has to answer what @kbve/laser's PhaserGame asks of a game: it
// subscribes to `events` for the ready signal and reattaches `canvas` across a
// StrictMode remount.
const destroy = vi.fn();
vi.mock('phaser', async (importOriginal) => {
	const actual = (await importOriginal()) as { default: Record<string, unknown> };
	const Game = class {
		destroy = destroy;
		events = { once: vi.fn() };
		isBooted = false;
		canvas = document.createElement('canvas');
	};
	return { ...actual, Game, default: { ...actual.default, Game } };
});

describe('App', () => {
	it('mounts a container for the game and tears it down', async () => {
		const { baseElement, unmount } = render(<App />);

		expect(baseElement.querySelector('div')).toBeTruthy();

		unmount();

		// laser defers the destroy by a tick so that StrictMode's mount ->
		// cleanup -> mount can cancel it and keep the canvas. A real unmount
		// lets the timer fire, which is what this waits for.
		expect(destroy).not.toHaveBeenCalled();
		await new Promise((resolve) => setTimeout(resolve, 0));
		expect(destroy).toHaveBeenCalledWith(true);
	});
});
