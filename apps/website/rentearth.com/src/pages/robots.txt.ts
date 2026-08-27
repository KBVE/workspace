import type { APIRoute } from 'astro';

/**
 * Generated rather than static so the sitemap URL comes from `site` in
 * astro.config.mjs and cannot fall out of step with it.
 */
export const GET: APIRoute = ({ site }) => {
  const sitemap = new URL('sitemap-index.xml', site).toString();

  return new Response(
    `User-agent: *
Allow: /

Sitemap: ${sitemap}
`,
    { headers: { 'Content-Type': 'text/plain; charset=utf-8' } },
  );
};
