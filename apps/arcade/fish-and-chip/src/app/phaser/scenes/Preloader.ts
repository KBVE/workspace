import { Scene } from 'phaser';

// Every asset is served from this build's own public/assets, not from a CDN.
// The original jam build pulled them from kbve.com and a Discord attachment;
// both went away, which took the game with them. Paths are relative on purpose
// -- itch serves an upload from a hashed subdirectory, so a leading slash 404s
// there.

export class Preloader extends Scene {
    mainMenuButtonImage: Phaser.GameObjects.Image | undefined;
    mainMenuButtonText: Phaser.GameObjects.Text | undefined;
    constructor() {
        super('Preloader');
    }

    preload() {
        this.load.image('mainBg', 'game/main_bg.webp'); // Ensure you have a correct path to your logo image
        this.load.image('scroll', 'game/scroll.webp');
        this.load.audio('music', 'game/bg.ogg');
        this.load.image('creditsBg', 'game/credits_bg.png');
        this.load.audio('type', 'game/type.mp3');
        this.load.spritesheet('fishing', 'game/animate.png', { frameWidth: 800, frameHeight: 600 });
        this.load.image('fish', 'game/letter_logo.png');
        this.load.image('background', 'game/scaled_fish_menu_minigame.webp');
        //this.load.image('fish', 'game/letter_logo.png');

        //  Cloud TileSet -> cloud_tileset.png
        this.load.image("tiles", "game/desert_tileset_1.png");
        this.load.tilemapTiledJSON(
            "cloud-city-map",
            "game/cloud_city.json",
        );
        // /assets/img/fishchip/characters_filter.png
        this.load.spritesheet("player", "game/chip_charactersheet_warmer.png", {
            frameWidth: 52,
            frameHeight: 72,
        });

    }

    create() {
        if (!this.sound.get('music')?.isPlaying) {
            this.sound.add('music', { loop: true, volume: 0.1 }).play();
        }
        this.add.image(480, 480, 'mainBg').setScale(0.1);

        this.mainMenuButtonImage = this.add.image(480, 480, 'scroll').setAlpha(0.9).setScale(0.7, 0.2).setInteractive({ useHandCursor: true });

        this.mainMenuButtonText = this.add.text(480, 480, 'Start Game', {
            fontFamily: 'Arial Black', fontSize: 50, color: '#ffffff', stroke: '#000000', strokeThickness: 6,
        }).setOrigin(0.5).setInteractive({ useHandCursor: true });
        this.mainMenuButtonText.on('pointerdown', () => {
            this.scene.start('TownScene');
        }, this);
    }
}