// Fails when the Windmill instance holds something the repo does not.
//
// `wmill sync pull --dry-run` prints what it would change but always exits 0,
// so it cannot gate a build on its own. Pulling for real and then asking git
// whether anything moved uses a source of truth that does not depend on
// parsing CLI output.
//
// Run this in CI on a clean checkout. Locally it will report your own
// uncommitted work under f/, which is the same signal by a different cause.

import { execFileSync } from 'node:child_process';

const wmill = process.platform === 'win32' ? 'wmill.cmd' : 'wmill';

try {
  execFileSync(wmill, ['sync', 'pull', '--yes'], { stdio: 'inherit' });
} catch (error) {
  console.error('wmill sync pull failed. Is WMILL_TOKEN set for this workspace?');
  process.exit(error.status ?? 1);
}

const changed = execFileSync('git', ['status', '--porcelain', '--', 'f'], {
  encoding: 'utf8',
}).trim();

if (changed) {
  console.error(
    'The Windmill instance is ahead of the repository:\n' +
      changed +
      '\n\nSomeone edited in the UI. Commit this pull rather than pushing over it.',
  );
  process.exit(1);
}

console.log('No drift: the repository matches the instance.');
