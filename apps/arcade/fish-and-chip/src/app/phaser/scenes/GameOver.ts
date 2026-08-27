import { Scene } from 'phaser';

import { highScores, recordRun, type ScoreEntry } from './data/score';

export class GameOver extends Scene {
  
  score = 0;
  wpm = 0;
  scores: ScoreEntry[] = [];

  constructor() {
    super('GameOver');
  }

  init(data: { score: number; wpm: number; }) {
    this.score = data.score;
    this.wpm = data.wpm;

    // The run is banked here, in the one place that knows it just ended, so
    // the town's total and the high score table cannot disagree.
    recordRun({ score: this.score, wpm: this.wpm });
    this.scores = highScores.get();
  }

  create() {
    this.add.image(480, 480, 'background').setScale(1.4, 1.4);

    this.add.text(480, 100, `Game Over\nScore: ${this.score}\nWPM: ${this.wpm}`, {
      fontFamily: 'Arial Black', fontSize: 38, color: '#ffffff',
      stroke: '#000000', strokeThickness: 8,
      align: 'center'
    }).setOrigin(0.5);

    this.add.text(480, 225, 'High Scores', {
      fontFamily: 'Arial Black', fontSize: 64, color: '#ffffff',
      stroke: '#000000', strokeThickness: 8,
      align: 'center'
    }).setOrigin(0.5);

    this.scores.forEach((score: ScoreEntry, index: number) => {
      this.add.text(480, 300 + (index * 50), `${index + 1}. Score: ${score.score} - WPM: ${score.wpm}`, {
        fontFamily: 'Arial Black', fontSize: 38, color: '#ffffff',
        stroke: '#000000', strokeThickness: 8,
        align: 'center'
      }).setOrigin(0.5);
    });

    const retryMenuButtonText = this.add.text(200, 600, 'Retry', {
      fontFamily: 'Arial Black', fontSize: 40, color: '#ffffff',
      stroke: '#000000', strokeThickness: 6,
    }).setInteractive({ useHandCursor: true });

    const mainMenuButtonText = this.add.text(500, 600, 'Go Back To Town', {
      fontFamily: 'Arial Black', fontSize: 40, color: '#ffffff',
      stroke: '#000000', strokeThickness: 6,
    }).setInteractive({ useHandCursor: true });

    retryMenuButtonText.on('pointerdown', () => {
      this.retry();
    });

    mainMenuButtonText.on('pointerdown', () => {
      this.mainMenu();
    });

    this.add.text(480, 700, 'Press Shift or R to Retry', {
      fontFamily: 'Arial Black', fontSize: 32, color: '#ffffff',
      stroke: '#000000', strokeThickness: 6,
      align: 'center'
    }).setOrigin(0.5);

    // Attach the keydown event listener only once

    if (this.input && this.input.keyboard) {
    this.input.keyboard.on('keydown', this.handleKeyDown, this);
    }
  }

  handleKeyDown(event: { key: string; }) {
    const key = event.key.toUpperCase();
    if (key === 'SHIFT' || key === 'R') {
      this.retry();
    }
  }

  retry() {
    this.scene.start('FishChipScene');
  }

  mainMenu() {
    this.scene.start('TownScene');
  }




}
