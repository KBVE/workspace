import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';
import { locales } from '@kbve/i18n';

/**
 * Prose pages authored as MDX, one directory per locale: `pages/en/about.mdx`
 * is the English About page and `pages/es/about.mdx` its translation.
 *
 * `locale` is not written in frontmatter. It is derived from the directory and
 * validated against the registered locale list, so a file under an
 * unregistered directory fails the build instead of never being routed.
 */
const pages = defineCollection({
  loader: glob({ base: './src/content/pages', pattern: '**/*.{md,mdx}' }),
  schema: z
    .object({
      title: z.string().min(1),
      // 160 is what a search result shows before truncating.
      description: z.string().min(1).max(160).optional(),
      draft: z.boolean().default(false),
      // Ordering for any generated index; unset sorts last.
      order: z.number().int().nonnegative().optional(),

      // --- SEO ---------------------------------------------------------
      /** Social card, relative to the site root. */
      image: z.string().startsWith('/').optional(),
      /** Alt text for that card; required alongside an image so the schema
       *  cannot produce an inaccessible one. */
      imageAlt: z.string().optional(),
      /** Keep the page out of search results while leaving it reachable. */
      noindex: z.boolean().default(false),
      /** Points elsewhere when this page restates content that lives at
       *  another canonical URL. */
      canonical: z.string().url().optional(),
      publishedAt: z.coerce.date().optional(),
      updatedAt: z.coerce.date().optional(),
    })
    .strict()
    .refine((data) => !data.image || Boolean(data.imageAlt), {
      message: 'imageAlt is required when image is set',
      path: ['imageAlt'],
    }),
});

export const collections = { pages };

/** Built here rather than in @kbve/i18n so the zod instance is the one Astro
 *  ships, not a second copy pinned by the package. */
export const localeSchema = z.enum(locales);
