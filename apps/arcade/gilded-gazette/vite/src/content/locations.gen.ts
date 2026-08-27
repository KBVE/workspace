/**
 * GENERATED FILE - DO NOT EDIT.
 *
 * Source: shared/data/locations/*.mdx
 * Regenerate: npm run gen (from vite/). Runs automatically on dev and build.
 */

/** Somewhere a passenger, an item or the player can be. */
export type LocationId =
  | 'guard_van'
  | 'dining'
  | 'corridor'
  | 'cabin'
  | 'vestibule'
  | 'platform';

/** Every location, the consist in order and then anywhere off the train. */
export const LOCATION_IDS: readonly LocationId[] = ['guard_van', 'dining', 'corridor', 'cabin', 'vestibule', 'platform'] as const;

/** Every location that is a place in the consist, by index along the train. */
export const CARRIAGE_LOCATION_IDS: readonly LocationId[] = ['guard_van', 'dining', 'corridor', 'cabin', 'vestibule'] as const;
