import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { contractPlugin } from './src/plugins/contract.ts';

const crossOriginIsolation = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
};

export default defineConfig({
  base: './',
  plugins: [contractPlugin(), react()],
  // &stale -> hashed bundles plus an emptied outDir means any page still holding
  //           a previous index.html asks for a file that no longer exists and
  //           dies on a 404. Keeping old bundles costs a few KB and makes a
  //           mid-rebuild reload survivable, which matters when testing on a
  //           device that reloads on its own.
  build: { emptyOutDir: false },
  server: { port: 5173, host: true, headers: crossOriginIsolation },
  preview: { headers: crossOriginIsolation },
});
