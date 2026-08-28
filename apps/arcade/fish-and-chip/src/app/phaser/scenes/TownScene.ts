import { Direction, type GridEngine, type GridEngineConfig } from 'grid-engine';
import { Scene } from 'phaser';
import Phaser from 'phaser';

import { generateTown, toTiledJSON, type Position, type TownMap } from '../world/generate';
import { totalFish } from './data/score';
import { PLAYER_ID, townCharacters } from './data/town-characters';

declare global {
  interface Window {
    __GRID_ENGINE__?: GridEngine;
    /** The town this run generated. Read by the e2e suite. */
    __TOWN__?: TownMap;
    /**
     * Milliseconds of Phaser's clock this scene has stepped through. Read by
     * the e2e suite, which cannot time a walk with a stopwatch: see update().
     */
    __TOWN_ELAPSED_MS__?: number;
  }
}

class ExtendedSprite extends Phaser.GameObjects.Sprite {
  textBubble?: Phaser.GameObjects.Container;
}

/** Tilemap cache key the generated map is registered under. */
const MAP_KEY = 'generated-town';

/** How close the player has to stand to a landmark for F to do anything. */
const INTERACT_RANGE = 1;

export class TownScene extends Scene {
  town!: TownMap;
  npcSprites: ExtendedSprite[] = [];
  cursor: Phaser.Types.Input.Keyboard.CursorKeys | undefined;
  // Keys are registered once in create(). The jam build called
  // createCursorKeys() and addKey() from update(), i.e. on every frame.
  keys: Record<string, Phaser.Input.Keyboard.Key> | undefined;
  // Injected by the grid-engine scene plugin under the `gridEngine` mapping
  // declared in game.tsx, so it exists from create() onwards.
  gridEngine!: GridEngine;
  /** Set while a landmark message is on screen. */
  private notice?: Phaser.GameObjects.Container;

  constructor() {
    super({ key: 'TownScene' });
  }

  /**
   * The seed for this run. `?seed=` pins it, which is what makes a bad town
   * reportable -- otherwise every run is a different map and any bug in one is
   * a bug nobody else can reach.
   */
  private seed(): number {
    const requested = new URLSearchParams(window.location.search).get('seed');
    const parsed = Number(requested);
    if (requested !== null && requested !== '' && Number.isFinite(parsed)) return parsed;
    return Math.floor(Math.random() * 2 ** 31);
  }

  create() {
    const fishCaught = totalFish.get();

    this.town = generateTown({ seed: this.seed() });
    window.__TOWN__ = this.town;

    // Registered into the cache rather than loaded from a file: the map does
    // not exist until this line, so Preloader has nothing it could fetch.
    this.cache.tilemap.remove(MAP_KEY);
    this.cache.tilemap.add(MAP_KEY, {
      format: Phaser.Tilemaps.Formats.TILED_JSON,
      data: toTiledJSON(this.town),
    });

    const tilemap = this.make.tilemap({ key: MAP_KEY });
    tilemap.addTilesetImage('Cloud City', 'tiles');
    for (let i = 0; i < tilemap.layers.length; i++) {
      const layer = tilemap.createLayer(i, 'Cloud City', 0, 0);
      if (layer) {
        layer.scale = 3;
      } else {
        console.error(`Layer ${i} could not be created.`);
      }
    }

    const characters = townCharacters(this.town);
    const sprites = new Map<string, ExtendedSprite>();
    this.npcSprites = [];

    for (const character of characters) {
      const sprite = this.add.sprite(0, 0, 'player') as ExtendedSprite;
      sprite.scale = 1.5;
      sprites.set(character.id, sprite);
      if (character.id !== PLAYER_ID) this.npcSprites.push(sprite);
    }

    const playerSprite = sprites.get(PLAYER_ID)!;
    this.cameras.main.startFollow(playerSprite, true);
    this.cameras.main.setFollowOffset(-playerSprite.width, -playerSprite.height);

    const gridEngineConfig: GridEngineConfig = {
      characters: characters.map((character) => ({
        ...character,
        sprite: sprites.get(character.id),
      })),
    };

    this.gridEngine.create(tilemap, gridEngineConfig);

    const greetings = [
      'Enter the sand pit to start fishing! Go near it and press F!',
      `You have caught a total of ${fishCaught} fish!`,
    ];
    characters
      .filter((character) => character.id !== PLAYER_ID)
      .forEach((character, position) => {
        const sprite = sprites.get(character.id);
        if (sprite) this.createTextBubble(sprite, greetings[position] ?? greetings[0]);
        this.gridEngine.moveRandomly(character.id, 1500, 3);
      });

    this.labelLandmarks(tilemap.tileWidth * 3);

    window.__GRID_ENGINE__ = this.gridEngine;

    if (this.input.keyboard) {
      this.cursor = this.input.keyboard.createCursorKeys();
      this.keys = this.input.keyboard.addKeys('W,A,S,D,F') as Record<
        string,
        Phaser.Input.Keyboard.Key
      >;
      // Edge triggered. update() runs every frame, and a held F would restart
      // the fishing scene dozens of times a second.
      this.keys.F.on('down', () => this.interact());
    }
  }

