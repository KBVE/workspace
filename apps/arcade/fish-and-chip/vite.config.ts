/// <reference types="vitest/config" />
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
	// itch.io serves an uploaded HTML build from a hashed subdirectory, not
	// from the domain root, so every asset URL has to be relative. This is the
	// one setting that decides whether the itch upload boots or shows a blank
	// page, and it costs nothing when serving the same build from a root.
	base: './',

	plugins: [react()],

	// laser is consumed from source, not from its dist. Its published
	// package.json points at built files that only exist under packages/laser/
	// dist, so a workspace link to the package root does not resolve; aliasing
	// the entry points keeps types live and means the app does not need laser
	// built before it can run. The subpath alias has to come first -- '@kbve/
	// laser' is a prefix of '@kbve/laser/phaser'.
	resolve: {
		alias: [
			{
				find: '@kbve/laser/phaser',
				replacement: resolve(dirname(fileURLToPath(import.meta.url)), '../../../packages/laser/src/phaser.ts'),
			},
			{
				find: '@kbve/laser',
				replacement: resolve(dirname(fileURLToPath(import.meta.url)), '../../../packages/laser/src/index.ts'),
			},
		],
	},

	server: { port: 4200 },
	preview: { port: 4300 },

	build: {
		outDir: 'dist',
		emptyOutDir: true,
		// Phaser is a single 1MB+ chunk no matter how it is split, so the
		// warning fires on every build and says nothing new.
		chunkSizeWarningLimit: 2000,
	},

	test: {
		globals: true,
		environment: 'jsdom',
		setupFiles: ['src/test/setup.ts'],
		include: ['src/**/*.{test,spec}.{ts,tsx}'],
	},
});
