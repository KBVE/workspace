import { Scene } from 'phaser';

import { highScores, totalFish } from './data/score';

// What the building's doorway opens into. It used to be a console.log.
//
// The market reads the two persisted numbers -- fish caught across every run,
// and the best runs -- and puts them somewhere the player can actually see
// them. Before this, `totalFish` was written by GameOver, mentioned once by an
// NPC in passing, and otherwise invisible.
export class MarketScene extends Scene {
	constructor() {
		super({ key: 'MarketScene' });
	}

	create() {
		const caught = totalFish.get();
		const best = highScores.get();

		this.add.image(480, 480, 'background').setScale(1.4, 1.4).setAlpha(0.35);

		this.add
			.text(480, 90, 'The Fish Market', {
				fontFamily: 'Arial Black',
				fontSize: 52,
				color: '#ffffff',
				stroke: '#000000',
				strokeThickness: 8,
			})
			.setOrigin(0.5);

		this.add
			.text(480, 180, `${caught} fish landed, all time`, {
				fontFamily: 'Arial Black',
				fontSize: 30,
				color: '#c2b280',
				stroke: '#000000',
				strokeThickness: 6,
			})
			.setOrigin(0.5);

		// The market's stock is the player's record, so an empty table is a
		// first visit rather than a missing feature -- say so.
		const lines = best.length
			? best.map((entry, place) => `${place + 1}.  ${entry.score} fish  ·  ${entry.wpm} wpm`)
			: ['No catches yet.', 'The pit is west of here.'];

		lines.forEach((line, position) => {
			this.add
				.text(480, 270 + position * 46, line, {
					fontFamily: 'Arial',
					fontSize: 28,
					color: '#ffffff',
					stroke: '#000000',
					strokeThickness: 6,
				})
				.setOrigin(0.5);
		});

		const back = this.add
			.text(480, 620, 'Back to town', {
				fontFamily: 'Arial Black',
				fontSize: 34,
				color: '#ffffff',
				stroke: '#000000',
				strokeThickness: 6,
			})
			.setOrigin(0.5)
			.setInteractive({ useHandCursor: true });

		back.on('pointerdown', () => this.leave());

		this.add
			.text(480, 680, 'or press F', {
				fontFamily: 'Arial',
				fontSize: 20,
				color: '#c2b280',
			})
			.setOrigin(0.5);

		// `once` on keyup first: F is still held from the press that opened the
		// market, and a keydown handler would close it on the same press.
		this.input.keyboard?.once('keyup-F', () => {
			this.input.keyboard?.once('keydown-F', () => this.leave());
		});
	}

	private leave() {
		this.scene.start('TownScene');
	}
}
