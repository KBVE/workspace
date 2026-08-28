import { expect, test, type ConsoleMessage, type Page, type Request } from '@playwright/test';

// What this suite is for: unit tests mock Phaser away, so nothing else in the
// repository proves the game starts. It is a jam-era Phaser 3 game running on
// Phaser 4, loading assets that were 404 until recently, published to a page
// that serves it from a subdirectory. Each of those is a way to ship a build
// that compiles, passes every unit test, and shows a black rectangle.

const ASSET_KEYS = {
	textures: [
		'mainBg',
		'scroll',
		'creditsBg',
		'fishing',
		'fish',
		'background',
		'tiles',
		'player',
	],
	audio: ['music', 'type'],
	tilemaps: ['cloud-city-map'],
};

type Failure = { url: string; reason: string };

/** Console errors and failed requests, collected from the first navigation on. */
function watch(page: Page) {
	const consoleErrors: string[] = [];
	const failed: Failure[] = [];

	page.on('console', (message: ConsoleMessage) => {
		if (message.type() === 'error') consoleErrors.push(message.text());
	});
	page.on('requestfailed', (request: Request) => {
		failed.push({ url: request.url(), reason: request.failure()?.errorText ?? 'unknown' });
	});
	page.on('response', (response) => {
		if (response.status() >= 400) {
			failed.push({ url: response.url(), reason: `HTTP ${response.status()}` });
		}
	});

	return { consoleErrors, failed };
}

/** Waits until Phaser has constructed the game and a scene is running. */
async function booted(page: Page) {
	// Relative, not '/index.html': a leading slash would resolve against the
	// origin and skip the prefix the itch upload actually sits behind.
	await page.goto('index.html');
	await expect(page.locator('canvas')).toBeVisible();
	await page.waitForFunction(
		() => (window.__FISHCHIP_GAME__?.scene.getScenes(true).length ?? 0) > 0,
		undefined,
		{ timeout: 60_000 },
	);
}

const activeScenes = (page: Page) =>
	page.evaluate(
		() => window.__FISHCHIP_GAME__?.scene.getScenes(true).map((scene) => scene.scene.key) ?? [],
	);

