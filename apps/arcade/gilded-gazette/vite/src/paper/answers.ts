import {
  items,
  listedAs,
  locations,
  passengers,
  type Item,
  type LocationId,
} from '../content/content';

/**
 * The three questions an accusation answers, and every answer the run could give to
 * each. Read off the compiled content rather than written down, so a passenger added
 * to shared/data appears in both the notebook and the accusation without either
 * knowing they exist.
 *
 * Shared by the two of them on purpose. A sheet listing one set of answers beside a
 * form offering another is a sheet that can be filled in with something the form will
 * not accept, and the reader would be right to call that the game's fault.
 */
export interface Answer {
  id: string;
  label: string;
}

/**
 * Everybody aboard who is not the body, which is exactly the set TheNight draws its
 * culprit from. Who the body is arrives on the wire, so it is a parameter: before the
 * enquiry opens this lists everybody, which is the honest answer for the half second
 * before the engine has said.
 */
export const suspects = (victim: string): Answer[] =>
  passengers.filter((p) => p.id !== victim).map((p) => ({ id: p.id, label: listedAs(p) }));

/**
 * The weapons the run can name, which are the ones it can also put in a room: the
 * model is the qualification, not the kind. A weapon with no model cannot be placed
 * aboard, so it cannot be found, and naming it would be a guess between things the
 * player never saw.
 */
export const weapons = (): Answer[] =>
  items
    .filter((i: Item) => i.kind === 'weapon' && i.model)
    .map((i) => ({ id: i.id, label: i.name }));

/**
 * Rooms in the consist, and not the platform. The platform is where people were before
 * they were passengers; nobody is killed there and TheNight will not put the scene
 * there either.
 */
export const rooms = (): Answer[] =>
  locations
    .filter((l) => typeof l.carriage === 'number')
    .map((l) => ({ id: l.id as LocationId, label: l.name }));

/**
 * What to call one answer, whichever of the three columns it belongs to.
 *
 * The lists above are what can be chosen; this is for printing back something already
 * chosen -- the verdict names the culprit, and the culprit is not in `suspects()` when
 * the reader has been told who the body is and the body did it, which cannot happen,
 * or when they simply picked from a list this function was not given. Falling back to
 * the raw id is on purpose: an id on screen is a content bug somebody can see, and a
 * blank is the same bug hidden.
 */
export const nameOf = (part: 'who' | 'weapon' | 'room', id: string): string => {
  if (!id) return '';
  if (part === 'who') {
    const passenger = passengers.find((p) => p.id === id);
    return passenger ? listedAs(passenger) : id;
  }
  if (part === 'weapon') return items.find((i) => i.id === id)?.name ?? id;
  return locations.find((l) => l.id === id)?.name ?? id;
};
