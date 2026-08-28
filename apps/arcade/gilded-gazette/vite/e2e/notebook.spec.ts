import { test, expect, type Page } from '@playwright/test';
import { booted } from './harness';
import { readFileSync } from 'node:fs';

/**
 * Read rather than imported. This file runs in Node under Playwright, where a JSON
 * import needs an import attribute the app's own bundler never asks for, and a test
 * is not the place to carry a second module convention.
 */
interface Compiled {
  passengers: { id: string }[];
  items: { id: string; kind: string; model?: string }[];
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
/**
 * Everybody aboard. Which of them is the body is drawn per run and arrives on the
 * wire, so a spec cannot know it in advance -- what it can assert is the shape: all
 * but one of these are listed, and the one missing is the one the engine named.
 */
const ABOARD = content.passengers.map((p) => p.id);
/**
 * The model is what makes a weapon nameable: it is what lets the run put the thing in
 * a room to be found. TheNight draws from the same rule, so these are the weapons the
 * answer can be.
 */
const WEAPONS = content.items
  .filter((i) => i.kind === 'weapon' && i.model)
  .map((i) => i.id);
const UNMODELLED = content.items
  .filter((i) => i.kind === 'weapon' && !i.model)
  .map((i) => i.id);
const ROOMS = content.locations.filter((l) => typeof l.carriage === 'number').map((l) => l.id);

async function openNotebook(page: Page) {
  await page.getByTestId('open-dossier').click();
  await expect(page.getByTestId('notebook')).toBeVisible();
}

function row(page: Page, key: string) {
  return page.getByTestId(`notebook-${key}`);
}

/**
 * Somebody the sheet is actually listing. The body is drawn per run, so a spec that
 * picked a name out of the content would pick the corpse one run in eight and fail
 * for a reason that has nothing to do with what it is testing.
 */
async function aLivingName(page: Page): Promise<string> {
  for (const id of ABOARD) {
    if ((await row(page, `suspect:${id}`).count()) > 0) return id;
  }
  throw new Error('the sheet lists nobody at all');
}

test('the sheet lists every answer the run could give', async ({ page }) => {
  await booted(page);
  await openNotebook(page);

  expect(ABOARD.length).toBeGreaterThan(2);
  const listed = await page.getByTestId(/^notebook-suspect:/).count();
  expect(listed).toBe(ABOARD.length - 1);
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

  // The body is drawn, so which name is missing changes per run -- exactly one is,
  // and it is the one the engine named as the enquiry opened.
  const missing = [];
  for (const id of ABOARD) {
    if ((await row(page, `suspect:${id}`).count()) === 0) missing.push(id);
  }
  expect(missing).toHaveLength(1);
  await expect(page.getByTitle('The body')).toHaveCount(2);

  await expect(row(page, 'room:platform')).toHaveCount(0);

  // A weapon with no model cannot be put in a room, so nothing the player does could
  // ever bear on it. Real content, and not an answer.
  for (const id of UNMODELLED) await expect(row(page, `weapon:${id}`)).toHaveCount(0);
});

test('a pencil mark goes on, changes, and comes off', async ({ page }) => {
  await booted(page);
  await openNotebook(page);

  const first = row(page, `suspect:${await aLivingName(page)}`);
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

  const alive = await aLivingName(page);
  await row(page, `suspect:${alive}`).click();
  await row(page, `room:${ROOMS[0]}`).click();
  await expect(rub).toBeEnabled();

  await rub.click();
  await expect(row(page, `suspect:${alive}`)).toHaveAttribute('data-mark', 'clear');
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

  const marked = row(page, `suspect:${await aLivingName(page)}`);
  await marked.click();
  await expect(marked).toHaveAttribute('data-mark', 'out');

  await page.getByLabel('Close the case board').click();
  await page.getByTestId('open-dossier').click();
  await expect(marked).toHaveAttribute('data-mark', 'out');
});
