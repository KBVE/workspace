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
      description: z.string().min(1).max(160).optional(),
      draft: z.boolean().default(false),
      // Ordering for any generated index; unset sorts last.
      order: z.number().int().nonnegative().optional(),
    })
    .strict(),
});

export const collections = { pages };

/** Built here rather than in @kbve/i18n so the zod instance is the one Astro
 *  ships, not a second copy pinned by the package. */
export const localeSchema = z.enum(locales);
