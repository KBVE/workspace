import { test, expect, type Page } from '@playwright/test';
import { booted } from './harness';
import { readFileSync } from 'node:fs';

/**
 * Read rather than imported. This file runs in Node under Playwright, where a JSON
 * import needs an import attribute the app's own bundler never asks for, and a test
 * is not the place to carry a second module convention.
 */
interface Compiled {
  passengers: { id: string; suspect?: boolean; victim?: boolean }[];
  items: { id: string; kind: string }[];
  locations: { id: string; carriage?: number }[];
}
const content = JSON.parse(
  readFileSync(new URL('../src/content/content.gen.json', import.meta.url), 'utf8'),
) as Compiled;

/**
 * The reader's own sheet: three columns of everything the answer could be, marked
 * with a pencil. What is worth asserting is not that it renders but that it is
 * true -- a sheet listing a suspect the run can never name would be crossed off by
 * playing enough runs rather than by deducing anything.
 *
 * The expected rows are read out of the compiled content rather than written down,
 * so adding a passenger to shared/data fails here until the sheet lists them.
 */
const SUSPECTS = content.passengers.filter((p) => p.suspect).map((p) => p.id);
const WEAPONS = content.items.filter((i) => i.kind === 'weapon').map((i) => i.id);
const ROOMS = content.locations.filter((l) => typeof l.carriage === 'number').map((l) => l.id);

async function openNotebook(page: Page) {
  await page.getByTestId('open-dossier').click();
  await expect(page.getByTestId('notebook')).toBeVisible();
}

function row(page: Page, key: string) {
  return page.getByTestId(`notebook-${key}`);
}

test('the sheet lists every answer the run could give', async ({ page }) => {
  await booted(page);
  await openNotebook(page);

  expect(SUSPECTS.length).toBeGreaterThan(1);
  for (const id of SUSPECTS) await expect(row(page, `suspect:${id}`)).toBeVisible();
  for (const id of WEAPONS) await expect(row(page, `weapon:${id}`)).toBeVisible();
  for (const id of ROOMS) await expect(row(page, `room:${id}`)).toBeVisible();
});

/**
 * The victim is not on it, and neither is the platform. Both are answers the run
 * cannot give -- the body cannot have done it, and TheNight will not put the scene
 * somewhere nobody is aboard yet.
 */
test('the sheet leaves off what the answer can never be', async ({ page }) => {
  await booted(page);
  await openNotebook(page);

  const victim = content.passengers.find((p) => p.victim)!;
  await expect(row(page, `suspect:${victim.id}`)).toHaveCount(0);
  await expect(row(page, 'room:platform')).toHaveCount(0);
});

test('a pencil mark goes on, changes, and comes off', async ({ page }) => {
  await booted(page);
  await openNotebook(page);

  const first = row(page, `suspect:${SUSPECTS[0]}`);
  await expect(first).toHaveAttribute('data-mark', 'clear');
  await first.click();
  await expect(first).toHaveAttribute('data-mark', 'out');
  await first.click();
  await expect(first).toHaveAttribute('data-mark', 'likely');
  await first.click();
  await expect(first).toHaveAttribute('data-mark', 'clear');
});

test('rubbing out clears the sheet, and is offered only when there is something to rub', async ({
  page,
}) => {
  await booted(page);
  await openNotebook(page);

  const rub = page.getByTestId('notebook-clear');
  await expect(rub).toBeDisabled();

  await row(page, `suspect:${SUSPECTS[0]}`).click();
  await row(page, `room:${ROOMS[0]}`).click();
  await expect(rub).toBeEnabled();

  await rub.click();
  await expect(row(page, `suspect:${SUSPECTS[0]}`)).toHaveAttribute('data-mark', 'clear');
  await expect(row(page, `room:${ROOMS[0]}`)).toHaveAttribute('data-mark', 'clear');
  await expect(rub).toBeDisabled();
});

/**
 * The sheet is state, not markup. Closing the board unmounts nothing that matters,
 * and a reader who shuts it to look out of the window has not changed their mind.
 */
test('marks survive the board being closed', async ({ page }) => {
  await booted(page);
  await openNotebook(page);

  const marked = row(page, `suspect:${SUSPECTS[1]}`);
  await marked.click();
  await expect(marked).toHaveAttribute('data-mark', 'out');

  await page.getByLabel('Close the case board').click();
  await page.getByTestId('open-dossier').click();
  await expect(row(page, `suspect:${SUSPECTS[1]}`)).toHaveAttribute('data-mark', 'out');
});
