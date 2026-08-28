import { test, expect, type Page } from '@playwright/test';
import { booted } from './harness';

/**
 * The run's one irreversible move, from the browser side.
 *
 * The engine's own suite already proves the verdict: the whole answer wins, each third
 * of it wrong loses, and a part that is not a thing at all is refused. What it cannot
 * prove is that the form in front of the reader reaches it -- that a name chosen in one
 * list, a weapon in another and a room in a third arrive together as one accusation.
 * That is what these are for.
 *
 * They deliberately do not check who won. The answer is drawn per run and the browser
 * is never told it, which is the whole point of not sending the culprit across; a test
 * that knew would be a test proving the boundary leaks.
 */
async function openBoard(page: Page) {
  await page.getByTestId('open-dossier').click();
  await expect(page.getByTestId('accusation')).toBeVisible();
}

async function optionsOf(page: Page, part: 'who' | 'weapon' | 'room'): Promise<string[]> {
  return page
    .getByTestId(`accuse-${part}`)
    .locator('option')
    .evaluateAll((options) =>
      options.map((o) => (o as HTMLOptionElement).value).filter(Boolean),
    );
}

test('an accusation needs all three parts before it can be given', async ({ page }) => {
  await booted(page);
  await openBoard(page);

  const accuse = page.getByTestId('accuse');
  await expect(accuse).toBeDisabled();

  await page.getByTestId('accuse-who').selectOption((await optionsOf(page, 'who'))[0]);
  await expect(accuse).toBeDisabled();

  await page.getByTestId('accuse-weapon').selectOption((await optionsOf(page, 'weapon'))[0]);
  await expect(accuse).toBeDisabled();

  await page.getByTestId('accuse-room').selectOption((await optionsOf(page, 'room'))[0]);
  await expect(accuse).toBeEnabled();
});

test('naming somebody in the manifest puts them in the accusation', async ({ page }) => {
  await booted(page);
  await openBoard(page);

  const who = (await optionsOf(page, 'who'))[1];
  await page.getByTestId(`name-${who}`).click();
  await expect(page.getByTestId('accuse-who')).toHaveValue(who);
});

/**
 * The whole point of the boundary: the browser is handed the body and never the
 * answer, so the accusation is given without either side of this test knowing whether
 * it is right. What is asserted is that it lands -- the enquiry closes.
 */
test('the accusation crosses to the engine and closes the enquiry', async ({ page }) => {
  await booted(page);
  await openBoard(page);

  await page.getByTestId('accuse-who').selectOption((await optionsOf(page, 'who'))[0]);
  await page.getByTestId('accuse-weapon').selectOption((await optionsOf(page, 'weapon'))[0]);
  await page.getByTestId('accuse-room').selectOption((await optionsOf(page, 'room'))[0]);

  await page.getByTestId('accuse').click();

  await expect(page.getByTestId('accusation-closed')).toBeVisible();
  await expect(page.getByTestId('accuse')).toBeDisabled();
  await expect(page.getByTestId('accuse-who')).toBeDisabled();
});

/**
 * And the lists it offers are the lists the engine will accept. The body cannot have
 * done it and the platform is not somewhere it can have happened -- the engine refuses
 * both, so offering either would be the form inviting an accusation that is thrown away
 * without a verdict.
 */
test('the accusation offers nothing the engine would refuse', async ({ page }) => {
  await booted(page);
  await openBoard(page);

  expect(await optionsOf(page, 'room')).not.toContain('platform');

  const named = await optionsOf(page, 'who');
  const listed = await page.getByTestId(/^notebook-suspect:/).count();
  expect(named).toHaveLength(listed);
});
