import { defineConfig, devices } from '@playwright/test';

const PORT = 8100;

export default defineConfig({
  testDir: './e2e',
  // &slow -> a scene swap streams a whole Maaack menu tree in wasm, and a CI
  //          runner does it on software GL. Locally that load lands at ~60s;
  //          the runner is slower still, so the budgets are set well past it.
  timeout: 300_000,
  expect: { timeout: 120_000 },
  fullyParallel: false,
  workers: 1,
  reporter: process.env.CI ? 'list' : [['list']],
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
    trace: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        launchOptions: { args: ['--enable-unsafe-swiftshader'] },
      },
    },
  ],
  webServer: {
    command: `node e2e/server.mjs dist ${PORT}`,
    url: `http://127.0.0.1:${PORT}/index.html`,
    reuseExistingServer: !process.env.CI,
    timeout: 90_000,
  },
});