test.describe('fish and chip', () => {
	test('boots from a subdirectory with no failed requests', async ({ page }) => {
		const { consoleErrors, failed } = watch(page);

		await booted(page);
		await expect.poll(() => activeScenes(page)).toContain('Preloader');

		// Every asset is fetched relative to the page, so a leading slash or an
		// absolute CDN URL shows up here as a 404 rather than as a missing
		// sprite nobody notices until the itch page is live.
		expect(failed).toEqual([]);
		expect(consoleErrors).toEqual([]);
	});

	test('preloads every asset the scenes ask for', async ({ page }) => {
		await booted(page);

		const loaded = await page.evaluate((keys) => {
			const game = window.__FISHCHIP_GAME__;
			if (!game) return null;
			return {
				textures: keys.textures.filter((key) => !game.textures.exists(key)),
				audio: keys.audio.filter((key) => !game.cache.audio.exists(key)),
				tilemaps: keys.tilemaps.filter((key) => !game.cache.tilemap.exists(key)),
			};
		}, ASSET_KEYS);

		expect(loaded).not.toBeNull();
		expect(loaded).toEqual({ textures: [], audio: [], tilemaps: [] });
	});

	test('starts the town when the menu button is clicked', async ({ page }) => {
		await booted(page);
		await expect.poll(() => activeScenes(page)).toContain('Preloader');

		// The button is drawn on the canvas, so there is no locator for it. Its
		// on-screen position comes from the text object Preloader keeps a
		// reference to, which is also the thing that would move if the menu were
		// ever laid out differently.
		const point = await page.evaluate(() => {
			const game = window.__FISHCHIP_GAME__;
			const preloader = game?.scene.getScene('Preloader') as
				| (Phaser.Scene & { mainMenuButtonText?: Phaser.GameObjects.Text })
				| undefined;
			const button = preloader?.mainMenuButtonText;
			if (!game || !button) return null;

			const canvas = game.canvas.getBoundingClientRect();
			const camera = preloader.cameras.main;
			return {
				x: canvas.left + (button.x - camera.scrollX) * camera.zoom,
				y: canvas.top + (button.y - camera.scrollY) * camera.zoom,
			};
		});

		expect(point, 'Preloader should expose its menu button').not.toBeNull();

		await page.mouse.click(point!.x, point!.y);

		await expect.poll(() => activeScenes(page), { timeout: 60_000 }).toContain('TownScene');
	});

	test('walks the player with the keyboard', async ({ page }) => {
		await booted(page);
		await expect.poll(() => activeScenes(page)).toContain('Preloader');

		// Straight to the town: this test is about input and grid-engine, and
		// going through the menu again would only retest the click.
		await page.evaluate(() => window.__FISHCHIP_GAME__?.scene.start('TownScene'));
		await expect.poll(() => activeScenes(page), { timeout: 60_000 }).toContain('TownScene');

		const position = () =>
			page.evaluate(() => window.__GRID_ENGINE__?.getPosition('player') ?? null);
		await expect.poll(position).not.toBeNull();

		// Row 1 is always clear floor: the generator keeps buildings, props, and
		// landmarks at a margin of 2 or more from the wall. Walking east from
		// (1,1) is therefore unblocked on every seed, where "east of wherever
		// the player spawned" is a coin toss on a generated map.
		await page.evaluate(() => window.__GRID_ENGINE__?.setPosition('player', { x: 1, y: 1 }));
		const start = { x: 1, y: 1 };

		await page.locator('canvas').click({ position: { x: 10, y: 10 } });
		await page.keyboard.down('d');
		await expect.poll(position, { timeout: 30_000 }).not.toEqual(start);
		await page.keyboard.up('d');

		const moved = (await position())!;
		expect(moved.x).toBeGreaterThan(start.x);
		expect(moved.y).toBe(start.y);
	});

	test('refuses to walk into a wall', async ({ page }) => {
		await booted(page);
		await page.evaluate(() => window.__FISHCHIP_GAME__?.scene.start('TownScene'));
		await expect.poll(() => activeScenes(page), { timeout: 60_000 }).toContain('TownScene');

		const position = () =>
			page.evaluate(() => window.__GRID_ENGINE__?.getPosition('player') ?? null);
		await expect.poll(position).not.toBeNull();

		// (1,1) is the inside corner of the enclosure on every seed: the
		// generator keeps buildings, props, and landmarks at a margin of 2 or
		// more, so this tile is always open floor with wall to its west and
		// north. Standing the player there is what makes the assertion
		// seed-independent -- the old version relied on a wall the fixed map
		// happened to have beside the spawn.
		await page.evaluate(() => window.__GRID_ENGINE__?.setPosition('player', { x: 1, y: 1 }));
		const corner = { x: 1, y: 1 };
		expect(await position()).toEqual(corner);

		await page.locator('canvas').click({ position: { x: 10, y: 10 } });
		for (const key of ['a', 'w']) {
			await page.keyboard.down(key);
			await page.waitForTimeout(700);
			await page.keyboard.up(key);
			// Collision comes from the ge_collide property the generator emits,
			// so this fails if that stops being written or the wall gids change.
			expect(await position()).toEqual(corner);
		}
	});

	test('generates a town bigger than the map it replaced', async ({ page }) => {
		await booted(page);
		await page.evaluate(() => window.__FISHCHIP_GAME__?.scene.start('TownScene'));
		await expect.poll(() => activeScenes(page), { timeout: 60_000 }).toContain('TownScene');

		const town = await page.evaluate(() => {
			const map = window.__TOWN__;
			if (!map) return null;
			return {
				width: map.width,
				height: map.height,
				landmarks: Object.keys(map.landmarks).sort(),
				layers: map.layers.map((layer) => layer.name),
			};
		});

		expect(town).not.toBeNull();
		expect(town!.width * town!.height).toBeGreaterThan(20 * 20);
		expect(town!.landmarks).toEqual(['building', 'fishingPit', 'sign', 'tombstone']);
		expect(town!.layers).toEqual(['ground', 'buildings', 'objects']);
	});

	// The landmark system, end to end: the generator places a landmark, the
	// scene turns its position into an interaction, and F acts on it. The
	// building and the tombstone used to reach a console.log, so "does F do
	// anything here" is the whole question.
	test.describe('landmarks', () => {
		for (const [landmark, scene] of [
			['fishingPit', 'FishChipScene'],
			['sign', 'CreditsScene'],
			['building', 'MarketScene'],
		] as const) {
			test(`${landmark} opens ${scene}`, async ({ page }) => {
				await booted(page);
				await page.evaluate(() => window.__FISHCHIP_GAME__?.scene.start('TownScene'));
				await expect.poll(() => activeScenes(page), { timeout: 60_000 }).toContain('TownScene');

				// Stand on the landmark rather than walking to it: pathing across a
				// generated town is not what this test is about, and the seed
				// changes every run.
				await page.evaluate((name) => {
					const spot = window.__TOWN__!.landmarks[name];
					// The building landmark is its doorway, which is solid; the
					// player stands on the approach tile below it.
					const stand = name === 'building' ? { x: spot.x, y: spot.y + 1 } : spot;
					window.__GRID_ENGINE__?.setPosition('player', stand);
				}, landmark);

				await page.locator('canvas').click({ position: { x: 10, y: 10 } });
				await page.keyboard.press('f');

				await expect.poll(() => activeScenes(page), { timeout: 30_000 }).toContain(scene);
			});
		}
	});
});
