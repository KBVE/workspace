import GridEngine from 'grid-engine';
import Phaser from 'phaser';
import { useEffect, useRef } from 'react';

import { CreditsScene } from './scenes/CreditsScene';
import { FishChipScene } from './scenes/FishChipScene';
import { FishScene } from './scenes/FishScene';
import { GameOver } from './scenes/GameOver';
import { Preloader } from './scenes/Preloader';
import { TownScene } from './scenes/TownScene';

export function Game() {
	const gameRef = useRef<HTMLDivElement>(null);

	useEffect(() => {
		const parent = gameRef.current;
		if (!parent) return;

		const game = new Phaser.Game({
			title: 'TownEngine',
			type: Phaser.AUTO,
			parent,
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
			scene: [Preloader, TownScene, FishChipScene, GameOver, FishScene, CreditsScene],
			input: {
				mouse: { preventDefaultWheel: false },
				touch: { capture: false },
			},
		});

		// StrictMode mounts effects twice in development; without this the
		// second mount leaves an orphaned canvas and a running game loop.
		return () => game.destroy(true);
	}, []);

	return <div ref={gameRef} />;
}

export default Game;
