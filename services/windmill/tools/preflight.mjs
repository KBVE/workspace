// Refuses to sync when the private scripts are still encrypted.
//
// A locked clone has ciphertext in the working tree, and `wmill sync push`
// reads the working tree. Without this check a runner missing the git-crypt
// key pushes AES blobs into Windmill as script bodies and reports success:
// the private scripts are then broken in the instance with nothing in the log
// to say why. `pull` has the mirror problem -- it writes plaintext over
// ciphertext, and every private file then looks like drift.
//
// git-crypt writes a nine byte header, \0GITCRYPT\0, at the start of each
// encrypted blob. Checking for it is the whole test.

import { execFileSync } from 'node:child_process';
import { openSync, readSync, closeSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Resolved from this file rather than from cwd: moon runs the task with the
// project as the working directory, but a `node services/windmill/tools/...`
// from the repo root would otherwise match nothing under f/ and pass without
// having checked anything.
const project = dirname(dirname(fileURLToPath(import.meta.url)));
const scripts = join(project, 'f');

const MAGIC = Buffer.from('\0GITCRYPT\0', 'binary');

const tracked = execFileSync('git', ['ls-files', '-z', '--', scripts], {
  cwd: project,
})
  .toString('utf8')
  .split('\0')
  .filter(Boolean);

if (tracked.length === 0) {
  console.log('Nothing tracked under f/ yet.');
  process.exit(0);
}

// One call for every path rather than one per path: check-attr reads the
// whole list on stdin and answers in the same order.
const attrs = execFileSync('git', ['check-attr', '--stdin', '-z', 'filter'], {
  input: Buffer.from(tracked.join('\0'), 'utf8'),
  cwd: project,
})
  .toString('utf8')
  .split('\0');

const encrypted = [];
for (let i = 0; i + 2 < attrs.length; i += 3) {
  if (attrs[i + 2] === 'git-crypt') encrypted.push(attrs[i]);
}

const locked = encrypted.filter((path) => {
  const head = Buffer.alloc(MAGIC.length);
  const fd = openSync(join(project, path), 'r');
  try {
    return readSync(fd, head, 0, MAGIC.length, 0) === MAGIC.length && head.equals(MAGIC);
  } finally {
    closeSync(fd);
  }
});

if (locked.length > 0) {
  console.error(
    `${locked.length} private script(s) are still encrypted in the working tree:\n` +
      locked.map((path) => `  ${path}`).join('\n') +
      '\n\nRun `git-crypt unlock` before syncing. Pushing now would upload the\n' +
      'ciphertext to Windmill as the script body, and it would report success.',
  );
  process.exit(1);
}

console.log(`Preflight passed: ${encrypted.length} private script(s) are readable.`);
