// vitest/config, not vite: the `test` block below is vitest's extension of
// vite's config type, and vite's own defineConfig rejects it.
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import dts from 'vite-plugin-dts';
import * as path from 'node:path';

// Ported from the Nx workspace. Two Nx plugins were dropped rather than
// replaced: nxViteTsPaths resolved `@kbve/laser` through tsconfig.base.json,
// which this repository does not have -- the pnpm workspace link does the same
// job -- and nxCopyAssetsPlugin copied the README, which tools/pack.mjs
// now does alongside the manifest.
//
// Build output stays inside the project (`dist`) instead of a workspace-level
// dist/packages/npm/laser, because moon hashes task outputs by project.
export default defineConfig({
  root: __dirname,

  plugins: [
    react(),
    dts({
      entryRoot: 'src',
      tsconfigPath: path.join(__dirname, 'tsconfig.lib.json'),
      outDir: 'dist',
    }),
  ],

  build: {
    outDir: 'dist',
    emptyOutDir: true,
    reportCompressedSize: true,
    lib: {
      // One entry per subpath export in package.json. The split is load-bearing
      // and asserted by src/entrypoints.spec.ts: every optional peer below is
      // reachable from exactly one entry, so a consumer that imports
      // `@kbve/laser/ecs` never has to install three or phaser.
      entry: {
        index: path.resolve(__dirname, 'src/index.ts'),
        ecs: path.resolve(__dirname, 'src/ecs.ts'),
        mecs: path.resolve(__dirname, 'src/mecs.ts'),
        phaser: path.resolve(__dirname, 'src/phaser.ts'),
        rapier: path.resolve(__dirname, 'src/rapier.ts'),
        r3f: path.resolve(__dirname, 'src/r3f.ts'),
      },
      fileName: (format, entryName) =>
        entryName === 'index'
          ? `laser.${format}.js`
          : `${entryName}.${format}.js`,
      formats: ['es'],
    },
    rollupOptions: {
      // Every peer dependency. Bundling any of them would ship a second copy of
      // React or three into a consumer that already has one.
      external: [
        'react',
        'react-dom',
        'react/jsx-runtime',
        'phaser',
        'three',
        '@react-three/fiber',
        '@react-three/drei',
        'bitecs',
        '@phaserjs/rapier-connector',
        'fastnoise-lite',
      ],
    },
  },

  test: {
    globals: true,
    watch: false,
    environment: 'jsdom',
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
    reporters: ['default'],
    coverage: {
      reportsDirectory: 'coverage',
      provider: 'v8',
      reporter: ['text-summary', 'json-summary'],
      // `include` is what makes this measure the files the package ships
      // rather than only the ones a test happened to import -- without it,
      // deleting a spec would raise the percentage. (vitest 3 needed `all:
      // true` alongside it; vitest 4 removed the option and made it default.)
      include: ['src/**/*.{ts,tsx}'],
      exclude: [
        'src/**/*.{spec,test}.{ts,tsx}',
        'src/**/*.testing.ts',
        'src/types/**',
        // Type-only re-exports compile to nothing, so they have no statement
        // for v8 to instrument and would sit at 0% forever.
        'src/lib/phaser/types.ts',
        'src/lib/r3f/types.ts',
      ],
    },
  },
});
