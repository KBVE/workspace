import { expect, type Page } from '@playwright/test';

/**
 * &swiftshader -> the runner draws on software GL by flag, which is precisely what
 *                 GpuWarning is there to report. It is a modal, so it sits over
 *                 everything a test wants to click until it is acknowledged.
 */
export async function dismissGpuWarning(page: Page) {
  const dismiss = page.getByTestId('gpu-warning-dismiss');
  if (await dismiss.count()) await dismiss.click();
}

export async function booted(page: Page) {
  await page.goto('/index.html');
  await expect(page.locator('#godot-canvas')).toBeVisible();
  await dismissGpuWarning(page);
  // &live -> the curtain lifts on the first real scene, not when the engine
  //          merely started, so this is the point the run is actually on screen
  await expect(page.getByTestId('boot-curtain')).toHaveAttribute('aria-hidden', 'true');
}
