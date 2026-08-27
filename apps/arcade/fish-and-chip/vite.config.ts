/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
	// itch.io serves an uploaded HTML build from a hashed subdirectory, not
	// from the domain root, so every asset URL has to be relative. This is the
	// one setting that decides whether the itch upload boots or shows a blank
	// page, and it costs nothing when serving the same build from a root.
	base: './',

	plugins: [react()],

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
