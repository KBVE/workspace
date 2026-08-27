
import { Direction, type GridEngine, type GridEngineConfig } from 'grid-engine';
import { Scene } from 'phaser';
import Phaser from 'phaser';

import { totalFish } from './data/score';
import { PLAYER_ID, TOWN_CHARACTERS } from './data/town-characters';

declare global {
  interface Window {
    __GRID_ENGINE__?: GridEngine;
  }
}

class ExtendedSprite extends Phaser.GameObjects.Sprite {
  textBubble?: Phaser.GameObjects.Container; // Assuming it's a Container
}


export class TownScene extends Scene {
  
  npcSprite: ExtendedSprite | undefined;
  fishNpcSprite: ExtendedSprite| undefined;
  cursor: Phaser.Types.Input.Keyboard.CursorKeys | undefined;
  // Keys are registered once in create(). The jam build called
  // createCursorKeys() and addKey() from update(), i.e. on every frame.
  keys: Record<string, Phaser.Input.Keyboard.Key> | undefined;
  // Injected by the grid-engine scene plugin under the `gridEngine` mapping
  // declared in game.tsx, so it exists from create() onwards.
  gridEngine!: GridEngine;
  
  

  constructor() {
    super({ key: 'TownScene' });
  }

  create() {

    const fishCaught = totalFish.get();
    
    const cloudCityTilemap = this.make.tilemap({ key: "cloud-city-map" });
    cloudCityTilemap.addTilesetImage("Cloud City", "tiles");
    for (let i = 0; i < cloudCityTilemap.layers.length; i++) {
      const layer = cloudCityTilemap.createLayer(i, "Cloud City", 0, 0);
      if (layer) {
        layer.scale = 3;
      } else {
        console.error(`Layer ${i} could not be created.`);
      }
    }
    const playerSprite = this.add.sprite(0, 0, "player");
    playerSprite.scale = 1.5;

    this.npcSprite = this.add.sprite(0, 0, "player");
    this.npcSprite.scale = 1.5;

    // this.npcSprite = this.add.sprite(0, 0, "player");
    // this.npcSprite.scale = 1.5;

    this.fishNpcSprite = this.add.sprite(0, 0, "player");
    this.fishNpcSprite.scale = 1.5;

    this.cameras.main.startFollow(playerSprite, true);
    this.cameras.main.setFollowOffset(
      -playerSprite.width,
      -playerSprite.height,
    );

    // Sprites live here, the rest of each character lives in
    // data/town-characters.ts, where a test can reach it.
    const sprites: Record<string, Phaser.GameObjects.Sprite> = {
      player: playerSprite,
      npc: this.npcSprite,
      fishNpc: this.fishNpcSprite,
    };

    const gridEngineConfig: GridEngineConfig = {
      characters: TOWN_CHARACTERS.map((character) => ({
        ...character,
        sprite: sprites[character.id],
      })),
    };

    this.gridEngine.create(cloudCityTilemap, gridEngineConfig);

    this.createTextBubble(this.npcSprite, "Enter the sand pit to start fishing! Go near it and press F!");
    this.createTextBubble(this.fishNpcSprite, `You have caught a total of ${fishCaught} fish!`);
    this.gridEngine.moveRandomly("npc", 1500, 3);

    this.gridEngine.moveRandomly("fishNpc", 1500, 3);
    window.__GRID_ENGINE__ = this.gridEngine;

    if (this.input.keyboard) {
      this.cursor = this.input.keyboard.createCursorKeys();
      this.keys = this.input.keyboard.addKeys('W,A,S,D,F') as Record<
        string,
        Phaser.Input.Keyboard.Key
      >;
    }
  }

  createTextBubble(sprite: ExtendedSprite, text: string | string[]) {
    const bubbleWidth = 200;
    const bubbleHeight = 60;
    const bubblePadding = 10;

    const bubble = this.add.graphics();
    bubble.fillStyle(0xffffff, 1);
    bubble.fillRoundedRect(0, 0, bubbleWidth, bubbleHeight, 16);
    bubble.setDepth(99);

    const content = this.add.text(100, 30, text, { fontFamily: 'Arial', fontSize: 16, color: '#000000' });
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
    if(container)
    {
    container.x = sprite.x;
    container.y = sprite.y - sprite.height - container.height / 2;
    }
  }

  update() {
    const cursors = this.cursor;
    const keys = this.keys;

    function isWithinRangeOfWell(point: { x: number; y: number; }) {
      // Define the bounds
      const xMin = 2, xMax = 5;
      const yMin = 10, yMax = 14;

      // Check if the point is within the bounds
      return point.x >= xMin && point.x <= xMax &&
        point.y >= yMin && point.y <= yMax;
    }

    function isWithinRangeOfSign(point: { x: number; y: number; }) {
      // Define the bounds
      const xMin = 2, xMax = 5;
      const yMin = 2, yMax = 5;

      // Check if the point is within the bounds
      return point.x >= xMin && point.x <= xMax &&
        point.y >= yMin && point.y <= yMax;
    }

    function isWithinRangeOfBuilding(point: { x: number; y: number; }) {
      // Define the bounds
      const xMin = 13, xMax = 13;
      const yMin = 6, yMax = 7;

      // Check if the point is within the bounds
      return point.x >= xMin && point.x <= xMax &&
        point.y >= yMin && point.y <= yMax;
    }

    function isWithinRangeOfTombstone(point: { x: number; y: number; }) {
      //  Define the bounds
      const xMin = 7, xMax = 10
      const yMin = 9, yMax = 10
      // Check if the point is within the bounds
      return point.x >= xMin && point.x <= xMax &&
        point.y >= yMin && point.y <= yMax;
    }



    if (keys?.F.isDown) {
      const position = this.gridEngine.getPosition(PLAYER_ID);

      const withinRangeOfWell = isWithinRangeOfWell(position);
      if (withinRangeOfWell) {
        this.scene.start('FishChipScene');
      }

      const withinRangeOfSign = isWithinRangeOfSign(position);
      if (withinRangeOfSign) {
        this.scene.start('CreditsScene');
      }

      const withinRangeOfBuilding = isWithinRangeOfBuilding(position);
      if (withinRangeOfBuilding) {
        console.log('Enter the Building?');
      }

      const withinRangeOfTombstone = isWithinRangeOfTombstone(position);
      if (withinRangeOfTombstone) {
        console.log('Samson Statue!');
      }
    }
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

    // Update the speech bubble positions for both NPCs
    if (this.npcSprite && this.npcSprite.textBubble) {
      this.updateTextBubblePosition(this.npcSprite);
    }
    if (this.fishNpcSprite && this.fishNpcSprite.textBubble) {
      this.updateTextBubblePosition(this.fishNpcSprite);
    }
  }
}