  /**
   * A caption over each landmark. One 16px tile in a town this size is not
   * findable by looking, and a hotspot the player never finds is the same as
   * one that does nothing -- which is what the building and the tombstone were.
   */
  private labelLandmarks(tileSize: number) {
    const captions: Record<string, string> = {
      fishingPit: 'Sand Pit  [F]',
      sign: 'Sign  [F]',
      tombstone: 'Grave  [F]',
      building: 'Market  [F]',
    };

    for (const [name, spot] of Object.entries(this.town.landmarks)) {
      const label = this.add.text(
        spot.x * tileSize + tileSize / 2,
        spot.y * tileSize - tileSize / 2,
        captions[name] ?? name,
        {
          fontFamily: 'Arial',
          fontSize: 18,
          color: '#ffffff',
          stroke: '#000000',
          strokeThickness: 5,
        },
      );
      label.setOrigin(0.5);
      label.setDepth(150);
    }
  }

  /**
   * The nearest landmark the player is standing on or beside, if any.
   *
   * Nearest, not first: two landmarks can end up within a tile of each other,
   * and returning whichever came first in the object meant standing at the sign
   * opened the fishing minigame.
   */
  private landmarkUnderPlayer(): keyof TownMap['landmarks'] | null {
    const player = this.gridEngine.getPosition(PLAYER_ID);
    const distance = (spot: Position) =>
      Math.abs(spot.x - player.x) + Math.abs(spot.y - player.y);

    let closest: { name: keyof TownMap['landmarks']; away: number } | null = null;
    for (const [name, spot] of Object.entries(this.town.landmarks)) {
      const away = distance(spot);
      if (away > INTERACT_RANGE) continue;
      if (!closest || away < closest.away) {
        closest = { name: name as keyof TownMap['landmarks'], away };
      }
    }
    return closest?.name ?? null;
  }

  /**
   * F. Every landmark does something now: the building and the tombstone used
   * to reach a console.log, which from the player's side is a hotspot that does
   * nothing at all.
   */
  private interact() {
    if (this.notice) {
      this.notice.destroy();
      this.notice = undefined;
      return;
    }

    switch (this.landmarkUnderPlayer()) {
      case 'fishingPit':
        this.scene.start('FishChipScene');
        return;
      case 'sign':
        this.scene.start('CreditsScene');
        return;
      case 'building':
        this.scene.start('MarketScene');
        return;
      case 'tombstone':
        this.showNotice(
          'Here lies Samson.\nHe caught the biggest fish in the bay\nand never told anyone where.',
        );
        return;
      default:
        return;
    }
  }

  /** A dismissable panel for a landmark that does not warrant its own scene. */
  private showNotice(text: string) {
    const width = 460;
    const height = 170;

    const panel = this.add.graphics();
    panel.fillStyle(0x000000, 0.82);
    panel.fillRoundedRect(-width / 2, -height / 2, width, height, 16);

    const body = this.add.text(0, -14, text, {
      fontFamily: 'Arial',
      fontSize: 20,
      color: '#ffffff',
      align: 'center',
    });
    body.setOrigin(0.5);

    const hint = this.add.text(0, height / 2 - 30, 'Press F to close', {
      fontFamily: 'Arial',
      fontSize: 16,
      color: '#c2b280',
    });
    hint.setOrigin(0.5);

    const camera = this.cameras.main;
    this.notice = this.add.container(camera.width / 2, camera.height / 2, [panel, body, hint]);
    this.notice.setDepth(200);
    // Pinned to the camera, not the world: the player can still walk while it
    // is open, and a panel that slides off screen is worse than no panel.
    this.notice.setScrollFactor(0);
  }

  createTextBubble(sprite: ExtendedSprite, text: string | string[]) {
    const bubbleWidth = 200;
    const bubbleHeight = 60;
    const bubblePadding = 10;

    const bubble = this.add.graphics();
    bubble.fillStyle(0xffffff, 1);
    bubble.fillRoundedRect(0, 0, bubbleWidth, bubbleHeight, 16);
    bubble.setDepth(99);

    const content = this.add.text(100, 30, text, {
      fontFamily: 'Arial',
      fontSize: 16,
      color: '#000000',
    });
    content.setOrigin(0.5);
    content.setWordWrapWidth(bubbleWidth - bubblePadding * 2);
    content.setDepth(100);

    const container = this.add.container(0, 0, [bubble, content]);
    container.setDepth(100);

    sprite.textBubble = container;
    this.updateTextBubblePosition(sprite);
  }

  updateTextBubblePosition(sprite: ExtendedSprite) {
    const container = sprite.textBubble;
    if (container) {
      container.x = sprite.x;
      container.y = sprite.y - sprite.height - container.height / 2;
    }
  }

  update(_time: number, delta: number) {
    // grid-engine moves characters by frame delta, not by wall clock, and the
    // two are not the same number: a CI runner rendering in software delivers
    // roughly a third of real time as game time. Publishing the sum lets a
    // test measure tiles per game-second, which is the speed the player is
    // actually configured with, instead of measuring how fast the runner is.
    window.__TOWN_ELAPSED_MS__ = (window.__TOWN_ELAPSED_MS__ ?? 0) + delta;

    const cursors = this.cursor;
    const keys = this.keys;

    // Arrow keys and WASD both drive the player.
    if (cursors?.left.isDown || keys?.A.isDown) {
      this.gridEngine.move(PLAYER_ID, Direction.LEFT);
    } else if (cursors?.right.isDown || keys?.D.isDown) {
      this.gridEngine.move(PLAYER_ID, Direction.RIGHT);
    } else if (cursors?.up.isDown || keys?.W.isDown) {
      this.gridEngine.move(PLAYER_ID, Direction.UP);
    } else if (cursors?.down.isDown || keys?.S.isDown) {
      this.gridEngine.move(PLAYER_ID, Direction.DOWN);
    }

    for (const sprite of this.npcSprites) {
      if (sprite.textBubble) this.updateTextBubblePosition(sprite);
    }
  }
}
