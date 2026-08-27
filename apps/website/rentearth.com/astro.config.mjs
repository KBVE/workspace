import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';
import { locales, defaultLocale } from '@kbve/i18n';

// Static output: every page is rendered at build time and served as a file.
export default defineConfig({
  output: 'static',
  // Astro's own prefetch: hover-intent rather than eager, and it stays correct
  // as the page count grows. Costs ~1.1 kB gzipped.
  prefetch: { prefetchAll: true, defaultStrategy: 'hover' },
  site: 'https://rentearth.com',
  // One URL per page. Without this the canonical tag, the sitemap and the
  // hreflang alternates can disagree on a trailing slash, which search engines
  // read as separate URLs.
  trailingSlash: 'never',
  integrations: [mdx(), sitemap()],

  // Astro owns routing; @kbve/i18n owns the list. Registering a language is one
  // entry in the package plus a directory under src/content/pages — this file
  // never changes.
  i18n: {
    defaultLocale,
    locales: [...locales],
    routing: {
      prefixDefaultLocale: false,
      redirectToDefaultLocale: false,
    },
  },
  build: {
    // Sheets under the threshold are inlined, which keeps a page to one request.
    inlineStylesheets: 'auto',
  },
});
