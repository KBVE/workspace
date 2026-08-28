import { PhaserGame } from '@kbve/laser/phaser';
import GridEngine from 'grid-engine';
import Phaser from 'phaser';
import { useCallback, useMemo } from 'react';

import { CreditsScene } from './scenes/CreditsScene';
import { FishChipScene } from './scenes/FishChipScene';
import { FishScene } from './scenes/FishScene';
import { GameOver } from './scenes/GameOver';
import { MarketScene } from './scenes/MarketScene';
import { Preloader } from './scenes/Preloader';
import { TownScene } from './scenes/TownScene';

declare global {
	interface Window {
		// Handle for the e2e suite. Phaser draws to a canvas, so there is no DOM
		// for a test to assert against; this is the seam it reads scene state and
		// asset caches through. TownScene exposes the grid engine the same way.
		__FISHCHIP_GAME__?: Phaser.Game;
	}
}

// The canvas is mounted by @kbve/laser, which exists to be this layer. Booting
// Phaser inside an effect by hand is a few lines until StrictMode's double
// mount destroys the game on the first cleanup and leaves the second mount
// holding an orphaned canvas; laser defers the destroy by a tick so a remount
// cancels it and reattaches the existing canvas instead.
export function Game() {
	const config = useMemo(
		() => ({
			transparent: true,
			width: 800,
			height: 600,
			render: { antialias: false },
			scale: {
				mode: Phaser.Scale.RESIZE,
				min: { width: 1024, height: 768 },
				max: { width: 1600, height: 1200 },
				zoom: 1,
			},
			physics: {
				default: 'arcade',
				// Top-down movement, so gravity stays at zero on both axes.
				arcade: { gravity: { x: 0, y: 0 }, debug: false },
			},
			plugins: {
				scene: [{ key: 'gridEngine', plugin: GridEngine, mapping: 'gridEngine' }],
			},
			scenes: [Preloader, TownScene, FishChipScene, GameOver, FishScene, CreditsScene, MarketScene],
			input: {
				mouse: { preventDefaultWheel: false },
				touch: { capture: false },
			},
		}),
		[],
	);

	const onReady = useCallback((game: Phaser.Game) => {
		window.__FISHCHIP_GAME__ = game;
	}, []);

	const onDestroy = useCallback(() => {
		delete window.__FISHCHIP_GAME__;
	}, []);

	return <PhaserGame config={config} onReady={onReady} onDestroy={onDestroy} />;
}

export default Game;
