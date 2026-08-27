/** Site-wide defaults. Per-page frontmatter overrides any of these. */
export const site = {
  name: 'RentEarth',
  /** Falls back into <title> and og:site_name when a page gives nothing. */
  description: 'RentEarth',
  /** Social card, relative to the site root. Absent until one exists: an
   *  og:image pointing at a 404 is worse than no og:image. */
  image: undefined as string | undefined,
  /** Paints browser chrome before CSS loads; matches --bg in the dark palette. */
  themeColor: '#14150f',
} as const;
