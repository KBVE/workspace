import { defineConfig, devices } from '@playwright/test';

const PORT = 8110;
const PREFIX = '/html';

export default defineConfig({
	testDir: './e2e',
	// Traces and screenshots stay beside the tests that produced them. The
	// default is a test-results/ directory at the project root, which lands in
	// `git status` as an untracked pile of binaries after the first failure.
	outputDir: './e2e/.artifacts',
	// Phaser boots a WebGL context and pulls ~2MB of assets before the menu
	// appears. On a runner that is software GL, so the budgets are generous.
	timeout: 120_000,
	expect: { timeout: 30_000 },
	fullyParallel: false,
	workers: 1,
	reporter: [['list']],
	use: {
		// Trailing slash matters: a relative goto('index.html') resolves against
		// the last path segment, and without it every request would land at the
		// origin root instead of inside the prefix.
		baseURL: `http://127.0.0.1:${PORT}${PREFIX}/`,
		trace: 'retain-on-failure',
		// The game's scale config has a 1024x768 minimum; a smaller viewport
		// letterboxes it and moves every on-screen coordinate the tests click.
		viewport: { width: 1280, height: 800 },
	},
	projects: [
		{
			name: 'chromium',
			use: {
				...devices['Desktop Chrome'],
				// CI runners have no GPU, and Phaser.AUTO would silently fall back
				// to canvas there while using WebGL locally -- two different
				// renderers under test. swiftshader keeps it WebGL on both.
				launchOptions: { args: ['--enable-unsafe-swiftshader'] },
			},
		},
	],
	webServer: {
		command: `node e2e/server.mjs dist ${PORT} ${PREFIX}`,
		url: `http://127.0.0.1:${PORT}${PREFIX}/index.html`,
		reuseExistingServer: !process.env.CI,
		timeout: 60_000,
	},
});
