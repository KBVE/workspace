import { memo } from 'react';
import { journalKindName } from '../godot/state';
import { useJournal } from '../state/gameStore';
import styles from './debug.module.css';

const clockFace = (minutesPastMidnight: number): string =>
  minutesPastMidnight < 0
    ? '--:--'
    : `${String(Math.floor(minutesPastMidnight / 60)).padStart(2, '0')}:` +
      `${String(minutesPastMidnight % 60).padStart(2, '0')}`;

const Entry = memo(function Entry({ entry }: { entry: ReturnType<typeof useJournal>[number] }) {
  const participants = [entry.actor, entry.target, entry.place].filter(Boolean).join(' → ');
  return (
    <li data-testid="journal-item" title={entry.id}>
      <code data-testid="journal-kind">{journalKindName(entry.kind).toLowerCase()}</code>
      <span>
        {clockFace(entry.at)} {participants}
      </span>
    </li>
  );
});

export function JournalLog() {
  const journal = useJournal();

  return (
    <>
      <div className={styles.sectionHead}>
        journal <span data-testid="journal-count">{journal.length}</span>
      </div>
      <ol className={styles.list}>
        {journal.map((entry) => (
          <Entry key={entry.id} entry={entry} />
        ))}
        {journal.length === 0 && (
          <li className={styles.empty} data-testid="journal-empty">
            nothing recorded
          </li>
        )}
      </ol>
    </>
  );
}
