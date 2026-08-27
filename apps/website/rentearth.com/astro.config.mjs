import { defineConfig } from 'astro/config';

// Static output: every page is rendered at build time and the API is called
// from the browser, which is why the wire types matter here.
export default defineConfig({
  output: 'static',
  site: 'https://rentearth.com',
});
