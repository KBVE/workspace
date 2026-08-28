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
        // bg.ogg is not here: see startMusic(). It is 1.1MB, over half the
        // boot payload, and nothing on the title screen needs it to draw.
        this.load.image('creditsBg', 'game/credits_bg.png');
        this.load.audio('type', 'game/type.mp3');
        this.load.spritesheet('fishing', 'game/animate.png', { frameWidth: 800, frameHeight: 600 });
        this.load.image('fish', 'game/letter_logo.png');
        this.load.image('background', 'game/scaled_fish_menu_minigame.webp');
        //this.load.image('fish', 'game/letter_logo.png');

        //  Cloud TileSet -> cloud_tileset.png
        this.load.image("tiles", "game/desert_tileset_1.png");
        // The authored map itself is not loaded. TownScene generates its own
        // and registers it in the tilemap cache, so shipping cloud_city.json
        // meant downloading 352KB on every boot to never read it. It lives in
        // tools/source now, where the prefab and collision extractors read it.
        // /assets/img/fishchip/characters_filter.png
        this.load.spritesheet("player", "game/chip_charactersheet_warmer.png", {
            frameWidth: 52,
            frameHeight: 72,
        });

    }

    create() {
        this.startMusic();
        this.add.image(480, 480, 'mainBg').setScale(0.1);

        this.mainMenuButtonImage = this.add.image(480, 480, 'scroll').setAlpha(0.9).setScale(0.7, 0.2).setInteractive({ useHandCursor: true });

        this.mainMenuButtonText = this.add.text(480, 480, 'Start Game', {
            fontFamily: 'Arial Black', fontSize: 50, color: '#ffffff', stroke: '#000000', strokeThickness: 6,
        }).setOrigin(0.5).setInteractive({ useHandCursor: true });
        this.mainMenuButtonText.on('pointerdown', () => {
            this.scene.start('TownScene');
        }, this);
    }

    /**
     * Fetches the music after the menu is on screen, then plays it.
     *
     * The track is the single largest asset in the game, and preloading it put
     * it in front of the title screen: every player waited on a megabyte of
     * ogg to see a button. A second load pass costs nothing on screen -- the
     * music simply arrives a moment later -- and the scene is already
     * interactive while it downloads.
     */
    private startMusic() {
        if (this.sound.get('music')?.isPlaying) return;
        if (this.cache.audio.exists('music')) {
            this.sound.add('music', { loop: true, volume: 0.1 }).play();
            return;
        }

        this.load.audio('music', 'game/bg.ogg');
        this.load.once('complete', () => {
            // The scene can be gone by the time a slow download lands.
            if (!this.scene.isActive() || this.sound.get('music')?.isPlaying) return;
            this.sound.add('music', { loop: true, volume: 0.1 }).play();
        });
        this.load.start();
    }
}