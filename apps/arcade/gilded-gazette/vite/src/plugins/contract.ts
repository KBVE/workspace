import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import type { Plugin } from 'vite';

const ROOT = resolve(import.meta.dirname, '../../..');
const GENERATOR = resolve(ROOT, 'tools/gen-contract.mjs');
const SOURCES = ['shared/state.json', 'shared/events.json'].map((p) => resolve(ROOT, p));

function generate(): void {
  execFileSync(process.execPath, [GENERATOR], { stdio: 'inherit' });
}

export function contractPlugin(): Plugin {
  return {
    name: 'gilded-gazette-contract',
    config: generate,
    configureServer(server) {
      SOURCES.forEach((file) => server.watcher.add(file));
      server.watcher.on('change', (file) => {
        if (!SOURCES.includes(resolve(file))) return;
        server.config.logger.info(`contract: ${file} changed, regenerating`);
        try {
          generate();
        } catch (error) {
          server.config.logger.error(`contract: generation failed\n${error}`);
        }
      });
    },
  };
}
