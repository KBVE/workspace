import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { readFileSync, writeFileSync, rmSync } from 'node:fs';
import { resolve } from 'node:path';

const OUT = resolve(import.meta.dirname, '../godot/web');

function inlineShell(): Plugin {
  return {
    name: 'inline-shell',
    closeBundle() {
      const html = resolve(OUT, 'shell.html');
      const js = resolve(OUT, 'app.js');
      const css = resolve(OUT, 'app.css');
      const out = readFileSync(html, 'utf8')
        .replace(
          /<script type="module"[^>]*src="[^"]*app\.js"[^>]*><\/script>/,
          () => `<script type="module">\n${readFileSync(js, 'utf8')}\n</script>`,
        )
        .replace(
          /<link rel="stylesheet"[^>]*href="[^"]*app\.css"[^>]*>/,
          () => `<style>\n${readFileSync(css, 'utf8')}\n</style>`,
        );
      writeFileSync(html, out);
      rmSync(js, { force: true });
      rmSync(css, { force: true });
    },
  };
}

export default defineConfig({
  plugins: [react(), inlineShell()],
  base: './',
  publicDir: false,
  build: {
    outDir: OUT,
    emptyOutDir: true,
    rollupOptions: {
      input: resolve(import.meta.dirname, 'shell.html'),
      output: {
        entryFileNames: 'app.js',
        chunkFileNames: 'app-[name].js',
        assetFileNames: 'app.[ext]',
      },
    },
  },
});
