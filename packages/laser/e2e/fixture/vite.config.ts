import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import * as path from 'node:path';

const here = import.meta.dirname;

// The app the e2e specs drive. It is a fixture, not a project: it exists only
// to mount laser's two renderer entry points in a real browser, so it lives
// under the package it tests rather than in the sibling `laser-e2e` project
// Nx needed (an Nx executor binds to a project, so a served app had to be one).
//
// laser is aliased to SOURCE, which is how every consumer in the Nx workspace
// took it and what src/entrypoints.spec.ts guards -- see the comment there.
// Resolving through the built dist instead would mean the specs could not run
// until a build had, and would test the bundler as much as the library.
export default defineConfig({
  root: here,
  plugins: [react()],
  resolve: {
    alias: {
      '@kbve/laser/phaser': path.resolve(here, '../../src/phaser.ts'),
      '@kbve/laser/r3f': path.resolve(here, '../../src/r3f.ts'),
      '@kbve/laser/ecs': path.resolve(here, '../../src/ecs.ts'),
      '@kbve/laser/mecs': path.resolve(here, '../../src/mecs.ts'),
      '@kbve/laser': path.resolve(here, '../../src/index.ts'),
    },
  },
  server: {
    // host is pinned rather than left at vite's default `localhost`, which
    // resolves to ::1 on macOS: the server then listens on IPv6 loopback only
    // while playwright polls 127.0.0.1 and times out after a minute with no
    // hint as to why. strictPort keeps a taken 4300 from silently moving the
    // server to 4301 while playwright still waits on 4300.
    host: '127.0.0.1',
    port: 4300,
    strictPort: true,
  },
  build: { outDir: 'dist', emptyOutDir: true },
});
