import { test, expect, type Page } from '@playwright/test';
import { booted } from './harness';

/**
 * The envelope, from the browser side.
 *
 * The engine's suite already proves what the verdict says. What it cannot prove is
 * that it reaches the reader: that giving an accusation opens the reveal, that the
 * reveal prints all three parts whether or not they were had, and that starting
 * another night takes it away again along with the sheet the last one was worked out
 * on.
 *
 * As with the accusation, none of these know who did it. The answer is drawn per run
 * and crosses only once the accusation is given, so a test expecting a particular
 * culprit would be a test of the seed rather than of the page.
 */
async function optionsOf(page: Page, part: 'who' | 'weapon' | 'room'): Promise<string[]> {
  return page
    .getByTestId(`accuse-${part}`)
    .locator('option')
    .evaluateAll((options) =>
      options.map((o) => (o as HTMLOptionElement).value).filter(Boolean),
    );
}

async function accuseAnybody(page: Page) {
  // &toggle -> the button opens and closes the board, so a test that already has it
  //            open would be closing it here and then clicking a button the drawer is
  //            sitting over.
  if (!(await page.getByTestId('accusation').isVisible())) {
    await page.getByTestId('open-dossier').click();
  }
  await expect(page.getByTestId('accusation')).toBeVisible();
  for (const part of ['who', 'weapon', 'room'] as const) {
    await page.getByTestId(`accuse-${part}`).selectOption((await optionsOf(page, part))[0]);
  }
  await page.getByTestId('accuse').click();
}

test('the answer stays in the engine until the accusation is given', async ({ page }) => {
  await booted(page);
  await expect(page.getByTestId('verdict')).toHaveAttribute('aria-hidden', 'true');
  await expect(page.getByTestId('verdict-outcome')).toHaveCount(0);
});

test('giving the accusation opens the envelope', async ({ page }) => {
  await booted(page);
  await accuseAnybody(page);

  await expect(page.getByTestId('verdict')).toHaveAttribute('aria-hidden', 'false');
  await expect(page.getByTestId('verdict-outcome')).toBeVisible();
});

/**
 * All three, right or wrong. A mystery that keeps its answer from somebody who has
 * already lost is not being mysterious; it is refusing to finish.
 */
test('the envelope prints every part of the answer', async ({ page }) => {
  await booted(page);
  await accuseAnybody(page);

  for (const part of ['who', 'weapon', 'room'] as const) {
    const row = page.getByTestId(`verdict-${part}`);
    await expect(row).toBeVisible();
    await expect(row).toHaveAttribute('data-had', /^(yes|no)$/);
    await expect(row).not.toBeEmpty();
  }
});

test('the verdict can be put down and picked up again', async ({ page }) => {
  await booted(page);
  await accuseAnybody(page);

  await page.getByTestId('verdict-board').click();
  await expect(page.getByTestId('verdict')).toHaveAttribute('aria-hidden', 'true');
  await expect(page.getByTestId('dossier')).toHaveAttribute('aria-hidden', 'false');

  await page.getByTestId('reopen-verdict').click();
  await expect(page.getByTestId('verdict')).toHaveAttribute('aria-hidden', 'false');
});

/**
 * A fresh night is a fresh sheet. Marks about somebody else's evening surviving into
 * this one would be the notebook lying about a run it never saw.
 */
test('another night clears the verdict and the sheet with it', async ({ page }) => {
  await booted(page);
  await page.getByTestId('open-dossier').click();

  const pencilled = (await optionsOf(page, 'who'))[0];
  const mark = page.getByTestId(`notebook-suspect:${pencilled}`);
  await mark.click();
  await expect(mark).not.toHaveAttribute('data-mark', 'clear');

  await accuseAnybody(page);
  await page.getByTestId('verdict-again').click();

  await expect(page.getByTestId('verdict')).toHaveAttribute('aria-hidden', 'true');
  await expect(page.getByTestId('accusation-closed')).toHaveCount(0);
  await expect(page.getByTestId('accuse-who')).toBeEnabled();
  await expect(mark).toHaveAttribute('data-mark', 'clear');
});
