import { defineConfig, devices } from '@playwright/test';

const PORT = 4300;

export default defineConfig({
  testDir: './e2e',
  // Traces stay beside the tests that produced them. Playwright's default is a
  // test-results/ directory at the project root, which shows up in `git status`
  // as untracked binaries after the first failure.
  outputDir: './e2e/.artifacts',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [['list']],
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        // CI runners have no GPU. Without this both Phaser and three fall back
        // to software canvas there while using WebGL locally, which is two
        // different renderers under test.
        launchOptions: { args: ['--enable-unsafe-swiftshader'] },
      },
    },
  ],
  // Nx served this through `nx serve laser-e2e`, which only existed because the
  // fixture was its own project. Vite is invoked directly now.
  webServer: {
    command: 'vite --config e2e/fixture/vite.config.ts',
    url: `http://127.0.0.1:${PORT}`,
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
});
