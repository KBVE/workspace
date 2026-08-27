import { memo } from 'react';
import { useTrace, type TracedEvent } from '../state/gameStore';
import styles from './debug.module.css';

const TraceRow = memo(function TraceRow({ entry }: { entry: TracedEvent }) {
  return (
    <li data-testid="trace-item">
      <code data-testid="trace-event">{entry.event}</code>
      <span>{JSON.stringify(entry.payload)}</span>
    </li>
  );
});

export function EventTrace() {
  const trace = useTrace();

  return (
    <>
      <div className={styles.sectionHead}>
        events <span data-testid="trace-count">{trace.length}</span>
      </div>
      <ol className={styles.list}>
        {trace.map((entry) => (
          <TraceRow key={entry.seq} entry={entry} />
        ))}
        {trace.length === 0 && (
          <li className={styles.empty} data-testid="trace-empty">
            nothing yet
          </li>
        )}
      </ol>
    </>
  );
}
